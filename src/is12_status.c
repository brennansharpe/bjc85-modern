#include "is12_status.h"
#include "is12_protocol.h"
bool is12_status_has_error(const uint8_t s[3]) {
    return (s[0]&0x44) || (s[1]&0xd4) || (s[2]&3);
}
is12_status_result is12_status_evaluate(bool transport,bool replies,const uint8_t *carrier,
    size_t cn,const uint8_t *information,size_t in,const uint8_t status[3]) {
    is12_status_result result={.transport_ok=transport,.replies_ok=replies};
    if (!transport) result.kind=IS12_STATUS_TRANSPORT_ERROR;
    else if (!replies || !status || cn!=12 || in!=9) result.kind=IS12_STATUS_REPLY_ERROR;
    else {
        result.head_matches=is12_bjc85_head_matches(carrier,cn,information,in);
        if (!result.head_matches) result.kind=IS12_STATUS_WRONG_HEAD;
        else if (is12_status_has_error(status)) result.kind=IS12_STATUS_DEVICE_ERROR;
        else if (status[1]&8) result.kind=IS12_STATUS_WARMING;
        else { result.kind=IS12_STATUS_READY; result.ready=true; }
    }
    return result;
}
const char *is12_status_name(is12_status_kind kind) {
    switch(kind) {
    case IS12_STATUS_READY: return "ready";
    case IS12_STATUS_TRANSPORT_ERROR: return "transportError";
    case IS12_STATUS_REPLY_ERROR: return "replyError";
    case IS12_STATUS_WRONG_HEAD: return "wrongHead";
    case IS12_STATUS_WARMING: return "warming";
    case IS12_STATUS_DEVICE_ERROR: return "deviceError";
    }
    return "replyError";
}
