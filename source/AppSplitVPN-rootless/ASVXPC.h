#pragma once
// The iPhone public SDK omits XPC headers. Declare only the runtime ABI used
// by the owned-session compatibility hook, not a replacement XPC implementation.
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdbool.h>

#if __has_include(<xpc/xpc.h>)
#import <xpc/xpc.h>
#else
@class OS_xpc_object;
typedef OS_xpc_object *xpc_object_t;
typedef xpc_object_t xpc_connection_t;
typedef const struct xpc_type_s *xpc_type_t;
extern const struct xpc_type_s _xpc_type_dictionary;
extern const struct xpc_type_s _xpc_type_array;
#define XPC_TYPE_DICTIONARY (&_xpc_type_dictionary)
#define XPC_TYPE_ARRAY (&_xpc_type_array)
extern xpc_type_t xpc_get_type(xpc_object_t object);
extern const char *xpc_dictionary_get_string(xpc_object_t object, const char *key);
extern xpc_object_t xpc_dictionary_get_value(xpc_object_t object, const char *key);
extern uint64_t xpc_dictionary_get_uint64(xpc_object_t object, const char *key);
extern const void *xpc_dictionary_get_data(xpc_object_t object, const char *key, size_t *length);
extern void xpc_dictionary_set_data(xpc_object_t object, const char *key, const void *bytes, size_t length);
extern bool xpc_array_apply(xpc_object_t object, bool (^applier)(size_t index, xpc_object_t value));
#endif
