/* Local IPP prototype. PAPPL handles IPP/Apple Raster; Gutenprint emits BJRaster. */
#include "usb.h"
#include "protocol.h"
#include "transfer.h"
#include <pappl/pappl.h>
#include <gutenprint/gutenprint.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define MAX_JOB_BYTES (64u * 1024u * 1024u)

static struct {
    char spool[PATH_MAX], recovery[PATH_MAX], state[PATH_MAX];
    bool dry_run;
} service;

typedef struct {
    bjc_usb usb;
    bool opened, failed;
    pappl_job_t *job;
} device_state;

typedef struct {
    FILE *stream;
    char filename[PATH_MAX];
    stp_vars_t *vars;
    stp_image_t image;
    unsigned char *rgb;
    unsigned width, height, crop_left, crop_top, full_height, next_y, pages;
    size_t bytes;
    int copies;
    bool failed, started;
    pappl_job_t *job;
} job_state;

/* PAPPL's formatter does not support every printf length modifier. Format
   locally, then pass one terminated string through its escaping logger. */
static void job_log(pappl_job_t *job, pappl_loglevel_t level, const char *format, ...) __attribute__((format(printf, 3, 4)));
static void job_log(pappl_job_t *job, pappl_loglevel_t level, const char *format, ...) {
    char message[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    papplLogJob(job, level, "%s", message);
}

static bool device_open(pappl_device_t *device, const char *uri, const char *name) {
    (void)name;
    if (strcmp(uri, "bjc85native://usb")) return false;
    device_state *state = calloc(1, sizeof(*state));
    if (!state) return false;
    papplDeviceSetData(device, state);
    return true;
}

static void device_close(pappl_device_t *device) {
    device_state *state = papplDeviceGetData(device);
    if (!state) return;
    if (state->opened) bjc_usb_close(&state->usb);
    free(state);
    papplDeviceSetData(device, NULL);
}

static uint64_t now_ms(void *context) {
    (void)context;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static int transfer(void *context, const unsigned char *data, int length, int *sent) {
    device_state *state = context;
    *sent = 0;
    if (papplJobIsCanceled(state->job)) return LIBUSB_ERROR_INTERRUPTED;
    return libusb_bulk_transfer(state->usb.handle, state->usb.bulk_out,
                               (unsigned char *)data, length, sent, 1000);
}

/* The driver calls this directly so a final buffered write cannot hide errors. */
static ssize_t device_write(pappl_device_t *device, const void *data, size_t length) {
    device_state *state = papplDeviceGetData(device);
    if (!state || !state->job || service.dry_run) { errno = EINVAL; return -1; }
    if (!state->opened) {
        int rc = bjc_usb_open(&state->usb);
        if (!rc) rc = bjc_usb_claim(&state->usb);
        uint8_t status = 0;
        if (!rc) rc = bjc_usb_status(&state->usb, &status);
        if (rc < 0 || !bjc_port_ready(status)) {
            job_log(state->job, PAPPL_LOGLEVEL_ERROR,
                        "USB unavailable: %s, status=0x%02x. Nothing sent.", libusb_error_name(rc), status);
            bjc_usb_close(&state->usb);
            errno = EIO;
            return -1;
        }
        state->opened = true;
    }
    size_t sent = 0;
    int rc = bjc_transfer_all(data, length, &sent, state, transfer, now_ms);
    if (rc < 0) {
        state->failed = true;
        job_log(state->job, PAPPL_LOGLEVEL_ERROR,
                    "USB stopped after %zu/%zu bytes in this block: %s.", sent, length, libusb_error_name(rc));
        /* Keep the precise partial count even when the USB operation failed. */
        errno = EIO;
        return (ssize_t)sent;
    }
    return (ssize_t)sent;
}

static void image_noop(stp_image_t *image) { (void)image; }
static int image_width(stp_image_t *image) { return (int)((job_state *)image->rep)->width; }
static int image_height(stp_image_t *image) { return (int)((job_state *)image->rep)->height; }
static const char *image_app(stp_image_t *image) { (void)image; return "BJC85 Native IPP"; }
static stp_image_status_t image_row(stp_image_t *image, unsigned char *data, size_t limit, int row) {
    job_state *state = image->rep;
    size_t bytes = (size_t)state->width * 3;
    if (state->failed || papplJobIsCanceled(state->job) || row < 0 ||
        (unsigned)row >= state->height || limit < bytes) return STP_IMAGE_STATUS_ABORT;
    memcpy(data, state->rgb + (size_t)row * bytes, bytes);
    return STP_IMAGE_STATUS_OK;
}

static void output_bytes(void *context, const char *data, size_t length) {
    job_state *state = context;
    if (state->failed) return;
    if (length > MAX_JOB_BYTES - state->bytes || fwrite(data, 1, length, state->stream) != length) {
        state->failed = true;
        return;
    }
    state->bytes += length;
}

static void output_error(void *context, const char *data, size_t length) {
    job_state *state = context;
    job_log(state->job, PAPPL_LOGLEVEL_ERROR, "Gutenprint: %.*s", (int)(length > 2000 ? 2000 : length), data);
}

static bool start_job(pappl_job_t *job, pappl_pr_options_t *options, pappl_device_t *device) {
    if (!access(service.recovery, F_OK)) {
        job_log(job, PAPPL_LOGLEVEL_ERROR, "Printer recovery required; see %s.", service.recovery);
        return false;
    }
    if (options->copies < 1 || options->copies > 999) return false;
    job_state *state = calloc(1, sizeof(*state));
    if (!state) return false;
    state->job = job;
    state->copies = options->copies;
    int n = snprintf(state->filename, sizeof(state->filename), "%s/job-%d-XXXXXX.bjc", service.spool, papplJobGetID(job));
    if (n < 0 || n >= (int)sizeof(state->filename)) { free(state); return false; }
    int fd = mkstemps(state->filename, 4);
    state->stream = fd < 0 ? NULL : fdopen(fd, "w+b");
    if (!state->stream) { if (fd >= 0) close(fd); free(state); return false; }
    state->image = (stp_image_t){image_noop, image_noop, image_width, image_height, image_row, image_app, image_noop, state};
    papplJobSetData(job, state);
    ((device_state *)papplDeviceGetData(device))->job = job;
    return true;
}

static bool start_page(pappl_job_t *job, pappl_pr_options_t *options, pappl_device_t *device, unsigned page) {
    (void)device;
    job_state *state = papplJobGetData(job);
    cups_page_header2_t *header = &options->header;
    const char *paper = !strcmp(options->media.size_name, "na_letter_8.5x11in") ? "Letter" :
                        !strcmp(options->media.size_name, "iso_a4_210x297mm") ? "A4" : NULL;
    bool rgb = header->cupsColorSpace == CUPS_CSPACE_SRGB || header->cupsColorSpace == CUPS_CSPACE_RGB;
    bool gray = header->cupsColorSpace == CUPS_CSPACE_SW || header->cupsColorSpace == CUPS_CSPACE_W || header->cupsColorSpace == CUPS_CSPACE_K;
    if (!state || state->failed || !paper || page >= 1000 ||
        header->HWResolution[0] != 360 || header->HWResolution[1] != 360 ||
        header->cupsBitsPerColor != 8 || header->cupsColorOrder != CUPS_ORDER_CHUNKED ||
        (!rgb && !gray) || header->cupsBitsPerPixel != (rgb ? 24u : 8u) ||
        header->cupsWidth > 3100 || header->cupsHeight > 4300 ||
        header->cupsBytesPerLine != header->cupsWidth * (rgb ? 3u : 1u)) {
        if (state) state->failed = true;
        job_log(job, PAPPL_LOGLEVEL_ERROR, "Unsupported raster geometry, resolution, or colour format.");
        return false;
    }
    if (!state->vars) {
        state->vars = stp_vars_create();
        stp_set_printer_defaults(state->vars, stp_get_printer_by_driver("bjc-85"));
    }
    stp_set_string_parameter(state->vars, "PageSize", paper);
    stp_set_string_parameter(state->vars, "MediaType", "Plain");
    stp_set_string_parameter(state->vars, "InputSlot", "Auto");
    stp_set_string_parameter(state->vars, "Quality", "None");
    stp_set_string_parameter(state->vars, "Resolution", options->print_quality == IPP_QUALITY_DRAFT ? "360x360dpi_draft" :
                             options->print_quality == IPP_QUALITY_HIGH ? "360x360dpi_high" : "360x360dpi");
    bool color = options->print_color_mode == PAPPL_COLOR_MODE_COLOR || options->print_color_mode == PAPPL_COLOR_MODE_AUTO;
    stp_set_string_parameter(state->vars, "InkType", color ? "CMYK" : "Gray");
    stp_set_string_parameter(state->vars, "PrintingMode", color ? "Color" : "BW");
    stp_set_string_parameter(state->vars, "InputImageType", "RGB");
    stp_set_string_parameter(state->vars, "ChannelBitDepth", "8");
    stp_set_string_parameter(state->vars, "JobMode", "Job");
    stp_dimension_t left, right, bottom, top;
    stp_get_imageable_area(state->vars, &left, &right, &bottom, &top);
    stp_set_left(state->vars, left); stp_set_top(state->vars, top);
    stp_set_width(state->vars, right-left); stp_set_height(state->vars, bottom-top);
    stp_merge_printvars(state->vars, stp_printer_get_defaults(stp_get_printer_by_driver("bjc-85")));
    state->crop_left = (unsigned)lround(left * 5);
    state->crop_top = (unsigned)lround(top * 5);
    state->width = (unsigned)lround((right-left) * 5);
    state->height = (unsigned)lround((bottom-top) * 5);
    state->full_height = header->cupsHeight;
    state->next_y = 0;
    if (!stp_verify(state->vars) || !state->width || !state->height ||
        state->crop_left + state->width > header->cupsWidth ||
        state->crop_top + state->height > header->cupsHeight) {
        state->failed = true;
        return false;
    }
    free(state->rgb);
    state->rgb = malloc((size_t)state->width * state->height * 3);
    if (!state->rgb) { state->failed = true; return false; }
    memset(state->rgb, 255, (size_t)state->width * state->height * 3);
    stp_set_outfunc(state->vars, output_bytes); stp_set_outdata(state->vars, state);
    stp_set_errfunc(state->vars, output_error); stp_set_errdata(state->vars, state);
    return true;
}

static bool write_line(pappl_job_t *job, pappl_pr_options_t *options, pappl_device_t *device, unsigned y, const unsigned char *line) {
    (void)device;
    job_state *state = papplJobGetData(job);
    if (!state || state->failed || y != state->next_y || y >= state->full_height) {
        if (state) state->failed = true;
        return false;
    }
    state->next_y++;
    if (y < state->crop_top || y >= state->crop_top + state->height) return true;
    unsigned char *out = state->rgb + (size_t)(y-state->crop_top) * state->width * 3;
    if (options->header.cupsBitsPerPixel == 24) {
        memcpy(out, line + state->crop_left * 3, state->width * 3);
    } else {
        for (unsigned x = 0; x < state->width; x++) {
            unsigned char v = line[state->crop_left + x];
            if (options->header.cupsColorSpace == CUPS_CSPACE_K) v = 255-v;
            out[3*x] = out[3*x+1] = out[3*x+2] = v;
        }
    }
    return true;
}

static bool end_page(pappl_job_t *job, pappl_pr_options_t *options, pappl_device_t *device, unsigned page) {
    (void)options; (void)device; (void)page;
    job_state *state = papplJobGetData(job);
    if (!state || state->failed || state->next_y != state->full_height || papplJobIsCanceled(job)) {
        if (state) state->failed = true;
        return false;
    }
    if (!state->started) {
        state->started = stp_start_job(state->vars, &state->image) == 1;
        if (!state->started) state->failed = true;
    }
    if (!state->failed && stp_print(state->vars, &state->image) != 1) state->failed = true;
    if (!state->failed) state->pages++;
    return !state->failed;
}

static bool end_job(pappl_job_t *job, pappl_pr_options_t *options, pappl_device_t *device) {
    (void)options;
    job_state *state = papplJobGetData(job);
    if (!state) return false;
    bool success = !state->failed && state->pages && !papplJobIsCanceled(job) && papplJobGetState(job) != IPP_JSTATE_ABORTED;
    if (success) success = stp_end_job(state->vars, &state->image) == 1 && !state->failed;
    if (fflush(state->stream) || ferror(state->stream)) success = false;
    size_t accepted = 0;
    if (success && !service.dry_run) {
        /* A process crash leaves this marker, preventing automatic replay. */
        FILE *journal = fopen(service.recovery, "w");
        if (!journal) success = false;
        else {
            if (fprintf(journal, "Job %d is being submitted. Accepted bytes are unknown if interrupted.\nRaw job: %s\nInspect/reset the printer before removing this marker. Never replay automatically.\n", papplJobGetID(job), state->filename) < 0 ||
                fflush(journal) || fsync(fileno(journal))) success = false;
            if (fclose(journal)) success = false;
        }
        unsigned char buffer[65536];
        for (int copy = 0; copy < state->copies && success; copy++) {
            if (fseek(state->stream, 0, SEEK_SET)) { success = false; break; }
            size_t bytes;
            while ((bytes = fread(buffer, 1, sizeof(buffer), state->stream)) > 0) {
                if (papplJobIsCanceled(job)) { success = false; break; }
                ssize_t sent = device_write(device, buffer, bytes);
                if (sent > 0) accepted += (size_t)sent;
                if (sent != (ssize_t)bytes || ((device_state *)papplDeviceGetData(device))->failed) { success = false; break; }
            }
            if (ferror(state->stream)) success = false;
        }
        if (!success && accepted) {
            FILE *marker = fopen(service.recovery, "w");
            if (marker) {
                fprintf(marker, "Job %d stopped after %zu accepted USB bytes.\nRaw job: %s\nDo not replay. Inspect/reset the printer, then remove this marker before resuming.\n", papplJobGetID(job), accepted, state->filename);
                fclose(marker);
            }
            papplPrinterPause(papplJobGetPrinter(job));
        }
        if (success || !accepted) unlink(service.recovery);
    }
    job_log(job, success ? PAPPL_LOGLEVEL_INFO : PAPPL_LOGLEVEL_ERROR,
                "%s: %u pages, %d copies, %zu raw bytes, %zu USB bytes accepted. Raw file: %s",
                service.dry_run ? "Dry run (no USB)" : (success ? "Transfer complete" : "Transfer stopped"),
                state->pages, state->copies, state->bytes, accepted, state->filename);
    if (fclose(state->stream)) success = false;
    if (success && state->copies > 1) {
        papplJobSetCopiesCompleted(job, state->copies-1);
        papplJobSetImpressionsCompleted(job, (int)state->pages * (state->copies-1));
    }
    if (state->vars) stp_vars_destroy(state->vars);
    free(state->rgb); free(state);
    papplJobSetData(job, NULL);
    ((device_state *)papplDeviceGetData(device))->job = NULL;
    return success;
}

static bool status(pappl_printer_t *printer) { (void)printer; return true; }

static bool save_state(pappl_system_t *system, void *context) {
    (void)context;
    char temporary[PATH_MAX];
    if (snprintf(temporary, sizeof(temporary), "%s.XXXXXX", service.state) >= (int)sizeof(temporary)) return false;
    int fd = mkstemp(temporary);
    if (fd < 0) return false;
    close(fd);
    bool success = papplSystemSaveState(system, temporary);
    if (success) {
        fd = open(temporary, O_RDWR);
        if (fd < 0) success = false;
        else { if (fsync(fd)) success = false; close(fd); }
    }
    if (success && rename(temporary, service.state)) success = false;
    if (!success) unlink(temporary);
    return success;
}

static bool driver(pappl_system_t *system, const char *driver_name, const char *uri, const char *id,
                   pappl_pr_driver_data_t *data, ipp_t **attrs, void *context) {
    (void)system; (void)uri; (void)id; (void)context;
    if (strcmp(driver_name, "bjc-85")) return false;
    papplCopyString(data->make_and_model, "Canon BJC-85 Native ARM64", sizeof(data->make_and_model));
    data->format = NULL;
    data->printfile_cb = NULL;
    data->rstartjob_cb = start_job; data->rendjob_cb = end_job;
    data->rstartpage_cb = start_page; data->rendpage_cb = end_page;
    data->rwriteline_cb = write_line; data->status_cb = status;
    data->kind = PAPPL_KIND_DOCUMENT;
    data->ppm = 1; data->ppm_color = 1;
    data->has_supplies = false;
    data->color_supported = PAPPL_COLOR_MODE_COLOR | PAPPL_COLOR_MODE_MONOCHROME;
    data->color_default = PAPPL_COLOR_MODE_COLOR;
    data->raster_types = PAPPL_PWG_RASTER_TYPE_SRGB_8 | PAPPL_PWG_RASTER_TYPE_SGRAY_8;
    data->num_resolution = 1;
    data->x_resolution[0] = data->y_resolution[0] = data->x_default = data->y_default = 360;
    data->sides_supported = data->sides_default = PAPPL_SIDES_ONE_SIDED;
    data->left_right = 353; data->bottom_top = 706;
    data->num_media = 2;
    data->media[0] = "na_letter_8.5x11in"; data->media[1] = "iso_a4_210x297mm";
    data->num_source = 1; data->source[0] = "main";
    data->num_type = 1; data->type[0] = "stationery";
    papplCopyString(data->media_default.size_name, data->media[0], sizeof(data->media_default.size_name));
    papplCopyString(data->media_default.source, "main", sizeof(data->media_default.source));
    papplCopyString(data->media_default.type, "stationery", sizeof(data->media_default.type));
    data->media_default.size_width = 21590;
    data->media_default.size_length = 27940;
    data->media_default.left_margin = data->media_default.right_margin = data->left_right;
    data->media_default.top_margin = data->media_default.bottom_margin = data->bottom_top;
    data->media_ready[0] = data->media_default;
    data->quality_default = IPP_QUALITY_NORMAL;
    *attrs = NULL;
    return true;
}

int main(int argc, char **argv) {
    const char *spool = NULL;
    int port = 8631;
    bool cartridge = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--dry-run")) service.dry_run = true;
        else if (!strcmp(argv[i], "--print-cartridge=bc11e")) cartridge = true;
        else if (!strcmp(argv[i], "--spool-dir") && i+1 < argc) spool = argv[++i];
        else if (!strcmp(argv[i], "--port") && i+1 < argc) {
            char *end;
            long value = strtol(argv[++i], &end, 10);
            if (*end || value < 1024 || value > 65535) return 2;
            port = (int)value;
        } else { fprintf(stderr, "Unknown or incomplete option: %s\n", argv[i]); return 2; }
    }
    if (!spool || (!cartridge && !service.dry_run)) {
        fprintf(stderr, "Usage: %s --spool-dir DIRECTORY [--port 8631] (--print-cartridge=bc11e | --dry-run)\n", argv[0]);
        return 2;
    }
    umask(0077);
    if (mkdir(spool, 0700) && errno != EEXIST) { perror(spool); return 1; }
    struct stat info;
    if (lstat(spool, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid() ||
        (info.st_mode & 0077) || !realpath(spool, service.spool)) {
        fprintf(stderr, "Spool directory must be a private directory owned by this user.\n"); return 1;
    }
    if (snprintf(service.recovery, sizeof(service.recovery), "%s/usb-recovery-required.txt", service.spool) >= (int)sizeof(service.recovery)) return 1;
    if (snprintf(service.state, sizeof(service.state), "%s/printer.state", service.spool) >= (int)sizeof(service.state)) return 1;
    if (stp_init() || !stp_get_printer_by_driver("bjc-85")) return 1;
    papplDeviceAddScheme("bjc85native", PAPPL_DEVTYPE_CUSTOM_LOCAL, NULL, device_open, device_close, NULL, device_write, NULL, NULL);
    pappl_pr_driver_t drivers[] = {{"bjc-85", "Canon BJC-85 Native ARM64", NULL, NULL}};
    pappl_system_t *system = papplSystemCreate(PAPPL_SOPTIONS_NO_TLS | PAPPL_SOPTIONS_WEB_INTERFACE,
        service.dry_run ? "BJC-85 Dry Run" : "BJC-85 Native", port, NULL, service.spool, "-",
        service.dry_run ? PAPPL_LOGLEVEL_DEBUG : PAPPL_LOGLEVEL_INFO, NULL, false);
    if (!system) return 1;
    /* PAPPL 1.4.12 localizes the footer even when it is NULL. Providing text
       avoids a null key in its localization lookup when serving web pages. */
    papplSystemSetFooterHTML(system, "BC-11e printing on Letter or A4 plain paper.");
    papplSystemSetMaxClients(system, 8);
    papplSystemSetHostName(system, "localhost");
    papplSystemSetDNSSDName(system, NULL);
    if (!papplSystemAddListeners(system, "127.0.0.1")) { papplSystemDelete(system); return 1; }
    papplSystemSetPrinterDrivers(system, 1, drivers, NULL, NULL, driver, NULL);
    pappl_printer_t *printer;
    if (!access(service.state, F_OK)) {
        if (!papplSystemLoadState(system, service.state)) { papplSystemDelete(system); return 1; }
        printer = papplSystemFindPrinter(system, NULL, 1, NULL);
    } else {
        printer = papplPrinterCreate(system, 1, service.dry_run ? "Canon BJC-85 Dry Run" : "Canon BJC-85 Native", "bjc-85", NULL, "bjc85native://usb");
    }
    if (!printer) { papplSystemDelete(system); return 1; }
    if (strcmp(papplPrinterGetDeviceURI(printer), "bjc85native://usb") || strcmp(papplPrinterGetDriverName(printer), "bjc-85")) {
        fprintf(stderr, "Saved state is not for this BJC-85 service.\n"); papplSystemDelete(system); return 1;
    }
    papplSystemSetDNSSDName(system, NULL);
    papplPrinterSetDNSSDName(printer, NULL);
    papplSystemSetSaveCallback(system, save_state, NULL);
    papplPrinterSetMaxActiveJobs(printer, 10);
    papplPrinterSetMaxCompletedJobs(printer, 20);
    papplPrinterSetMaxPreservedJobs(printer, 0);
    fprintf(stderr, "Native %s service: ipp://localhost:%d/ipp/print\n", service.dry_run ? "dry-run" : "USB print", port);
    papplSystemRun(system);
    save_state(system, NULL);
    papplSystemDelete(system);
    return 0;
}
