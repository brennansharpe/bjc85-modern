#include "usb.h"
#include "protocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void json_string(const char *text) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p == '"' || *p == '\\') printf("\\%c", *p);
        else if (*p < 0x20 || *p >= 0x7f) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}

static int report(bjc_usb *usb) {
    printf("{\n  \"schema_version\": 1,\n  \"vendor_id\": \"%04x\", \"product_id\": \"%04x\",\n",
           usb->descriptor.idVendor, usb->descriptor.idProduct);
    printf("  \"bcd_usb\": \"%04x\", \"bcd_device\": \"%04x\", \"ep0_max_packet\": %u,\n",
           usb->descriptor.bcdUSB, usb->descriptor.bcdDevice, usb->descriptor.bMaxPacketSize0);
    printf("  \"bus\": %u, \"address\": %u, \"configuration\": %u,\n",
           usb->bus, usb->address, usb->configuration->bConfigurationValue);
    printf("  \"interface\": %u, \"alternate_setting\": %u, \"class\": 7, \"subclass\": 1, \"protocol\": 2,\n",
           usb->interface_number, usb->alternate_setting);
    printf("  \"bulk_in\": \"%02x\", \"bulk_out\": \"%02x\",\n", usb->bulk_in, usb->bulk_out);
    printf("  \"endpoints\": [");
    int first = 1;
    for (int i = 0; i < usb->configuration->bNumInterfaces; i++) {
        const struct libusb_interface *iface = &usb->configuration->interface[i];
        for (int a = 0; a < iface->num_altsetting; a++) {
            const struct libusb_interface_descriptor *alt = &iface->altsetting[a];
            if (alt->bInterfaceNumber != usb->interface_number || alt->bAlternateSetting != 0) continue;
            for (int e = 0; e < alt->bNumEndpoints; e++) {
                const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                printf("%s{\"address\": \"%02x\", \"attributes\": %u, \"max_packet_size\": %u, \"interval\": %u}",
                       first ? "" : ", ", ep->bEndpointAddress, ep->bmAttributes, ep->wMaxPacketSize, ep->bInterval);
                first = 0;
            }
        }
    }
    printf("],\n  \"serial\": ");
    unsigned char serial[256] = {0};
    int rc = libusb_get_string_descriptor_ascii(usb->handle, usb->descriptor.iSerialNumber, serial, sizeof(serial)-1);
    if (rc > 0) { serial[rc] = 0; json_string((char *)serial); } else printf("null");
    int claim_rc = bjc_usb_claim(usb);
    printf(",\n  \"claim_result\": "); json_string(libusb_error_name(claim_rc));
    unsigned char identity[2048];
    char id[2048];
    int id_rc = claim_rc < 0 ? claim_rc : bjc_usb_identity(usb, identity, sizeof(identity));
    printf(",\n  \"device_id_transfer_bytes\": %d,\n  \"device_id\": ", id_rc);
    int valid_id = id_rc >= 0 && bjc_device_id(identity, (size_t)id_rc, id, sizeof(id));
    if (valid_id) json_string(id); else printf("null");
    uint8_t status = 0;
    int status_rc = claim_rc < 0 ? claim_rc : bjc_usb_status(usb, &status);
    printf(",\n  \"status_result\": "); json_string(libusb_error_name(status_rc));
    printf(",\n  \"port_status\": ");
    if (!status_rc) printf("{\"raw\": %u, \"paper_empty\": %s, \"selected\": %s, \"not_error\": %s, \"ready\": %s}",
        status, status & 0x20 ? "true":"false", status & 0x10 ? "true":"false",
        status & 0x08 ? "true":"false", bjc_port_ready(status) ? "true":"false");
    else printf("null");
    printf(",\n  \"cartridge\": \"unknown\"\n}\n");
    return claim_rc < 0 || !valid_id || status_rc < 0 ? 1 : 0;
}

static int send_file(bjc_usb *usb, const char *filename) {
    FILE *input = fopen(filename, "rb");
    if (!input) { perror(filename); return 1; }
    if (fseek(input, 0, SEEK_END)) { fclose(input); return 1; }
    long length = ftell(input);
    if (length <= 0 || length > 64 * 1024 * 1024 || fseek(input, 0, SEEK_SET)) {
        fprintf(stderr, "Expected a nonempty raw print job no larger than 64 MiB.\n"); fclose(input); return 1;
    }
    unsigned char *data = malloc((size_t)length);
    if (!data) { fclose(input); return 1; }
    size_t got = fread(data, 1, (size_t)length, input);
    fclose(input);
    if (got != (size_t)length) { free(data); return 1; }
    int rc = bjc_usb_claim(usb);
    uint8_t status = 0;
    if (!rc) rc = bjc_usb_status(usb, &status);
    if (rc < 0 || !bjc_port_ready(status)) {
        fprintf(stderr, "Printer is not ready (query=%s, status=0x%02x). Nothing sent.\n", libusb_error_name(rc), status);
        free(data); return 1;
    }
    size_t sent = 0;
    rc = bjc_usb_write(usb, data, (size_t)length, &sent);
    free(data);
    fprintf(stderr, "USB accepted %zu/%ld bytes: %s. Physical output still requires inspection.\n",
            sent, length, libusb_error_name(rc));
    return rc < 0 ? 1 : 0;
}

int main(int argc, char **argv) {
    int probe = argc == 2 && !strcmp(argv[1], "probe");
    int send = argc == 5 && !strcmp(argv[1], "send") &&
               !strcmp(argv[3], "--print-cartridge=bc11e") && !strcmp(argv[4], "--paper-loaded");
    if (!probe && !send) {
        fprintf(stderr, "Usage: %s probe\n       %s send JOB.bjc --print-cartridge=bc11e --paper-loaded\n"
                "probe issues read-only standard/class requests. send physically prints a raw job.\n", argv[0], argv[0]);
        return 2;
    }
    bjc_usb usb;
    int rc = bjc_usb_open(&usb);
    if (rc < 0) {
        fprintf(stderr, "Cannot open BJC-85: %s.\n", libusb_error_name(rc));
        bjc_usb_close(&usb); return 1;
    }
    int result = probe ? report(&usb) : send_file(&usb, argv[2]);
    bjc_usb_close(&usb);
    return result;
}
