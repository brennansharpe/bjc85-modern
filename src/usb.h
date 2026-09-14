#ifndef BJC85_USB_H
#define BJC85_USB_H
#include <libusb.h>
#include <stddef.h>
#include <stdint.h>

#define BJC85_VID 0x04a9
#define BJC85_PID 0x1055

typedef struct {
    libusb_context *context;
    libusb_device_handle *handle;
    struct libusb_device_descriptor descriptor;
    struct libusb_config_descriptor *configuration;
    uint8_t interface_number, alternate_setting, bulk_in, bulk_out;
    uint8_t bus, address, configuration_index;
    int claimed;
    int lease_fd_plus_one;
} bjc_usb;

int bjc_usb_open(bjc_usb *usb);
int bjc_usb_claim(bjc_usb *usb);
int bjc_usb_identity(bjc_usb *usb, unsigned char *data, uint16_t capacity);
int bjc_usb_status(bjc_usb *usb, uint8_t *status);
int bjc_usb_write(bjc_usb *usb, const unsigned char *data, size_t length, size_t *sent);
void bjc_usb_close(bjc_usb *usb);
#endif
