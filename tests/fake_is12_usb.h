#ifndef FAKE_IS12_USB_H
#define FAKE_IS12_USB_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { FAKE_CANCEL_NONE, FAKE_CANCEL_MODE, FAKE_CANCEL_AREA,
               FAKE_CANCEL_FINAL_READY, FAKE_CANCEL_LOAD } fake_cancel_point;
void fake_usb_reset(void);
void fake_usb_head(bool correct);
void fake_usb_warming(bool warming);
void fake_usb_loaded(bool loaded);
void fake_usb_recovery(bool blocked);
void fake_usb_cancel_at(fake_cancel_point point);
void fake_usb_fail_write(uint8_t command, int accepted);
unsigned fake_usb_writes(uint8_t command);
bool fake_usb_safe(void);
int is12_scan_main(const char *, bool, const char *, unsigned, bool, bool, bool, bool);
#endif
