#ifndef IS12_STATUS_H
#define IS12_STATUS_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef enum {
    IS12_STATUS_READY, IS12_STATUS_TRANSPORT_ERROR, IS12_STATUS_REPLY_ERROR,
    IS12_STATUS_WRONG_HEAD, IS12_STATUS_WARMING, IS12_STATUS_DEVICE_ERROR
} is12_status_kind;
typedef struct {
    is12_status_kind kind;
    bool transport_ok, replies_ok, head_matches, ready;
} is12_status_result;
is12_status_result is12_status_evaluate(bool transport_ok, bool replies_ok,
    const uint8_t *carrier, size_t carrier_size, const uint8_t *information,
    size_t information_size, const uint8_t status[3]);
const char *is12_status_name(is12_status_kind kind);
bool is12_status_has_error(const uint8_t status[3]);
#endif
