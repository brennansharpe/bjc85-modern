#include "transfer.h"
#include <libusb.h>

int bjc_transfer_all(const unsigned char *data, size_t length, size_t *sent,
                     void *context, bjc_transfer_fn transfer, bjc_clock_fn now) {
    *sent = 0;
    uint64_t last_progress = now(context);
    /* USB NAKs while the mechanical printer is busy are normal. Count the
       accepted prefix even on timeout, then continue ONLY at the next byte. */
    while (*sent < length) {
        size_t remaining = length - *sent;
        int chunk = remaining > 4096 ? 4096 : (int)remaining;
        int transferred = 0;
        int rc = transfer(context, data + *sent, chunk, &transferred);
        if (transferred < 0 || transferred > chunk) return LIBUSB_ERROR_IO;
        *sent += (size_t)transferred;
        uint64_t current = now(context);
        if (transferred) last_progress = current;
        if (rc < 0 && rc != LIBUSB_ERROR_TIMEOUT) return rc;
        if (!rc && !transferred) return LIBUSB_ERROR_IO;
        if (current - last_progress >= 60000) return LIBUSB_ERROR_TIMEOUT;
    }
    return 0;
}
