#include "is12_protocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

typedef struct {
    uint8_t kind, family, token;
    size_t length;
    uint8_t payload[32];
} saved_reply;
typedef struct { saved_reply records[16]; size_t count; bool reject; } collected;

static bool collect(const is12_reply *reply, void *context) {
    collected *saved = context;
    if (saved->reject) return false;
    CHECK(saved->count < 16);
    saved_reply *record = &saved->records[saved->count++];
    record->kind=reply->kind; record->family=reply->family; record->token=reply->token;
    record->length=reply->length;
    size_t copy = reply->length < sizeof(record->payload) ? reply->length : sizeof(record->payload);
    memcpy(record->payload, reply->payload, copy);
    if (reply->family == 'S' && reply->token == 'c') {
        CHECK(reply->length == 12337);
        for (size_t i=0; i<reply->length; i++) CHECK(reply->payload[i] == (uint8_t)(i*17+3));
    }
    return true;
}

static collected fragmented(const uint8_t *wire, size_t length, size_t chunk) {
    is12_stream stream;
    is12_stream_init(&stream);
    collected saved = {0};
    for (size_t offset=0; offset<length;) {
        size_t count = length-offset < chunk ? length-offset : chunk;
        CHECK(is12_stream_feed(&stream, wire+offset, count, collect, &saved));
        offset += count;
    }
    CHECK(is12_stream_complete(&stream));
    return saved;
}

static void check_chunks(const uint8_t *wire, size_t length, const collected *expected) {
    const size_t chunks[] = {1,2,3,5,7,63,64,65,511,512,4096,65535};
    for (size_t i=0; i<sizeof(chunks)/sizeof(chunks[0]); i++) {
        collected actual = fragmented(wire, length, chunks[i]);
        CHECK(actual.count == expected->count);
        for (size_t j=0; j<actual.count; j++) {
            const saved_reply *a=&actual.records[j], *e=&expected->records[j];
            CHECK(a->kind==e->kind && a->family==e->family && a->token==e->token && a->length==e->length);
            CHECK(!memcmp(a->payload, e->payload, sizeof(a->payload)));
        }
    }
}

static void fixture(const char *filename, const char *tokens, const size_t *lengths) {
    FILE *file = fopen(filename, "rb"); CHECK(file);
    uint8_t wire[4096];
    size_t length = fread(wire, 1, sizeof(wire), file);
    CHECK(!ferror(file) && feof(file) && length);
    fclose(file);
    collected expected = fragmented(wire, length, length);
    CHECK(expected.count == strlen(tokens));
    for (size_t i=0; i<expected.count; i++) {
        CHECK(expected.records[i].family == 's');
        CHECK(expected.records[i].token == (uint8_t)tokens[i]);
        CHECK(expected.records[i].length == lengths[i]);
        if (tokens[i] == 'c') CHECK(expected.records[i].payload[0] == 0xb0 && expected.records[i].payload[11] == 0x0e);
        if (tokens[i] == 'i') CHECK(expected.records[i].payload[0] == 0x70);
    }
    check_chunks(wire, length, &expected);
    /* Truncating the final outer frame remains incomplete. */
    is12_stream stream;
    is12_stream_init(&stream);
    collected saved = {0};
    CHECK(is12_stream_feed(&stream, wire, length-1, collect, &saved));
    CHECK(!is12_stream_complete(&stream));
}

int main(int argc, char **argv) {
    CHECK(argc == 4);
    const size_t first[] = {3,3,12,9,3}, warm[] = {3,12,9,3}, extended[] = {12,9,3,1,18};
    fixture(argv[1], "sscis", first);
    fixture(argv[2], "scis", warm);
    fixture(argv[3], "ciste", extended);

    /* Canon table row 27: uppercase S/c, 12,337-byte calibration payload.
       Synthetic content only; no calibration data has been acquired. */
    uint8_t inner[12343] = {0x1b,'!','S',0x32,0x30,'c'};
    for (size_t i=6; i<sizeof(inner); i++) inner[i] = (uint8_t)((i-6)*17+3);
    uint8_t wire[12349];
    const size_t cuts[] = {3,70,sizeof(inner)-73};
    size_t source=0, target=0;
    for (size_t i=0; i<3; i++) {
        size_t frame_length = cuts[i]+2;
        wire[target++] = (uint8_t)(frame_length>>8);
        wire[target++] = (uint8_t)frame_length;
        memcpy(wire+target, inner+source, cuts[i]);
        target += cuts[i]; source += cuts[i];
    }
    CHECK(target == sizeof(wire));
    collected calibration = fragmented(wire, sizeof(wire), sizeof(wire));
    CHECK(calibration.count == 1 && calibration.records[0].family == 'S');
    check_chunks(wire, sizeof(wire), &calibration);

    is12_stream stream;
    collected saved = {0};
    is12_stream_init(&stream);
    const uint8_t invalid[] = {0,1};
    CHECK(!is12_stream_feed(&stream, invalid, sizeof(invalid), collect, &saved));
    CHECK(!is12_stream_complete(&stream));
    CHECK(!is12_stream_feed(&stream, wire, sizeof(wire), collect, &saved));
    CHECK(saved.count == 0);
    is12_stream_init(&stream); saved.reject = true;
    CHECK(!is12_stream_feed(&stream, wire, sizeof(wire), collect, &saved));
    CHECK(!is12_stream_complete(&stream));
    puts("Captured replies and calibration-sized records survive USB/outer-frame fragmentation; malformed, partial and rejected streams stop.");
    return 0;
}
