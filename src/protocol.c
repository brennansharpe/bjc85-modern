#include "protocol.h"
#include <string.h>

bool bjc_device_id(const uint8_t *data, size_t received, char *out, size_t capacity) {
    if (!data || !out || !capacity) return false;
    out[0] = '\0';
    if (received < 2) return false;
    size_t declared = ((size_t)data[0] << 8) | data[1];
    /* The big-endian length includes its own two bytes. Reject incomplete IDs. */
    if (declared < 2 || declared > received || declared - 2 >= capacity) return false;
    if (memchr(data + 2, 0, declared - 2)) return false;
    memcpy(out, data + 2, declared - 2);
    out[declared - 2] = '\0';
    return true;
}

bool bjc_port_ready(uint8_t status) {
    /* Bit 3: not error; bit 4: selected; bit 5: paper empty. */
    return (status & 0x38) == 0x18;
}
