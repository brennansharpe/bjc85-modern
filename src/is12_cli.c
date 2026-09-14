#include "is12_protocol.h"
#include "is12_image.h"
#include "protocol.h"
#include "usb.h"
#include "is12_status.h"
#include "is12_calibration.h"
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int is12_scan_main(const char *directory,bool calibration,const char *reference,unsigned dpi,bool grayscale,bool lineart,bool blackwhite,bool live_preview);
static bool diagnostic_transport_ok;

static unsigned parse_dpi(const char *value) {
    return !strcmp(value,"90")?90:!strcmp(value,"180")?180:!strcmp(value,"360")?360:0;
}

static uint64_t now_ms(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return (uint64_t)value.tv_sec * 1000 + (uint64_t)value.tv_nsec / 1000000;
}

static void hex(const uint8_t *data, size_t length) {
    putchar('"');
    for (size_t i=0; i<length; i++) printf("%s%02x", i ? " " : "", data[i]);
    putchar('"');
}

static bool send_request(bjc_usb *usb, const char *stage, const uint8_t *data, size_t length) {
    if (bjc_usb_begin_operation(usb,"scanner-status")) { diagnostic_transport_ok=false; return false; }
    int accepted = 0;
    int rc = libusb_bulk_transfer(usb->handle, usb->bulk_out, (uint8_t *)data, (int)length, &accepted, 1000);
    printf("{\"event\":\"write\",\"stage\":\"%s\",\"requested\":%zu,\"accepted\":%d,\"usb_result\":%d,\"hex\":", stage, length, accepted, rc);
    hex(data, length); puts("}"); fflush(stdout);
    /* A diagnostic never retries or resets after a partial/failed write. */
    if (rc || accepted != (int)length) { diagnostic_transport_ok=false; return false; }
    return true;
}

typedef struct {
    const char *stage;
    uint8_t token;
    size_t expected, alternate, records;
    uint8_t *result;
    bool found;
} reply_context;

static bool log_reply(const is12_reply *reply, void *context) {
    reply_context *state = context;
    printf("{\"event\":\"reply\",\"stage\":\"%s\",\"kind\":%u,\"family\":%u,\"token\":%u,\"payload_hex\":",
           state->stage, reply->kind, reply->family, reply->token);
    hex(reply->payload, reply->length); puts("}"); fflush(stdout);
    state->records++;
    if (!state->result) return true; /* Offline decoding reports all record families. */
    /* A line advance is unexpected during an idle diagnostic. */
    if (reply->family == 'e') return false;
    if (reply->family == 's' && reply->token == state->token &&
        (reply->length == state->expected || (state->alternate && reply->length == state->alternate)) &&
        (reply->kind == '!' || state->token == 's')) {
        memcpy(state->result, reply->payload, reply->length);
        state->found = true;
    }
    return true;
}

static bool receive_reply(bjc_usb *usb, const char *stage, uint8_t token, size_t expected,
                          size_t alternate, uint8_t *result) {
    is12_stream stream;
    is12_stream_init(&stream);
    reply_context state = {.stage=stage, .token=token, .expected=expected, .alternate=alternate, .result=result};
    size_t received = 0;
    uint64_t deadline = now_ms()+5000, last_data = now_ms();
    while (now_ms() < deadline) {
        uint8_t block[512];
        int count = 0;
        int rc = libusb_bulk_transfer(usb->handle, usb->bulk_in, block, sizeof(block), &count, 250);
        if (count < 0 || (size_t)count > sizeof(block)) { diagnostic_transport_ok=false; return false; }
        if (count) {
            printf("{\"event\":\"read\",\"stage\":\"%s\",\"usb_result\":%d,\"bytes\":%d,\"hex\":", stage, rc, count);
            hex(block, (size_t)count); puts("}"); fflush(stdout);
            received += (size_t)count;
            last_data = now_ms();
            if (received > IS12_BUFFER_LIMIT ||
                !is12_stream_feed(&stream, block, (size_t)count, log_reply, &state)) {
                printf("{\"event\":\"invalid_reply_stream\",\"stage\":\"%s\"}\n", stage);
                return false;
            }
        }
        if (rc < 0 && rc != LIBUSB_ERROR_TIMEOUT) {
            diagnostic_transport_ok=false;
            printf("{\"event\":\"read_error\",\"stage\":\"%s\",\"usb_result\":%d}\n", stage, rc);
            return false;
        }
        /* This printer also returns successful zero-length IN packets while idle. */
        if (state.found && is12_stream_complete(&stream) && !count && now_ms()-last_data >= 100) break;
        if (!rc && !count) usleep(10000);
    }
    if (!state.found || !is12_stream_complete(&stream)) {
        printf("{\"event\":\"no_complete_reply\",\"stage\":\"%s\",\"received\":%zu}\n", stage, received);
        return false;
    }
    printf("{\"event\":\"expected_reply\",\"stage\":\"%s\",\"matched\":true}\n", stage);
    fflush(stdout);
    return true;
}

static int decode(const char *filename) {
    FILE *input = fopen(filename, "rb");
    if (!input) { perror("Open USB IN capture"); return 1; }
    is12_stream stream;
    is12_stream_init(&stream);
    reply_context state = {.stage="offline-capture"};
    uint8_t buffer[4096];
    size_t count;
    bool success = true;
    while ((count=fread(buffer, 1, sizeof(buffer), input))) {
        if (!is12_stream_feed(&stream, buffer, count, log_reply, &state)) { success=false; break; }
    }
    success = success && !ferror(input) && is12_stream_complete(&stream) && state.records > 0;
    fclose(input);
    if (!success) fputs("Capture is empty, malformed or truncated.\n", stderr);
    return success ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc>=4 && !strcmp(argv[1],"image")) {
        unsigned dpi=90; bool rotated=false, dpi_seen=false, gray=false, mode_seen=false, lineart=false, bw=false;
        for (int i=4;i<argc;i++) {
            if (!strcmp(argv[i],"--rotate180") && !rotated) rotated=true;
            else if (!strcmp(argv[i],"--dpi") && !dpi_seen && i+1<argc) {
                dpi=parse_dpi(argv[++i]); dpi_seen=true;
                if (!dpi) { fputs("Supported dpi: 90, 180, 360.\n",stderr); return 2; }
            } else if (!strcmp(argv[i],"--mode") && !mode_seen && i+1<argc) {
                const char *mode=argv[++i]; mode_seen=true;
                bw=!strcmp(mode,"bw"); gray=bw || !strcmp(mode,"gray");
                lineart=!strcmp(mode,"lineart");
                if (!gray && !lineart && strcmp(mode,"color")) { fputs("Supported modes: color, gray, bw, lineart.\n",stderr); return 2; }
            } else { fputs("Invalid image option.\n",stderr); return 2; }
        }
        return is12_image_decode_file(argv[2],argv[3],rotated,dpi,gray,lineart,bw);
    }
    if (argc>=3 && !strcmp(argv[1],"scan")) {
        unsigned dpi=90; bool installed=false, reference_set=false, dpi_seen=false, gray=false, mode_seen=false, lineart=false, bw=false;
        bool live_preview=false;
        const char *reference=NULL,*directory=NULL;
        for (int i=2;i<argc;i++) {
            if (!strcmp(argv[i],"--scanner-installed") && !installed) installed=true;
            else if (!strcmp(argv[i],"--live-preview") && !live_preview) live_preview=true;
            else if (!strcmp(argv[i],"--uncalibrated") && !reference_set) reference_set=true;
            else if (!strcmp(argv[i],"--calibration") && !reference_set && i+1<argc) {
                reference=argv[++i]; reference_set=true;
            } else if (!strcmp(argv[i],"--dpi") && !dpi_seen && i+1<argc) {
                dpi=parse_dpi(argv[++i]); dpi_seen=true;
                if (!dpi) { fputs("Supported dpi: 90, 180, 360.\n",stderr); return 2; }
            } else if (!strcmp(argv[i],"--mode") && !mode_seen && i+1<argc) {
                const char *mode=argv[++i]; mode_seen=true;
                bw=!strcmp(mode,"bw"); gray=bw || !strcmp(mode,"gray");
                lineart=!strcmp(mode,"lineart");
                if (!gray && !lineart && strcmp(mode,"color")) { fputs("Supported modes: color, gray, bw, lineart.\n",stderr); return 2; }
            } else if (argv[i][0]!='-' && !directory) directory=argv[i];
            else { fputs("Invalid scan option.\n",stderr); return 2; }
        }
        if (!installed || !reference_set || !directory) {
            fputs("Scan requires --scanner-installed, --calibration FILE or --uncalibrated, and a new output directory.\n",stderr);
            return 2;
        }
        return is12_scan_main(directory,false,reference,dpi,gray,lineart,bw,live_preview);
    }
    if (argc == 5 && !strcmp(argv[1], "calibrate") && !strcmp(argv[2], "--scanner-installed") &&
        !strcmp(argv[3], "--plain-paper-reference")) return is12_scan_main(argv[4],true,NULL,90,false,false,false,false);
    if (argc == 3 && !strcmp(argv[1], "decode")) return decode(argv[2]);
    const uint8_t enter[] = {0x1b, '[', 'K', 2, 0, 0, 0x0d};
    bool plan = argc == 2 && !strcmp(argv[1], "plan");
    bool hardware = argc >= 3 && !strcmp(argv[1], "status") && !strcmp(argv[2], "--scanner-installed");
    bool enter_mode = false;
    const char *reference_path=NULL;
    if (hardware) for (int i=3;i<argc;i++) {
        if (!strcmp(argv[i],"--enter-scanner-mode") && !enter_mode) enter_mode=true;
        else if (!strcmp(argv[i],"--reference") && !reference_path && i+1<argc) reference_path=argv[++i];
        else { hardware=false; break; }
    }
    if (!plan && !hardware) {
        fprintf(stderr, "Usage: %s plan\n       %s decode USB-IN-CAPTURE\n       %s status --scanner-installed [--enter-scanner-mode] [--reference FILE]\n"
                "       %s scan --scanner-installed --uncalibrated [--dpi 90|180|360] [--mode color|gray|bw|lineart] [--live-preview] NEW-OUTPUT-DIRECTORY\n"
                "       %s image RECORDS OUTPUT.png [--rotate180] [--dpi 90|180|360] [--mode color|gray|bw|lineart]\n"
                "       %s calibrate --scanner-installed --plain-paper-reference NEW-OUTPUT-DIRECTORY\n"
                "       %s scan --scanner-installed --calibration REFERENCE.bin [--dpi 90|180|360] [--mode color|gray|bw|lineart] [--live-preview] NEW-OUTPUT-DIRECTORY\n"
                "Stop the print service and pause its queue before hardware use. Scan is an experimental single-page capture.\n", argv[0], argv[0], argv[0], argv[0], argv[0], argv[0], argv[0]);
        return 2;
    }
    if (plan) {
        printf("Optional scanner mode entry: "); hex(enter, sizeof(enter)); putchar('\n');
        for (uint8_t i=0; i<5; i++) {
            uint8_t request[7]; is12_information_request(i, request);
            printf("Information selector %u: ", i); hex(request, sizeof(request)); putchar('\n');
        }
        return 0;
    }
    bjc_usb usb;
    diagnostic_transport_ok=true;
    int rc = bjc_usb_open(&usb);
    if (!rc) rc = bjc_usb_claim(&usb);
    uint8_t identity[2048]; char id[2048];
    int count = rc < 0 ? rc : bjc_usb_identity(&usb, identity, sizeof(identity));
    if (count < 0 || !bjc_device_id(identity, (size_t)count, id, sizeof(id)) ||
        !strstr(id, "MFG:Canon;") || !strstr(id, "MDL:BJC-85;")) {
        fprintf(stderr, "Could not verify and claim the Canon BJC-85. Nothing sent.\n");
        puts("{\"event\":\"readiness\",\"kind\":\"transportError\",\"transport_ok\":false,\"replies_ok\":false,\"head_matches\":false,\"ready\":false}");
        printf("{\"event\":\"operation_outcome\",\"outcome\":\"%s\"}\n",usb.recovery_blocked?"recoveryRequired":"preflightFailedSafe");
        bjc_usb_close(&usb); return 1;
    }
    puts("{\"event\":\"start\",\"cartridge\":\"IS-12 asserted by operator\",\"native_arch\":\"arm64\"}");
    uint8_t carrier[12] = {0}, information[9] = {0}, status[3] = {0};
    uint8_t temperature[1] = {0}, extended[18] = {0};
    bool success = true;
    if (enter_mode) {
        success = send_request(&usb, "scanner-mode", enter, sizeof(enter));
        if (success) { usleep(400000); success = receive_reply(&usb, "scanner-mode", 's', 3, 0, status); }
    }
    const char *stages[] = {"carrier", "information", "status", "temperature", "extended-information"};
    const uint8_t tokens[] = {'c', 'i', 's', 't', 'e'};
    uint8_t *outputs[] = {carrier, information, status, temperature, extended};
    const size_t sizes[] = {sizeof(carrier), sizeof(information), sizeof(status), sizeof(temperature), sizeof(extended)};
    for (uint8_t i=0; success && i<5; i++) {
        uint8_t request[7]; is12_information_request(i, request);
        success = send_request(&usb, stages[i], request, sizeof(request));
        /* Canon's extended-information postprocessor handles 6- or 18-byte payloads. */
        if (success) success = receive_reply(&usb, stages[i], tokens[i], sizes[i], i == 4 ? 6 : 0, outputs[i]);
    }
    if (success) {
        bool matches = is12_bjc85_head_matches(carrier, sizeof(carrier), information, sizeof(information));
        printf("{\"event\":\"head_check\",\"matches_canon_bjc85_is12_checks\":%s,\"calibration_verified\":false,\"scan_verified\":false}\n", matches ? "true" : "false");
        printf("{\"event\":\"status_summary\",\"warming_up\":%s,\"temperature_raw\":%u}\n",
               status[1] & 0x08 ? "true" : "false", temperature[0]);
    }
    is12_status_result readiness=is12_status_evaluate(diagnostic_transport_ok,success,carrier,sizeof(carrier),information,sizeof(information),status);
    bool reference_valid=false;
    uint8_t reference_temperature=0;
    if (reference_path && readiness.ready) {
        char serial[32]={0};
        uint8_t measurement[IS12_MEASUREMENT_SIZE], correction[IS12_CORRECTION_SIZE];
        int size=libusb_get_string_descriptor_ascii(usb.handle,usb.descriptor.iSerialNumber,(uint8_t *)serial,sizeof(serial)-1);
        reference_valid=size>0 && size<32 &&
            is12_reference_load(reference_path,measurement,&reference_temperature,serial,carrier) &&
            is12_correction(measurement,reference_temperature,temperature[0],90,correction);
        // This validates existing data only; no T download or paper motion.
    }
    if (success && bjc_usb_finish_safe(&usb)) { success=false; readiness.ready=false; readiness.kind=IS12_STATUS_TRANSPORT_ERROR; }
    printf("{\"event\":\"readiness\",\"schema_version\":1,\"kind\":\"%s\",\"transport_ok\":%s,\"replies_ok\":%s,\"head_matches\":%s,\"ready\":%s,\"temperature_raw\":%u,\"reference_valid\":%s,\"reference_temperature_raw\":%u,\"calibration_verified\":false}\n",
        is12_status_name(readiness.kind),readiness.transport_ok?"true":"false",readiness.replies_ok?"true":"false",
        readiness.head_matches?"true":"false",readiness.ready?"true":"false",temperature[0],
        reference_path?(reference_valid?"true":"false"):"null",reference_temperature);
    printf("{\"event\":\"operation_outcome\",\"outcome\":\"%s\"}\n",success?(readiness.ready?"completedSafe":"preflightFailedSafe"):"recoveryRequired");
    bjc_usb_close(&usb);
    if (!success) fprintf(stderr, "Diagnostic stopped; retain the byte log. No automatic reset or retransmission was performed.\n");
    return readiness.ready ? 0 : (int)readiness.kind;
}
