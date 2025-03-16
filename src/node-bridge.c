#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <node_api.h>
#include "../obj/c-lib.swift.h"


typedef int (*swift_call_t)(const char *, int, char *, int);
typedef int (*swift_call_noargs_t)(char *, int);
typedef void (*swift_async_call_t)(const char *, int, const void *, const void *);


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


// Runs in main thread..
static void deferred_tsfn(napi_env env, napi_value _jscb, napi_deferred deferred, char *ret_json) {
    napi_value ret = NULL;
    if (ret_json == NULL) {
        fprintf(stderr, "Ooops: Swift error\n"); // XXX remove after test..
        napi_reject_deferred(env, deferred, NULL);
    } else {
        napi_status r = napi_create_string_utf8(env, ret_json, NAPI_AUTO_LENGTH, &ret);
        free(ret_json);
        if (r == napi_ok) {
            napi_resolve_deferred(env, deferred, ret);
        } else {
            printf("Ooops: internal swift ret value error\n"); // remove after verify.
            napi_reject_deferred(env, deferred, NULL);
        }
    }
}


// Runs from outside main thread..
static void deferred_cb(napi_threadsafe_function tsfn, char* ret_buf, int ret_size) {
    // ret_buf is allocated by swift, make a null terminated copy to be used later..
    char *ret_json = ret_size > 0 ? strndup(ret_buf, ret_size) : NULL;
    napi_status r = napi_call_threadsafe_function(tsfn, ret_json, napi_tsfn_nonblocking);
    napi_release_threadsafe_function(tsfn, napi_tsfn_release); // XXX comment out and see if we leak, it's just a bit ambiguous in the docs
    if (r != napi_ok) {
        fprintf(stderr, "Failed to call thread safe function\n");
        return;
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
    napi_value tsfn_label;
    NAPI_CALL(env, napi_create_string_utf8(env, "DeferredSwiftCallback", NAPI_AUTO_LENGTH, &tsfn_label));
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
    memset(args_buf, 0, args_buf_len);
    if (napi_get_value_string_utf8(env, args[0], args_buf, args_buf_len, NULL) != napi_ok) {
        free(args_buf);
        ensure_throw(env);
        return NULL;
    }
    napi_threadsafe_function tsfn;
    napi_status r = napi_create_threadsafe_function(env, NULL, NULL, tsfn_label, /*max q size*/ 0,
                                                    /*thread use cnt*/ 1, NULL, NULL, deferred,
                                                    (napi_threadsafe_function_call_js) deferred_tsfn,
                                                    &tsfn);
    if (r != napi_ok) {
        // XXX test
        free(args_buf);
        ensure_throw(env);
        return NULL;
    }
    swift_call(args_buf, (int) args_len_nonull, tsfn, deferred_cb);
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
