#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <node_api.h>
#include "../obj/mwc.h"


typedef struct deferred_cb_ctx {
    napi_env env;
    napi_deferred deferred;
} deferred_cb_ctx_t;
typedef void (*deferred_cb_t)(deferred_cb_ctx_t*, char*, int);
typedef int (*swift_call_t)(const char*, int, char*, int);
typedef int (*swift_call_noargs_t)(char*, int);
typedef void (*swift_async_call_t)(const char*, int, const void*, const void*);


// Basically everything in node_api uses this error handling conv...
#define NAPI_CALL(env, the_call)                                   \
    do {                                                           \
        if ((the_call) != napi_ok) {                               \
            ensure_throw((env));                                   \
            return NULL;                                           \
        }                                                          \
    } while (0)


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


static void deferred_cb(struct deferred_cb_ctx *ctx, char* ret_buf, int ret_size) {
    printf("FUCK ME< it workd? %p %p %d\n", ctx, ret_buf, ret_size);
    // TBD: I'm not sure how errors thrown from here are handled (if at all). XXX
    napi_deferred deferred = ctx->deferred;
    napi_env env = ctx->env;
    free(ctx);
    napi_value ret = NULL;
    if (ret_size < 0) {
        printf("Ooops: Swift error\n");
        napi_reject_deferred(env, deferred, NULL);
        return;
    } else if (ret_size > 0) {
        if (napi_create_string_utf8(env, ret_buf, ret_size, &ret) != napi_ok) {
            printf("Ooops: internal swift ret value error\n");
            napi_reject_deferred(env, deferred, NULL);
            return;
        }
    }
    napi_resolve_deferred(env, deferred, ret);
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
    size_t json_len_nonull;
    char json_stack[0xffff] = {0};
    size_t buf_len = sizeof(json_stack);
    char *json_ptr = json_stack;
    // Get size only first...
    NAPI_CALL(env, napi_get_value_string_utf8(env, args[0], NULL, 0, &json_len_nonull));
    if (json_len_nonull >= sizeof(json_stack)) {
        buf_len = json_len_nonull + 1;
        json_ptr = malloc(buf_len);
        if (json_ptr == NULL) {
            napi_throw_error(env, NULL, "malloc failed");
            return NULL;
        }
        memset(json_ptr, 0, buf_len);
    }
    // Though shalt not return from here on... (use cleanup)
    napi_value ret = NULL;
    if (napi_get_value_string_utf8(env, args[0], json_ptr, buf_len, NULL) != napi_ok) {
        ensure_throw(env);
        goto cleanup;
    }
    char ret_buf[524288] = {0};
    int size;
    if ((size = swift_call(json_ptr, (int) json_len_nonull, ret_buf, (int) sizeof(ret_buf))) <= 0) {
        napi_throw_error(env, NULL, "swift call failed");
        goto cleanup;
    }
    if (size > (int) sizeof(ret_buf)) {
        napi_throw_error(env, NULL, "swift call response buffer overflow");
        goto cleanup;
    }
    napi_value json;
    if (napi_create_string_utf8(env, ret_buf, size, &json) != napi_ok) {
        ensure_throw(env);
        goto cleanup;
    }
    ret = json;

cleanup:
    if (json_ptr != json_stack) {
        free(json_ptr);
    }
    return ret;
}


static napi_value swiftCallAsync(napi_env env, napi_callback_info info, swift_async_call_t swift_call) {
    size_t argc = 1;
    napi_value args[1];
    NAPI_CALL(env, napi_get_cb_info(env, info, &argc, args, NULL, NULL));
    if (argc != 1) {
        napi_throw_type_error(env, NULL, "1 argument required");
        return NULL;
    }
    napi_deferred deferred;
    napi_value promise;
    NAPI_CALL(env, napi_create_promise(env, &deferred, &promise));
    size_t args_len_nonull;
    // Get size only first...
    NAPI_CALL(env, napi_get_value_string_utf8(env, args[0], NULL, 0, &args_len_nonull));
    size_t args_buf_len = args_len_nonull + 1;
    char *args_buf = malloc(args_buf_len);
    if (args_buf == NULL) {
        napi_throw_error(env, NULL, "malloc failed");
        return NULL;
    }
    // args_buf cleanup required from here on...
    memset(args_buf, 0, args_buf_len);
    if (napi_get_value_string_utf8(env, args[0], args_buf, args_buf_len, NULL) != napi_ok) {
        free(args_buf);
        ensure_throw(env);
        return NULL;
    }
    struct deferred_cb_ctx *cb_ctx = malloc(sizeof(struct deferred_cb_ctx));
    if (cb_ctx == NULL) {
        free(args_buf);
        napi_throw_error(env, NULL, "malloc failed");
        return NULL;
    }
    // args_buf, cb_ctx cleanup required from here on...
    memset(cb_ctx, 0, sizeof(struct deferred_cb_ctx));
    cb_ctx->env = env;
    cb_ctx->deferred = deferred;

printf("okay do it!\n");
printf("okay %p %d %p %p %p\n", args_buf, args_len_nonull, cb_ctx, deferred_cb, swift_call);
    swift_call(args_buf, (int) args_len_nonull, cb_ctx, deferred_cb);
printf("back!!!! goind to sleeep %d!\n", getpid());
    sleep(10);
printf("back from sleeep!\n");

    free(args_buf);
    return promise;
}


static napi_value hasAccessibilityPermission(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_hasAccessibilityPermission);
}


static napi_value getMainScreenSize(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getMainScreenSize);
}


static napi_value getMenuBarHeight(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getMenuBarHeight);
}


static napi_value getApps(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_getApps);
}


static napi_value getWindows(napi_env env, napi_callback_info info) {
    return swiftCallAsync(env, info, mwc_getWindows);
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
    return swiftCallNoArgs(env, mwc_getZoom);
}


static napi_value setZoom(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_setZoom);
}



static napi_value Init(napi_env env, napi_value exports) {
#   define ADD_FUNC(fn) \
        do { \
            napi_value jsFunc; \
            napi_create_function(env, (#fn), NAPI_AUTO_LENGTH, (fn), NULL, &jsFunc); \
            napi_set_named_property(env, exports, (#fn), jsFunc); \
        } while (0)
    ADD_FUNC(hasAccessibilityPermission);
    ADD_FUNC(getMainScreenSize);
    ADD_FUNC(getMenuBarHeight);
    ADD_FUNC(getApps);
    ADD_FUNC(getWindows);
    ADD_FUNC(getWindowSize);
    ADD_FUNC(setWindowSize);
    ADD_FUNC(activateWindow);
    ADD_FUNC(getZoom);
    ADD_FUNC(setZoom);
    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
