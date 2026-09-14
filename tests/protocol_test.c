#include "protocol.h"
#include <stdio.h>
#include <string.h>
#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #condition); return 1; } } while (0)
int main(void) {
    char out[32];
    const uint8_t valid[] = {0, 10, 'M', 'F', 'G', ':', 'C', 'a', 'n', ';'};
    CHECK(bjc_device_id(valid, sizeof(valid), out, sizeof(out)));
    CHECK(!strcmp(out, "MFG:Can;"));
    CHECK(!bjc_device_id(valid, sizeof(valid)-1, out, sizeof(out)));
    CHECK(!bjc_device_id(valid, sizeof(valid), out, 8));
    CHECK(!bjc_device_id(valid, 1, out, sizeof(out)));
    const uint8_t bad_length[] = {0, 1};
    const uint8_t bad_endian[] = {10, 0, 'x'};
    const uint8_t embedded_null[] = {0, 4, 'x', 0};
    CHECK(!bjc_device_id(bad_length, 2, out, sizeof(out)));
    CHECK(!bjc_device_id(bad_endian, 3, out, sizeof(out)));
    CHECK(!bjc_device_id(embedded_null, 4, out, sizeof(out)));
    CHECK(bjc_port_ready(0x18));
    CHECK(!bjc_port_ready(0x38));
    CHECK(!bjc_port_ready(0x10));
    CHECK(!bjc_port_ready(0x08));
    CHECK(!bjc_port_ready(0));
    puts("USB identity framing and readiness tests passed.");
    return 0;
}
