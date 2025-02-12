#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <node_api.h>

// For simplicity we use the same interface for everything.  All funcs
// use a JSON based char* input argument and/or a char* output buffer along
// with int size for the output buffer for response values.  The swift
// func returns a positive value to indicate how many bytes will copied
// into the output buffer or < 0 on error.
int mwc_getMainScreenSize(char*, int);
int mwc_getMenuBarHeight(char*, int);
int mwc_resizeAppWindow(char*, int);


// Basically everything in node_api uses this error handling conv...
#define NAPI_CALL(env, the_call)                                   \
    do {                                                           \
        if ((the_call) != napi_ok) {                               \
            const napi_extended_error_info *error_info;            \
            napi_get_last_error_info((env), &error_info);          \
            bool is_pending;                                       \
            const char* err_message = error_info->error_message;   \
            napi_is_exception_pending((env), &is_pending);         \
            if (!is_pending) {                                     \
                const char* error_message = err_message != NULL ?  \
                err_message :                                      \
                "empty error message";                             \
                napi_throw_error((env), NULL, error_message);      \
            }                                                      \
            return NULL;                                           \
        }                                                          \
    } while (0)


static napi_value swiftCallWithReturn(napi_env env, int (*fptr)(char*, int)) {
    char outBuf[0xffff] = {0};
    int size;
    if ((size = fptr(outBuf, (int) sizeof(outBuf))) <= 0) {
        napi_throw_error(env, NULL, "swift call failed");
        return NULL;
    }
    napi_value json;
    NAPI_CALL(env, napi_create_string_utf8(env, outBuf, size, &json));
    return json;
}


static napi_value swiftCallWithArgs(napi_env env, napi_callback_info info, int (*fptr)(char*, int)) {
    size_t argc = 1;
    napi_value args[1];
    NAPI_CALL(env, napi_get_cb_info(env, info, &argc, args, NULL, NULL));
    if (argc != 1) {
        napi_throw_error(env, NULL, "1 argument required");
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
    if (napi_get_value_string_utf8(env, args[0], json_ptr, buf_len, NULL) != napi_ok) {
        goto cleanup;
    }
    if (fptr(json_ptr, (int) json_len_nonull) != 0) {
        napi_throw_error(env, NULL, "swift call failed");
        goto cleanup;
    }

cleanup:
    if (json_ptr != json_stack) {
        free(json_ptr);
    }
    return NULL;
}


static napi_value getMainScreenSize(napi_env env, napi_callback_info info) {
    return swiftCallWithReturn(env, mwc_getMainScreenSize);
}


static napi_value getMenuBarHeight(napi_env env, napi_callback_info info) {
    return swiftCallWithReturn(env, mwc_getMenuBarHeight);
}


static napi_value resizeAppWindow(napi_env env, napi_callback_info info) {
    return swiftCallWithArgs(env, info, mwc_resizeAppWindow);
}


static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor props[] = {{
        .utf8name = "getMainScreenSize",
        .method = getMainScreenSize,
        .attributes = napi_default
    }, {
        .utf8name = "getMenuBarHeight",
        .method = getMenuBarHeight,
        .attributes = napi_default
    }, {
        .utf8name = "resizeAppWindow",
        .method = resizeAppWindow,
        .attributes = napi_default
    }};
    NAPI_CALL(env, napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props));
    return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
