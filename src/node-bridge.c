#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <node_api.h>

// For simplicity we use the same interface for everything.  All funcs
// take four arguments: (jsonArgs, jsonArgsSiz, &retJson, &retJsonSize)
// The swift func will return a positive value to indicate how many bytes
// were copied into the return buffer or < 0 on error.  If the retJson
// buffer is insufficiently sized it will be clipped and this should
// be considered an internal error.
int mwc_hasAccessibilityPermission(char*, int);
int mwc_getMainScreenSize(char*, int);
int mwc_getMenuBarHeight(char*, int);
int mwc_getWindowApps(char*, int);
int mwc_getAppWindowSize(char*, int, char*, int);
int mwc_resizeAppWindow(char*, int, char*, int);
int mwc_getZoom(char*, int);
int mwc_setZoom(char*, int, char*, int);


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


static napi_value swiftCallNoArgs(napi_env env, int (*fptr)(char*, int)) {
    char ret_buf[0xffff] = {0};
    int size;
    if ((size = fptr(ret_buf, (int) sizeof(ret_buf))) <= 0) {
        napi_throw_error(env, NULL, "swift call failed");
        return NULL;
    }
    napi_value json;
    NAPI_CALL(env, napi_create_string_utf8(env, ret_buf, size, &json));
    return json;
}


static napi_value swiftCall(napi_env env, napi_callback_info info, int (*fptr)(char*, int, char*, int)) {
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
    char ret_buf[0xffff] = {0};
    int size;
    if ((size = fptr(json_ptr, (int) json_len_nonull, ret_buf, (int) sizeof(ret_buf))) <= 0) {
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


static napi_value hasAccessibilityPermission(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_hasAccessibilityPermission);
}


static napi_value getMainScreenSize(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getMainScreenSize);
}


static napi_value getMenuBarHeight(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getMenuBarHeight);
}


static napi_value getWindowApps(napi_env env, napi_callback_info info) {
    return swiftCallNoArgs(env, mwc_getWindowApps);
}


static napi_value getAppWindowSize(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_getAppWindowSize);
}


static napi_value resizeAppWindow(napi_env env, napi_callback_info info) {
    return swiftCall(env, info, mwc_resizeAppWindow);
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
    ADD_FUNC(getWindowApps);
    ADD_FUNC(getAppWindowSize);
    ADD_FUNC(resizeAppWindow);
    ADD_FUNC(getZoom);
    ADD_FUNC(setZoom);
    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
