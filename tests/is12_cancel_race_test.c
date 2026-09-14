#include "fake_is12_usb.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    char parent[]="/tmp/is12-cancel-test-XXXXXX"; assert(mkdtemp(parent));
    const fake_cancel_point points[]={FAKE_CANCEL_FINAL_READY,FAKE_CANCEL_MODE,FAKE_CANCEL_AREA,FAKE_CANCEL_LOAD};
    for (unsigned i=0;i<sizeof(points)/sizeof(points[0]);i++) {
        fake_usb_reset(); fake_usb_cancel_at(points[i]);
        fake_usb_loaded(points[i]!=FAKE_CANCEL_LOAD);
        char path[1024]; snprintf(path,sizeof(path),"%s/case-%u",parent,i);
        assert(is12_scan_main(path,false,NULL,90,false,false,false,false)!=0);
        assert(fake_usb_writes('B')==0 && fake_usb_writes('W')==0);
        assert(fake_usb_writes('L')==(points[i]==FAKE_CANCEL_LOAD?1:0));
        assert(fake_usb_safe());
    }
    const uint8_t commands[]={'D','C','L','B','Q'};
    for (unsigned i=0;i<sizeof(commands);i++) {
        fake_usb_reset(); fake_usb_loaded(false); fake_usb_fail_write(commands[i],2);
        if (commands[i]=='Q') fake_usb_cancel_at(FAKE_CANCEL_LOAD);
        char path[1024]; snprintf(path,sizeof(path),"%s/failure-%u",parent,i);
        assert(is12_scan_main(path,false,NULL,90,false,false,false,false)==7);
        assert(!fake_usb_safe());
        assert(fake_usb_writes(commands[i])==1);
        if (commands[i]!='Q') assert(fake_usb_writes('Q')==0);
    }
    puts("Cancellation during readiness, mode, area, and loading never starts acquisition.");
    return 0;
}
