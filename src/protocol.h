#ifndef BJC85_PROTOCOL_H
#define BJC85_PROTOCOL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* USB Printer Class 1.1 sections 4.2.1 and 4.2.2. */
bool bjc_device_id(const uint8_t *data, size_t received, char *out, size_t capacity);
bool bjc_port_ready(uint8_t status);
#endif
