#include "usb.h"
#include "admission.h"
#include <stdlib.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include "transfer.h"
#include "recovery.h"

int bjc_usb_open(bjc_usb *usb) {
    memset(usb, 0, sizeof(*usb));
    /* Serialize all native clients before opening USB. The persistent file is
       only an inode for flock; a crash releases ownership without replay. */
    int admission=bjc_admission_acquire();
    if (admission<0) return LIBUSB_ERROR_BUSY;
    usb->admission_fd_plus_one=admission+1;
    char lease_path[4096];
    snprintf(lease_path, sizeof(lease_path), "/tmp/bjc85-usb-%lu.lock", (unsigned long)getuid());
    const char *test=getenv("BJC85_OFFLINE_TEST"), *override=getenv("BJC85_USB_LEASE_PATH");
    if (test && !strcmp(test,"1") && override) {
        if (snprintf(lease_path,sizeof(lease_path),"%s",override)>=(int)sizeof(lease_path)) { bjc_usb_close(usb); return LIBUSB_ERROR_ACCESS; }
    }
    int fd = open(lease_path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    struct stat lease_stat;
    if (fd < 0) { bjc_usb_close(usb); return LIBUSB_ERROR_ACCESS; }
    if (fstat(fd, &lease_stat) || !S_ISREG(lease_stat.st_mode) ||
        lease_stat.st_uid != getuid() || lease_stat.st_nlink != 1 || (lease_stat.st_mode & 077)) {
        close(fd); bjc_usb_close(usb); return LIBUSB_ERROR_ACCESS;
    }
    if (flock(fd, LOCK_EX | LOCK_NB)) {
        int saved_errno = errno;
        close(fd);
        fprintf(stderr, "Another native BJC-85 operation owns USB. Finish or cancel it first.\n");
        bjc_usb_close(usb);
        return saved_errno == EWOULDBLOCK ? LIBUSB_ERROR_BUSY : LIBUSB_ERROR_ACCESS;
    }
    usb->lease_fd_plus_one = fd + 1;
    if (bjc_recovery_required()) {
        fputs("BJC-85 recovery required. Inspect the previous operation and physical device before continuing.\n",stderr);
        bjc_usb_close(usb); usb->recovery_blocked=1; return LIBUSB_ERROR_BUSY;
    }
    /* Offline tests may exercise locks, but can never enter libusb. */
    if (test && !strcmp(test,"1")) { bjc_usb_close(usb); return LIBUSB_ERROR_ACCESS; }
    int rc = libusb_init(&usb->context);
    if (rc < 0) { bjc_usb_close(usb); return rc; }
    libusb_device **devices = NULL;
    ssize_t count = libusb_get_device_list(usb->context, &devices);
    if (count < 0) { bjc_usb_close(usb); return (int)count; }
    libusb_device *target = NULL;
    unsigned matches = 0;
    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor desc;
        if (!libusb_get_device_descriptor(devices[i], &desc) &&
            desc.idVendor == BJC85_VID && desc.idProduct == BJC85_PID) {
            target = devices[i];
            usb->descriptor = desc;
            matches++;
        }
    }
    if (matches != 1) {
        fprintf(stderr, "Expected one Canon BJC-85 (04a9:1055); found %u.\n", matches);
        libusb_free_device_list(devices, 1);
        bjc_usb_close(usb);
        return matches ? LIBUSB_ERROR_BUSY : LIBUSB_ERROR_NO_DEVICE;
    }
    usb->bus = libusb_get_bus_number(target);
    usb->address = libusb_get_device_address(target);
    rc = libusb_get_active_config_descriptor(target, &usb->configuration);
    if (rc < 0) goto done;
    /* GET_DEVICE_ID takes the descriptor index, not bConfigurationValue. */
    for (uint8_t i = 0; i < usb->descriptor.bNumConfigurations; i++) {
        struct libusb_config_descriptor *candidate = NULL;
        rc = libusb_get_config_descriptor(target, i, &candidate);
        if (rc < 0) goto done;
        int matched = candidate->bConfigurationValue == usb->configuration->bConfigurationValue;
        libusb_free_config_descriptor(candidate);
        if (matched) { usb->configuration_index = i; break; }
    }
    unsigned interfaces = 0;
    for (int i = 0; i < usb->configuration->bNumInterfaces; i++) {
        const struct libusb_interface *iface = &usb->configuration->interface[i];
        for (int a = 0; a < iface->num_altsetting; a++) {
            const struct libusb_interface_descriptor *alt = &iface->altsetting[a];
            if (alt->bInterfaceClass != LIBUSB_CLASS_PRINTER ||
                alt->bInterfaceSubClass != 1 || alt->bInterfaceProtocol != 2 ||
                alt->bAlternateSetting != 0) continue;
            uint8_t in = 0, out = 0;
            for (int e = 0; e < alt->bNumEndpoints; e++) {
                const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) != LIBUSB_TRANSFER_TYPE_BULK) continue;
                if (ep->bEndpointAddress & LIBUSB_ENDPOINT_IN) in = ep->bEndpointAddress;
                else out = ep->bEndpointAddress;
            }
            if (!in || !out) continue;
            interfaces++;
            usb->interface_number = alt->bInterfaceNumber;
            usb->alternate_setting = alt->bAlternateSetting;
            usb->bulk_in = in;
            usb->bulk_out = out;
        }
    }
    if (interfaces != 1) { rc = LIBUSB_ERROR_NOT_SUPPORTED; goto done; }
    rc = libusb_open(target, &usb->handle);
done:
    libusb_free_device_list(devices, 1);
    if (rc < 0) bjc_usb_close(usb);
    return rc;
}

int bjc_usb_claim(bjc_usb *usb) {
    if (usb->claimed) return 0;
    /* Never detach a kernel driver, reset, or change the USB configuration. */
    int rc = libusb_claim_interface(usb->handle, usb->interface_number);
    if (!rc) usb->claimed = 1;
    return rc;
}

int bjc_usb_identity(bjc_usb *usb, unsigned char *data, uint16_t capacity) {
    return libusb_control_transfer(usb->handle, 0xa1, 0,
        usb->configuration_index,
        (uint16_t)((usb->interface_number << 8) | usb->alternate_setting),
        data, capacity, 2000);
}

int bjc_usb_status(bjc_usb *usb, uint8_t *status) {
    int rc = libusb_control_transfer(usb->handle, 0xa1, 1, 0,
                                   usb->interface_number, status, 1, 2000);
    return rc == 1 ? 0 : (rc < 0 ? rc : LIBUSB_ERROR_IO);
}

static int bulk_write(void *context, const unsigned char *data, int length, int *transferred) {
    bjc_usb *usb = context;
    return libusb_bulk_transfer(usb->handle, usb->bulk_out, (unsigned char *)data, length, transferred, 1000);
}

static uint64_t monotonic_ms(void *context) {
    (void)context;
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

int bjc_usb_write(bjc_usb *usb, const unsigned char *data, size_t length, size_t *sent) {
    if (bjc_usb_begin_operation(usb,"print")) { *sent=0; return LIBUSB_ERROR_IO; }
    return bjc_transfer_all(data, length, sent, usb, bulk_write, monotonic_ms);
}

int bjc_usb_begin_operation(bjc_usb *usb,const char *operation) {
    if (usb->operation_started) return 0;
    if (!usb->lease_fd_plus_one || !bjc_recovery_begin(operation)) return LIBUSB_ERROR_IO;
    usb->operation_started=1; return 0;
}
int bjc_usb_finish_safe(bjc_usb *usb) {
    if (!usb->operation_started) return 0;
    if (!bjc_recovery_finish_safe()) return LIBUSB_ERROR_IO;
    usb->operation_started=0; return 0;
}

void bjc_usb_close(bjc_usb *usb) {
    if (usb->claimed && usb->handle) libusb_release_interface(usb->handle, usb->interface_number);
    if (usb->handle) libusb_close(usb->handle);
    if (usb->configuration) libusb_free_config_descriptor(usb->configuration);
    if (usb->context) libusb_exit(usb->context);
    if (usb->lease_fd_plus_one) close(usb->lease_fd_plus_one - 1);
    if (usb->admission_fd_plus_one) close(usb->admission_fd_plus_one - 1);
    memset(usb, 0, sizeof(*usb));
}
