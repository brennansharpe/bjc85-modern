/* Link-time transport replacement: the real CLI/parser/acquisition code runs,
 * but no libusb library or device is opened. Reply bytes mirror hardware framing. */
#include "fake_is12_usb.h"
#include "usb.h"
#include <assert.h>
#include <signal.h>
#include <string.h>
static struct {
    bool head, warming, loaded, safe, recovery;
    fake_cancel_point cancel;
    uint8_t reply[128], last, selector, fail;
    int reply_size, accepted;
    unsigned writes[256], statuses;
} fake;
void fake_usb_reset(void) { memset(&fake,0,sizeof(fake)); fake.head=true; fake.loaded=true; }
void fake_usb_head(bool value) { fake.head=value; }
void fake_usb_warming(bool value) { fake.warming=value; }
void fake_usb_loaded(bool value) { fake.loaded=value; }
void fake_usb_recovery(bool value) { fake.recovery=value; }
void fake_usb_cancel_at(fake_cancel_point value) { fake.cancel=value; }
void fake_usb_fail_write(uint8_t command,int accepted) { fake.fail=command; fake.accepted=accepted; }
unsigned fake_usb_writes(uint8_t command) { return fake.writes[command]; }
bool fake_usb_safe(void) { return fake.safe; }
int bjc_usb_open(bjc_usb *usb) {
    memset(usb,0,sizeof(*usb));
    if (fake.recovery) { usb->recovery_blocked=1; return LIBUSB_ERROR_BUSY; }
    usb->handle=(libusb_device_handle *)&fake;
    usb->bulk_in=0x82; usb->bulk_out=1; return 0;
}
int bjc_usb_claim(bjc_usb *usb) { (void)usb; return 0; }
void bjc_usb_close(bjc_usb *usb) { (void)usb; }
int bjc_usb_begin_operation(bjc_usb *usb,const char *operation) { (void)usb; (void)operation; fake.safe=false; return 0; }
int bjc_usb_finish_safe(bjc_usb *usb) { (void)usb; fake.safe=true; return 0; }
int bjc_usb_identity(bjc_usb *usb,unsigned char *data,uint16_t capacity) {
    (void)usb; const char *id="MFG:Canon;MDL:BJC-85;"; size_t n=strlen(id)+2;
    assert(n<=capacity); data[0]=(uint8_t)(n>>8); data[1]=(uint8_t)n;
    memcpy(data+2,id,n-2); return (int)n;
}
int libusb_get_string_descriptor_ascii(libusb_device_handle *handle,uint8_t index,unsigned char *data,int length) {
    (void)handle; (void)index; assert(length>=6); memcpy(data,"FAKE01",6); return 6;
}
static void reply(uint8_t token,const uint8_t *data,size_t length) {
    size_t n=8+length; assert(n<=sizeof(fake.reply));
    uint8_t header[]={0,(uint8_t)n,0x1b,'!','s',(uint8_t)(length+1),0,token};
    memcpy(fake.reply,header,8); memcpy(fake.reply+8,data,length); fake.reply_size=(int)n;
}
int libusb_bulk_transfer(libusb_device_handle *handle,unsigned char endpoint,unsigned char *data,int length,int *count,unsigned int timeout) {
    (void)handle; (void)timeout; *count=0;
    if (endpoint==0x82) {
        if (!fake.reply_size) return 0;
        assert(length>=fake.reply_size); memcpy(data,fake.reply,(size_t)fake.reply_size);
        *count=fake.reply_size; fake.reply_size=0;
        bool cancel=(fake.cancel==FAKE_CANCEL_MODE && fake.last=='D') ||
            (fake.cancel==FAKE_CANCEL_AREA && fake.last=='C') ||
            (fake.cancel==FAKE_CANCEL_FINAL_READY && fake.last=='R' && fake.selector==2 && fake.statuses==2) ||
            (fake.cancel==FAKE_CANCEL_LOAD && fake.last=='L');
        if (cancel) { fake.cancel=FAKE_CANCEL_NONE; raise(SIGINT); }
        return 0;
    }
    assert(endpoint==1 && length>=6); fake.last=data[5]; fake.writes[fake.last]++;
    *count=length;
    if (fake.last==fake.fail || fake.last=='B' || fake.last=='W') {
        *count=fake.last==fake.fail ? fake.accepted : 0; return LIBUSB_ERROR_IO;
    }
    uint8_t status[]={0,0,0};
    if (fake.last=='L') fake.loaded=true;
    if (fake.last=='Q') fake.loaded=false;
    status[0]=fake.loaded?0x10:0; status[1]=fake.warming?8:0;
    if (data[1]=='[') { fake.last='K'; reply('s',status,3); return 0; }
    if (fake.last=='R') {
        fake.selector=data[6];
        const uint8_t carrier[]={0xb0,1,0x0e,0x80,1,0,0,0x0b,0x40,0,0x10,0x0e};
        uint8_t info[]={0x70,0x19,0x11,1,0x1f,1,0x68,0x0b,0x88};
        const uint8_t temp[]={52}, extended[18]={1,0x0f};
        if (!fake.head) info[0]=0;
        switch(fake.selector) {
        case 0: reply('c',carrier,sizeof(carrier)); break;
        case 1: reply('i',info,sizeof(info)); break;
        case 2: fake.statuses++; reply('s',status,3); break;
        case 3: reply('t',temp,1); break;
        case 4: reply('e',extended,18); break;
        default: assert(false);
        }
    } else if (fake.last=='C') reply('C',data+6,8);
    else reply('s',status,3);
    return 0;
}
