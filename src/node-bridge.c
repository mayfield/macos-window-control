#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <node_api.h>
#include "../obj/c-lib.swift.h"


typedef struct deferred_tsfn_ctx {
    napi_deferred deferred;
    napi_threadsafe_function tsfn;
} deferred_tsfn_ctx_t;

typedef int (*swift_call_t)(const char *, int, char *, int);
typedef int (*swift_call_noargs_t)(char *, int);
typedef void (*swift_async_call_t)(const char *, int, const void *, const void *);

static sig_atomic_t g_loaded = 0;


// Basically everything in node_api uses this error handling conv...
#define NAPI_CALL(env, the_call)                                   \
    do {                                                           \
        if ((the_call) != napi_ok) {                               \
            ensure_throw((env));                                   \
            return NULL;                                           \
        }                                                          \
    } while (0)


static napi_value get_undefined(napi_env env) {
    napi_value undefined;
    if (napi_get_undefined(env, &undefined) != napi_ok) {
        return NULL;
    }
    return undefined;
}


static void ensure_throw(napi_env env) {
    const napi_extended_error_info *error_info;
    napi_get_last_error_info(env, &error_info);
    bool is_pending;
    const char* err_message = error_info->error_message;
    napi_is_exception_pending(env, &is_pending);
    if (!is_pending) {
        const char* error_message = err_message != NULL ? err_message : "internal error";
        napi_throw_error(env, NULL, error_message);
    }
}


static napi_status reject_deferred(napi_env env, napi_deferred deferred, const char *msg) {
    napi_status status;
    napi_value error_msg, error;
    status = napi_create_string_utf8(env, msg, NAPI_AUTO_LENGTH, &error_msg);
    if (status != napi_ok) {
        return status;
    }
    status = napi_create_error(env, NULL, error_msg, &error);
    if (status != napi_ok) {
        return status;
    }
    return napi_reject_deferred(env, deferred, error);
}


// Runs in main thread..
static void deferred_tsfn(napi_env env, napi_value _jscb, deferred_tsfn_ctx_t *ctx, char *ret_json) {
    if (ctx == NULL) {
        napi_fatal_error("deferred_tsfn", NAPI_AUTO_LENGTH,
                         "Internal threadsafe func error", NAPI_AUTO_LENGTH);
        // ^^^ exits
    }
    if (napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_release) != napi_ok) {
        reject_deferred(env, ctx->deferred, "NAPI threadsafe func release failed");
    } else if (ret_json == NULL) {
        reject_deferred(env, ctx->deferred, "Swift call empty response error");
    } else {
        napi_value ret;
        if (napi_create_string_utf8(env, ret_json, NAPI_AUTO_LENGTH, &ret) != napi_ok) {
            reject_deferred(env, ctx->deferred, "Swift return string value error");
        } else {
            napi_resolve_deferred(env, ctx->deferred, ret);
        }
    }
    if (ret_json != NULL) {
        free(ret_json);
    }
    if (ctx != NULL) {
        free(ctx);
    }
}


// Runs from any thread..
static void deferred_cb(deferred_tsfn_ctx_t *ctx, char* ret_buf, int ret_size) {
    if (!g_loaded) {
        printf("Ignoring deferred callback: mwc module is unloaded\n");
        return;
    }
    // ret_buf is allocated by swift (stack); make a null terminated copy to be used in MainThread
    char *ret_json = ret_size > 0 ? strndup(ret_buf, ret_size) : NULL;
    if (napi_call_threadsafe_function(ctx->tsfn, ret_json, /*enqueue*/ napi_tsfn_blocking) != napi_ok) {
        if (ret_json != NULL) {
            free(ret_json);
        }
        napi_fatal_error("deferred_cb", NAPI_AUTO_LENGTH,
                         "Internal deferred callback error", NAPI_AUTO_LENGTH);
    }
}


static napi_value swiftCallNoArgs(napi_env env, swift_call_noargs_t swift_call) {
    char ret_buf[0xffff] = {0};
    int size;
    if ((size = swift_call(ret_buf, (int) sizeof(ret_buf))) <= 0) {
        napi_throw_error(env, NULL, "swift call failed");
        return NULL;
    }
    napi_value json;
    NAPI_CALL(env, napi_create_string_utf8(env, ret_buf, size, &json));
    return json;
}


static napi_value swiftCall(napi_env env, napi_callback_info info, swift_call_t swift_call) {
    size_t argc = 1;
    napi_value args[1];
    NAPI_CALL(env, napi_get_cb_info(env, info, &argc, args, NULL, NULL));
    if (argc != 1) {
        napi_throw_type_error(env, NULL, "1 argument required");
        return NULL;
    }
    size_t args_len_nonull;
    char args_stack[0xffff] = {0};
    size_t args_buf_len = sizeof(args_stack);
    char *args_buf = args_stack;
    // Get size only first...
    NAPI_CALL(env, napi_get_value_string_utf8(env, args[0], NULL, 0, &args_len_nonull));
    if (args_len_nonull >= sizeof(args_stack)) {
        args_buf_len = args_len_nonull + 1;
        args_buf = malloc(args_buf_len);
        if (args_buf == NULL) {
            napi_throw_error(env, NULL, "malloc failed");
            return NULL;
        }
        memset(args_buf, 0, args_buf_len);
    }
    // Though shalt not return from here on... (use cleanup)
    napi_value ret = NULL;
    if (napi_get_value_string_utf8(env, args[0], args_buf, args_buf_len, NULL) != napi_ok) {
        ensure_throw(env);
        goto cleanup;
    }
    char ret_buf[524288] = {0};
    int size;
    if ((size = swift_call(args_buf, (int) args_len_nonull, ret_buf, (int) sizeof(ret_buf))) <= 0) {
        napi_throw_error(env, NULL, "swift call failed");
        goto cleanup;
    }
    if (size > (int) sizeof(ret_buf)) {
        napi_throw_error(env, NULL, "swift call failed");
        napi_throw_error(env, NULL, "swift call response buffer overflow");
        goto cleanup;
    }
    napi_value ret_json;
    if (napi_create_string_utf8(env, ret_buf, size, &ret_json) != napi_ok) {
        ensure_throw(env);
        goto cleanup;
    }
    ret = ret_json;

cleanup:
    if (args_buf != args_stack) {
        free(args_buf);
    }
    return ret;
}


static napi_value swiftCallDeferred(napi_env env, napi_callback_info info, swift_async_call_t swift_call) {
    size_t argc = 1;
    napi_value args[1];
    char *args_buf = NULL;
    deferred_tsfn_ctx_t *ctx = NULL;
    NAPI_CALL(env, napi_get_cb_info(env, info, &argc, args, NULL, NULL));
    if (argc != 1) {
        napi_throw_type_error(env, NULL, "1 argument required");
        return NULL;
    }
    // No NAPI_CALL from here down and use error label branch...

    size_t args_len_nonull;
    // Get size only first...
    if (napi_get_value_string_utf8(env, args[0], NULL, 0, &args_len_nonull) != napi_ok) {
        goto error;
    }
    size_t args_buf_len = args_len_nonull + 1;
    args_buf = malloc(args_buf_len);
    if (args_buf == NULL) {
        napi_throw_error(env, NULL, "malloc failed");
        goto error;
    }
    memset(args_buf, 0, args_buf_len);
    if (napi_get_value_string_utf8(env, args[0], args_buf, args_buf_len, NULL) != napi_ok) {
        goto error;
    }

    ctx = malloc(sizeof(deferred_tsfn_ctx_t));
    if (ctx == NULL) {
        napi_throw_error(env, NULL, "malloc failed");
        goto error;
    }
    memset(ctx, 0, sizeof(deferred_tsfn_ctx_t));
    napi_value promise;
    napi_value tsfn_label;
    if (napi_create_promise(env, &(ctx->deferred), &promise) != napi_ok ||
        napi_create_string_utf8(env, "DeferredSwiftCallback", NAPI_AUTO_LENGTH, &tsfn_label) != napi_ok ||
        napi_create_threadsafe_function(env, NULL, NULL, tsfn_label, /*max q size*/ 0,
                                        /*thread use cnt*/ 1, NULL, NULL, ctx,
                                        (napi_threadsafe_function_call_js) deferred_tsfn,
                                        &(ctx->tsfn)) != napi_ok) {
        goto error;
    }
    swift_call(args_buf, (int) args_len_nonull, ctx, deferred_cb);
    free(args_buf);
    return promise;

error:
    if (ctx != NULL) {
        if (ctx->deferred != NULL) {
            napi_resolve_deferred(env, ctx->deferred, get_undefined(env));
        }
        if (ctx->tsfn != NULL) {
            napi_release_threadsafe_function(ctx->tsfn, napi_tsfn_abort);
        }
        free(ctx);
    }
    if (args_buf != NULL) {
        free(args_buf);
    }
    ensure_throw(env);
    return NULL;
}


static napi_value hasAccessibilityPermission(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_hasAccessibilityPermission);
}


static napi_value getMainScreen(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getMainScreen);
}


static napi_value getActiveScreen(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getActiveScreen);
}


static napi_value getScreens(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getScreens);
}


static napi_value getApps(napi_env env, napi_callback_info info) {
    return swiftCallDeferred(env, info, mwc_getApps);
}


static napi_value getWindows(napi_env env, napi_callback_info info) {
    return swiftCallDeferred(env, info, mwc_getWindows);
}


static napi_value getWindowSize(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_getWindowSize);
}


static napi_value setWindowSize(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_setWindowSize);
}


static napi_value activateWindow(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_activateWindow);
}


static napi_value getZoom(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_getZoom);
}


static napi_value setZoom(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_setZoom);
}


static void on_cleanup(void *) {
    g_loaded = 0;
}


static napi_value Init(napi_env env, napi_value exports) {
#   define ADD_FUNC(fn) \
        do { \
            napi_value jsFunc; \
            NAPI_CALL(env, napi_create_function(env, (#fn), NAPI_AUTO_LENGTH, (fn), NULL, &jsFunc)); \
            NAPI_CALL(env, napi_set_named_property(env, exports, (#fn), jsFunc)); \
        } while (0)
    ADD_FUNC(hasAccessibilityPermission);
    ADD_FUNC(getMainScreen);
    ADD_FUNC(getActiveScreen);
    ADD_FUNC(getScreens);
    ADD_FUNC(getApps);
    ADD_FUNC(getWindows);
    ADD_FUNC(getWindowSize);
    ADD_FUNC(setWindowSize);
    ADD_FUNC(activateWindow);
    ADD_FUNC(getZoom);
    ADD_FUNC(setZoom);
    NAPI_CALL(env, napi_add_env_cleanup_hook(env, on_cleanup, NULL));
    g_loaded = 1;
    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
