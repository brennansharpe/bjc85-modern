#include "transfer.h"
#include <libusb.h>
#include <stdio.h>
#include <string.h>

typedef struct { const unsigned char *base; size_t offset; int calls; int scenario; uint64_t time; int bad; } fixture;
static uint64_t now(void *p) { return ((fixture *)p)->time; }
static int write_fake(void *p, const unsigned char *data, int length, int *transferred) {
    fixture *f = p;
    if (data != f->base + f->offset || length > 4096) f->bad = 1;
    f->calls++; f->time += 1000;
    if (f->scenario == 1) { *transferred = 0; return LIBUSB_ERROR_TIMEOUT; }
    if (f->scenario == 2) { *transferred = 17; f->offset += 17; return LIBUSB_ERROR_NO_DEVICE; }
    if (f->scenario == 3) { *transferred = length+1; return 0; }
    if (f->scenario == 4) { *transferred = 0; return 0; }
    if (f->calls == 2) { *transferred = 0; return LIBUSB_ERROR_TIMEOUT; }
    *transferred = f->calls == 1 ? 64 : length;
    f->offset += (size_t)*transferred;
    return f->calls == 1 ? LIBUSB_ERROR_TIMEOUT : 0;
}
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"line %d: %s\n",__LINE__,#x); return 1; } } while(0)
int main(void) {
    unsigned char data[9000] = {0}; size_t sent;
    fixture f = {.base=data};
    CHECK(!bjc_transfer_all(data,sizeof(data),&sent,&f,write_fake,now));
    CHECK(sent==sizeof(data) && f.offset==sizeof(data) && !f.bad);
    f=(fixture){.base=data,.scenario=1};
    CHECK(bjc_transfer_all(data,sizeof(data),&sent,&f,write_fake,now)==LIBUSB_ERROR_TIMEOUT);
    CHECK(sent==0 && f.calls==60);
    f=(fixture){.base=data,.scenario=2};
    CHECK(bjc_transfer_all(data,sizeof(data),&sent,&f,write_fake,now)==LIBUSB_ERROR_NO_DEVICE);
    CHECK(sent==17 && f.calls==1);
    for(int scenario=3;scenario<=4;scenario++) {
        f=(fixture){.base=data,.scenario=scenario};
        CHECK(bjc_transfer_all(data,sizeof(data),&sent,&f,write_fake,now)==LIBUSB_ERROR_IO);
        CHECK(sent==0);
    }
    puts("Partial writes, timed pauses, disconnects, and stalled transfers passed.");
    return 0;
}
