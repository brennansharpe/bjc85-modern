#include "is12_protocol.h"
#include <string.h>

/* See docs/protocol/is12-wire.md for original driver addresses and byte order. */
bool is12_information_request(uint8_t selector, uint8_t out[7]) {
    if (selector > 4 || !out) return false;
    const uint8_t prefix[] = {0x1b, '(', 's', 2, 0, 'R'};
    memcpy(out, prefix, sizeof(prefix));
    out[6] = selector;
    return true;
}

is12_parse_result is12_outer_frame(const uint8_t *data, size_t length, size_t *total) {
    if (!data || !total) return IS12_INVALID;
    if (length < 2) return IS12_MORE;
    *total = (size_t)data[0] * 256 + data[1];
    if (*total < 2 || *total > IS12_OUTER_LIMIT) return IS12_INVALID;
    return length < *total ? IS12_MORE : IS12_COMPLETE;
}

is12_parse_result is12_parse_reply(const uint8_t *data, size_t length, is12_reply *reply) {
    if (!data || !reply) return IS12_INVALID;
    if (length < 5) return IS12_MORE;
    if (data[0] != 0x1b || (data[1] != '!' && data[1] != '*') ||
        (data[2] != 's' && data[2] != 'e' && data[2] != 'S') ||
        (data[1] == '*' && data[2] != 's')) return IS12_INVALID;
    size_t body = data[3] + (size_t)data[4] * 256;
    if (!body || body > IS12_BUFFER_LIMIT-5) return IS12_INVALID;
    if (length < body+5) return IS12_MORE;
    reply->kind = data[1]; reply->family = data[2]; reply->consumed = body+5;
    if (data[2] == 'e') {
        if (body != 2) return IS12_INVALID;
        reply->token = 0; reply->payload = data+5; reply->length = body;
    } else {
        reply->token = data[5]; reply->payload = data+6; reply->length = body-1;
    }
    return IS12_COMPLETE;
}

void is12_stream_init(is12_stream *stream) {
    memset(stream, 0, sizeof(*stream));
}

static bool append_inner(is12_stream *stream, const uint8_t *data, size_t length,
                         is12_reply_callback callback, void *context) {
    while (length) {
        size_t available = sizeof(stream->inner)-stream->inner_length;
        if (!available) return false;
        size_t copy = length < available ? length : available;
        memcpy(stream->inner+stream->inner_length, data, copy);
        stream->inner_length += copy; data += copy; length -= copy;
        size_t offset = 0;
        while (offset < stream->inner_length) {
            is12_reply reply;
            is12_parse_result parsed = is12_parse_reply(stream->inner+offset, stream->inner_length-offset, &reply);
            if (parsed == IS12_INVALID) return false;
            if (parsed == IS12_MORE) break;
            if (!callback(&reply, context)) return false;
            offset += reply.consumed;
        }
        if (offset) {
            memmove(stream->inner, stream->inner+offset, stream->inner_length-offset);
            stream->inner_length -= offset;
        }
    }
    return true;
}

bool is12_stream_feed(is12_stream *stream, const uint8_t *data, size_t length,
                     is12_reply_callback callback, void *context) {
    if (!stream || stream->failed || (!data && length) || !callback) return false;
    while (length) {
        size_t total = 2;
        if (stream->outer_length >= 2 &&
            is12_outer_frame(stream->outer, stream->outer_length, &total) == IS12_INVALID) goto fail;
        size_t needed = total-stream->outer_length;
        size_t copy = length < needed ? length : needed;
        memcpy(stream->outer+stream->outer_length, data, copy);
        stream->outer_length += copy; data += copy; length -= copy;
        is12_parse_result parsed = is12_outer_frame(stream->outer, stream->outer_length, &total);
        if (parsed == IS12_INVALID) goto fail;
        if (parsed == IS12_COMPLETE) {
            if (!append_inner(stream, stream->outer+2, total-2, callback, context)) goto fail;
            stream->outer_length = 0;
        }
    }
    return true;
fail:
    stream->failed = true;
    return false;
}

bool is12_stream_complete(const is12_stream *stream) {
    return stream && !stream->failed && !stream->outer_length && !stream->inner_length;
}

bool is12_bjc85_head_matches(const uint8_t *carrier, size_t carrier_length,
                            const uint8_t *information, size_t information_length) {
    return carrier && information && carrier_length == 12 && information_length == 9 &&
           (carrier[0] & 0xe0) == 0xa0 && (information[0] & 0x60) == 0x60 && carrier[11] == 0x0e;
}
