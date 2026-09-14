#ifndef IS12_PROTOCOL_H
#define IS12_PROTOCOL_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Outer length is inclusive u16 BE; inner length is u16 LE plus five header bytes. */
#define IS12_OUTER_LIMIT 65535
#define IS12_BUFFER_LIMIT 65540
typedef enum { IS12_INVALID = -1, IS12_MORE = 0, IS12_COMPLETE = 1 } is12_parse_result;
typedef struct {
    uint8_t kind, family, token;
    const uint8_t *payload;
    size_t length, consumed;
} is12_reply;

/* Five statically traced information requests, no scan/feed API. */
bool is12_information_request(uint8_t selector, uint8_t out[7]);
is12_parse_result is12_outer_frame(const uint8_t *data, size_t length, size_t *total);
is12_parse_result is12_parse_reply(const uint8_t *data, size_t length, is12_reply *reply);
bool is12_bjc85_head_matches(const uint8_t *carrier, size_t carrier_length,
                            const uint8_t *information, size_t information_length);

typedef bool (*is12_reply_callback)(const is12_reply *reply, void *context);
typedef struct {
    uint8_t outer[IS12_OUTER_LIMIT], inner[IS12_BUFFER_LIMIT];
    size_t outer_length, inner_length;
    bool failed;
} is12_stream;

/* Callback payload is borrowed only for the duration of the callback. */
void is12_stream_init(is12_stream *stream);
bool is12_stream_feed(is12_stream *stream, const uint8_t *data, size_t length,
                     is12_reply_callback callback, void *context);
bool is12_stream_complete(const is12_stream *stream);
#endif
