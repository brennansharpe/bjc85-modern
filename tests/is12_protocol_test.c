#include "is12_protocol.h"
#include <stdio.h>
#include <string.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #c); return 1; } } while (0)

int main(void) {
    uint8_t request[7];
    const uint8_t expected[] = {0x1b, '(', 's', 2, 0, 'R', 2};
    CHECK(is12_information_request(2, request));
    CHECK(!memcmp(request, expected, sizeof(expected)));
    CHECK(is12_information_request(3, request) && request[6] == 3);
    CHECK(is12_information_request(4, request) && request[6] == 4);
    CHECK(!is12_information_request(5, request));
    /* Outer big-endian inclusive length; inner little-endian body length. */
    const uint8_t wire[] = {0,11,0x1b,'!','s',4,0,'s',0x60,0,0};
    size_t total = 0;
    for (size_t i=0; i<sizeof(wire); i++) CHECK(is12_outer_frame(wire, i, &total) == IS12_MORE);
    CHECK(is12_outer_frame(wire, sizeof(wire), &total) == IS12_COMPLETE && total == sizeof(wire));
    is12_reply reply;
    for (size_t i=0; i<sizeof(wire)-2; i++) CHECK(is12_parse_reply(wire+2, i, &reply) == IS12_MORE);
    CHECK(is12_parse_reply(wire+2, sizeof(wire)-2, &reply) == IS12_COMPLETE);
    CHECK(reply.token == 's' && reply.length == 3 && reply.payload[0] == 0x60 && reply.consumed == 9);
    const uint8_t short_frame[] = {0,1}, large_frame[] = {0xff,0xff};
    CHECK(is12_outer_frame(short_frame, 2, &total) == IS12_INVALID);
    CHECK(is12_outer_frame(large_frame, 2, &total) == IS12_MORE && total == 65535);
    uint8_t bad[9]; memcpy(bad, wire+2, sizeof(bad));
    bad[0] = 0;
    CHECK(is12_parse_reply(bad, sizeof(bad), &reply) == IS12_INVALID);
    bad[0] = 0x1b; bad[3] = bad[4] = 0;
    CHECK(is12_parse_reply(bad, sizeof(bad), &reply) == IS12_INVALID);
    const uint8_t error[] = {0x1b,'!','e',2,0,0x01,0x02};
    CHECK(is12_parse_reply(error, sizeof(error), &reply) == IS12_COMPLETE && reply.family == 'e' && reply.length == 2);
    uint8_t carrier[12] = {0xa0}, information[9] = {0x60};
    carrier[11] = 0x0e;
    CHECK(is12_bjc85_head_matches(carrier, 12, information, 9));
    CHECK(!is12_bjc85_head_matches(carrier, 11, information, 9));
    carrier[11] = 0x4e;
    CHECK(!is12_bjc85_head_matches(carrier, 12, information, 9));
    /* Actual 2026-09-13 USB replies, preserved in is12-first-status.jsonl. */
    const uint8_t captured_carrier[] = {0,20,0x1b,'!','s',13,0,'c',0xb0,1,0x0e,0x80,1,0,0,0x0b,0x40,0,0x10,0x0e};
    const uint8_t captured_info[] = {0,17,0x1b,'!','s',10,0,'i',0x70,0x19,0x11,1,0x1f,1,0x68,0x0b,0x88};
    const uint8_t captured_warmup[] = {0,11,0x1b,'*','s',4,0,'s',0,8,0};
    const uint8_t *captures[] = {captured_carrier, captured_info, captured_warmup};
    const size_t lengths[] = {sizeof(captured_carrier), sizeof(captured_info), sizeof(captured_warmup)};
    const uint8_t tokens[] = {'c', 'i', 's'};
    for (size_t j=0; j<3; j++) {
        for (size_t n=0; n<lengths[j]; n++) CHECK(is12_outer_frame(captures[j], n, &total) == IS12_MORE);
        CHECK(is12_outer_frame(captures[j], lengths[j], &total) == IS12_COMPLETE && total == lengths[j]);
        for (size_t n=0; n<lengths[j]-2; n++) CHECK(is12_parse_reply(captures[j]+2, n, &reply) == IS12_MORE);
        CHECK(is12_parse_reply(captures[j]+2, lengths[j]-2, &reply) == IS12_COMPLETE);
        CHECK(reply.token == tokens[j] && reply.length == lengths[j]-8);
        if (j == 0) memcpy(carrier, reply.payload, sizeof(carrier));
        if (j == 1) memcpy(information, reply.payload, sizeof(information));
        if (j == 2) CHECK(reply.kind == '*' && reply.payload[1] == 8);
    }
    CHECK(is12_bjc85_head_matches(carrier, sizeof(carrier), information, sizeof(information)));
    puts("IS-12 information requests, framing and cartridge checks passed (synthetic and captured fixtures).");
    return 0;
}
