#include "is12_protocol.h"
#include "is12_image.h"
#include "is12_preview.h"
#include "is12_calibration.h"
#include "protocol.h"
#include "usb.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* Research acquisition. Commands traced from the original IS Scan 3.50 DLLs.
 * Calibration is deliberately omitted for an explicitly uncalibrated test.
 * Keep every received byte, including incomplete records, for offline analysis. */
typedef struct {
    bjc_usb usb;
    is12_stream stream;
    is12_image image;
    is12_preview preview;
    FILE *raw, *records;
    const char *stage;
    uint8_t match_family, match_token, match_kind, reply[32], status[3];
    size_t match_length, reply_length, received, images, record_count;
    bool matched, status_seen, end, device_error, io_error;
    bool calibration, measured;
    bool correction_applied, stopping;
    uint8_t measurement[IS12_MEASUREMENT_SIZE];
    uint64_t last_data;
} scan_session;

static volatile sig_atomic_t interrupted;
static void on_signal(int value) { (void)value; interrupted = 1; }
static uint64_t scan_now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}
static void print_hex(const uint8_t *data, size_t length) {
    putchar('"');
    for (size_t i=0; i<length; i++) printf("%s%02x", i ? " " : "", data[i]);
    putchar('"');
}

static bool scan_record(const is12_reply *r, void *context) {
    scan_session *s = context;
    s->record_count++;
    size_t body = r->length + (r->family == 'e' ? 0 : 1);
    uint8_t header[] = {0x1b, r->kind, r->family, (uint8_t)body, (uint8_t)(body >> 8), r->token};
    size_t header_size = r->family == 'e' ? 5 : 6;
    if (fwrite(header, 1, header_size, s->records) != header_size ||
        fwrite(r->payload, 1, r->length, s->records) != r->length) {
        s->io_error = true; return false;
    }
    printf("{\"event\":\"record\",\"stage\":\"%s\",\"kind\":%u,\"family\":%u,\"token\":%u,\"length\":%zu",
           s->stage, r->kind, r->family, r->token, r->length);
    if (r->length <= 32) { printf(",\"payload\":"); print_hex(r->payload, r->length); }
    puts("}"); fflush(stdout);
    if (r->family == 's' && r->token == 's' && r->length == 3) {
        memcpy(s->status, r->payload, 3); s->status_seen = true;
        /* Canon's load/start paths map these to LED, paper, jam, battery,
         * head-change/failure and cover faults. Warm-up bit 08 is not an error. */
        if ((s->status[0] & 0x44) || (s->status[1] & 0xd4) || (s->status[2] & 3))
            s->device_error = true;
    }
    if (r->family == s->match_family && r->token == s->match_token &&
        (!s->match_kind || r->kind == s->match_kind) && r->length == s->match_length &&
        r->length <= sizeof(s->reply)) {
        memcpy(s->reply, r->payload, r->length); s->reply_length = r->length; s->matched = true;
    }
    if (r->family == 'S') {
        if (r->token == 'E') s->end = true;
        if (strchr("RGBKrgbk", r->token) && r->token) s->images += r->length;
    }
    if (s->calibration) {
        if (r->family=='S' && r->token=='c') {
            if (r->length!=sizeof(s->measurement) || s->measured) return false;
            memcpy(s->measurement,r->payload,r->length); s->measured=true;
        }
    } else if (!s->stopping && !is12_image_record(&s->image,r)) {
        fprintf(stderr,"Image record rejected: family %c, token %c, length %zu; raw data retained.\n",
                r->family,r->token?r->token:'-',r->length);
        return false;
    }
    return true;
}

static bool scan_pump(scan_session *s) {
    uint8_t buffer[4096]; int count = 0;
    int rc = libusb_bulk_transfer(s->usb.handle, s->usb.bulk_in, buffer, sizeof(buffer), &count, 250);
    if (count < 0 || (size_t)count > sizeof(buffer)) return false;
    if (count) {
        s->last_data = scan_now(); s->received += (size_t)count;
        if (s->received > IS12_CAPTURE_LIMIT || fwrite(buffer, 1, (size_t)count, s->raw) != (size_t)count) {
            s->io_error = true; return false;
        }
        bool parsed=is12_stream_feed(&s->stream, buffer, (size_t)count, scan_record, s);
        if (fflush(s->raw) || fflush(s->records)) { s->io_error=true; return false; }
        if (!parsed) return false;
        if (!s->calibration && !s->stopping) is12_preview_update(&s->preview,&s->image);
    }
    if (rc < 0 && rc != LIBUSB_ERROR_TIMEOUT) {
        printf("{\"event\":\"usb_read_error\",\"result\":%d}\n", rc); return false;
    }
    if (!count && !rc) usleep(10000);
    return !s->io_error;
}

static bool scan_write(scan_session *s, uint8_t token, const uint8_t *parameters, size_t size) {
    uint8_t command[IS12_CORRECTION_SIZE+6];
    if (size > sizeof(command)-6 || (size && !parameters)) return false;
    command[0]=0x1b; command[1]='('; command[2]='s'; command[3]=(uint8_t)(size+1);
    command[4]=(uint8_t)((size+1)>>8); command[5]=token;
    if (size) memcpy(command+6, parameters, size);
    int accepted=0;
    int rc=libusb_bulk_transfer(s->usb.handle,s->usb.bulk_out,command,(int)size+6,&accepted,1000);
    printf("{\"event\":\"write\",\"stage\":\"%s\",\"requested\":%zu,\"accepted\":%d,\"usb_result\":%d,\"hex\":",
           s->stage,size+6,accepted,rc);
    print_hex(command,size+6); puts("}"); fflush(stdout);
    /* Never replay a paper-moving command after a partial or ambiguous write. */
    return rc == 0 && accepted == (int)size+6;
}

static bool scan_expect(scan_session *s,uint8_t family,uint8_t token,size_t size,unsigned timeout) {
    s->match_family=family; s->match_token=token; s->match_kind='!'; s->match_length=size; s->matched=false;
    uint64_t deadline=scan_now()+timeout;
    while (!interrupted && scan_now()<deadline) {
        if (!scan_pump(s) || s->device_error) return false;
        if (s->matched && is12_stream_complete(&s->stream)) return true;
    }
    printf("{\"event\":\"reply_timeout\",\"stage\":\"%s\"}\n",s->stage);
    return false;
}

static bool status_query(scan_session *s) {
    const uint8_t selector=2;
    return scan_write(s,'R',&selector,1) && scan_expect(s,'s','s',3,5000);
}

int is12_scan_main(const char *directory,bool calibration,const char *reference,unsigned dpi,bool grayscale,bool lineart,bool blackwhite,bool live_preview) {
    scan_session *s=calloc(1,sizeof(*s));
    if (!s) return 1;
    if (!is12_image_init(&s->image,dpi)) { free(s); return 2; }
    s->image.grayscale=grayscale;
    s->image.lineart=lineart;
    bool success=false, started=false, writable=true;
    s->calibration=calibration;
    uint8_t temperature=0;
    char serial[32]={0};
    char filename[4096];
    if (mkdir(directory,0700) != 0) { perror("Create new scan directory"); free(s); return 1; }
    if (snprintf(filename,sizeof(filename),"%s/usb-in.bin",directory) >= (int)sizeof(filename)) goto done;
    s->raw=fopen(filename,"wbx");
    if (snprintf(filename,sizeof(filename),"%s/records.bin",directory) >= (int)sizeof(filename)) goto done;
    s->records=fopen(filename,"wbx");
    if (!s->raw || !s->records) { perror("Create scan capture"); goto done; }
    if (live_preview && !calibration && !is12_preview_open(&s->preview,directory,blackwhite)) {
        puts("{\"event\":\"scan_preview_unavailable\"}"); fflush(stdout);
    }
    signal(SIGINT,on_signal); signal(SIGTERM,on_signal);
    is12_stream_init(&s->stream);
    int rc=bjc_usb_open(&s->usb);
    if (!rc) rc=bjc_usb_claim(&s->usb);
    uint8_t identity[2048]; char id[2048];
    int count=rc < 0 ? rc : bjc_usb_identity(&s->usb,identity,sizeof(identity));
    if (count<0 || !bjc_device_id(identity,(size_t)count,id,sizeof(id)) ||
        !strstr(id,"MFG:Canon;") || !strstr(id,"MDL:BJC-85;")) {
        fputs("Could not verify and claim BJC-85; no commands sent.\n",stderr); goto done;
    }
    int serial_size=libusb_get_string_descriptor_ascii(s->usb.handle,s->usb.descriptor.iSerialNumber,
                                                       (uint8_t *)serial,sizeof(serial)-1);
    if (serial_size<=0 || serial_size>31) goto done;
    printf("{\"event\":\"scan_start\",\"plain_paper_calibration\":%s,\"reference_requested\":%s,\"requested_dpi\":%u,\"colour\":\"%s\",\"output_threshold\":%s,\"page_limit\":1}\n",
           calibration?"true":"false",reference?"true":"false",dpi,lineart?"lineart":grayscale?"gray":"RGB",blackwhite?"128":"null");
    uint8_t carrier[12], information[9];
    s->stage="verify-carrier";
    const uint8_t head_query=0, info_query=1;
    if (!scan_write(s,'R',&head_query,1) || !scan_expect(s,'s','c',12,5000)) goto done;
    memcpy(carrier,s->reply,12);
    s->stage="verify-information";
    if (!scan_write(s,'R',&info_query,1) || !scan_expect(s,'s','i',9,5000)) goto done;
    memcpy(information,s->reply,9);
    if (!is12_bjc85_head_matches(carrier,12,information,9)) goto done;
    s->stage="initial-status";
    if (!status_query(s)) goto done;
    uint64_t warm_deadline=scan_now()+120000;
    while ((s->status[1]&8) && scan_now()<warm_deadline && !interrupted) {
        usleep(250000); if (!status_query(s)) goto done;
    }
    if (s->status[1]&8) goto done;
    if (calibration || reference) {
        const uint8_t selector=3;
        s->stage="reference-temperature";
        if (!scan_write(s,'R',&selector,1) || !scan_expect(s,'s','t',1,5000)) goto done;
        temperature=s->reply[0];
    }
    if (calibration) {
        s->stage="quiesce-before-reference";
        if (!scan_write(s,'Q',NULL,0) || !scan_expect(s,'s','s',3,5000)) goto done;
        uint64_t quiet_deadline=scan_now()+10000;
        while ((s->status[0]&0x10) && !interrupted && scan_now()<quiet_deadline) {
            usleep(200000); if (!status_query(s)) goto done;
        }
        if (s->status[0]&0x10) goto done;
    }
    /* BjsInfo!biSetScaninfo: colour, default edge/threshold, 360/dpi divisor.
     * Coordinates are BE u16 in 360dpi units. Y=43 is Canon's 3mm leading offset.
     * An 8 x 10.8 inch region fits Letter and covers the loaded native chart. */
    /* BjsInfo!biSetScaninfo maps colour to 88 and eight-bit gray to 08.
     * Bjshidrv!10001c36 returns uncompressed S/K bytes without inversion. */
    /* 01 selects one-bit line art. Keep D[2] compression bit 10 clear. */
    const uint8_t mode[]={0x10,lineart?0x01:grayscale?0x08:0x88,0x0c,0x78,(uint8_t)(360/dpi)};
    const uint8_t calibration_mode[]={0x10,0x88,0x00,0x80,0x01};
    const uint8_t area[]={0,0,0,43,0x0b,0x40,0x0f,0x30};
    s->stage="configure-mode";
    if (!scan_write(s,'D',calibration?calibration_mode:mode,sizeof(mode)) || !scan_expect(s,'s','s',3,5000)) goto done;
    if (!calibration) {
        s->stage="configure-area";
        if (!scan_write(s,'C',area,sizeof(area)) || !scan_expect(s,'s','C',8,5000)) goto done;
        printf("{\"event\":\"accepted_area_be\",\"hex\":"); print_hex(s->reply,8); puts("}");
    }
    if (reference) {
        uint8_t reference_temperature, parameters[IS12_CORRECTION_SIZE];
        if (!is12_reference_load(reference,s->measurement,&reference_temperature,serial,carrier) ||
            !is12_correction(s->measurement,reference_temperature,temperature,dpi,parameters)) {
            fputs("Reference failed identity, checksum or temperature validation.\n",stderr); goto done;
        }
        s->stage="download-reference-correction";
        usleep(100000);
        if (!scan_write(s,'T',parameters,sizeof(parameters))) goto done;
        usleep(100000);
        if (!scan_expect(s,'s','s',3,5000)) goto done;
        s->correction_applied=true;
    }
    s->stage="load-page";
    if (!status_query(s)) goto done;
    if (!(s->status[0]&0x10)) {
        started=true;
        if (!scan_write(s,'L',NULL,0)) { writable=false; goto cleanup; }
        uint64_t load_deadline=scan_now()+30000;
        while (!(s->status[0]&0x10) && !interrupted && scan_now()<load_deadline) {
            if (!scan_pump(s) || s->device_error) goto cleanup;
        }
        if (!(s->status[0]&0x10)) goto cleanup;
    }
    s->stage=calibration?"measure-reference":"acquire"; started=true;
    const uint8_t white_parameters[]={1,7,7};
    if (!scan_write(s,calibration?'W':'B',calibration?white_parameters:NULL,calibration?3:0)) {
        writable=false; goto cleanup;
    }
    s->last_data=scan_now();
    uint64_t scan_deadline=scan_now()+1800000, report_at=scan_now()+10000;
    while (!(calibration?s->measured:s->end) && !interrupted && scan_now()<scan_deadline &&
           scan_now()-s->last_data<((calibration || (s->status[1]&8))?180000U:60000U)) {
        if (!scan_pump(s) || s->device_error) goto cleanup;
        if (scan_now()>=report_at) {
            printf("{\"event\":\"scan_progress\",\"image_bytes\":%zu,\"usb_bytes\":%zu}\n",s->images,s->received);
            fflush(stdout); report_at=scan_now()+10000;
        }
    }
    success=(calibration?s->measured:(s->end && is12_image_complete(&s->image))) &&
            is12_stream_complete(&s->stream) && !s->device_error;
    if (success && calibration) {
        s->stage="reference-eject-status";
        uint64_t eject_deadline=scan_now()+10000;
        do {
            if (!status_query(s)) { success=false; break; }
            if (!(s->status[0]&0x10)) break;
            usleep(200000);
        } while (!interrupted && scan_now()<eject_deadline);
        if (s->status[0]&0x10) success=false;
    }
cleanup:
    /* Q is the original driver's stop/quiesce command, never a full USB reset.
     * A failed write leaves transport state unknown, so do not append commands. */
    if (started && writable && !success) {
        s->stopping=true; /* Drain Q replies even if cancellation leaves an incomplete image. */
        s->stage="stop-acquisition";
        if (scan_write(s,'Q',NULL,0)) {
            uint64_t stop_deadline=scan_now()+3000;
            while (scan_now()<stop_deadline) if (!scan_pump(s)) break;
        }
    }
done:
    if (s->raw && (fflush(s->raw) || fsync(fileno(s->raw)))) success=false;
    if (s->records && (fflush(s->records) || fsync(fileno(s->records)))) success=false;
    if (success && calibration) {
        if (snprintf(filename,sizeof(filename),"%s/reference.bin",directory)>=(int)sizeof(filename) ||
            !is12_reference_save(filename,s->measurement,temperature,serial,carrier)) success=false;
    }
    if (success && !calibration) {
        if (snprintf(filename,sizeof(filename),"%s/scan-raw.png",directory)>=(int)sizeof(filename) ||
            !is12_image_png(&s->image,filename,false,blackwhite)) success=false;
        if (snprintf(filename,sizeof(filename),"%s/scan-upright.png",directory)>=(int)sizeof(filename) ||
            !is12_image_png(&s->image,filename,true,blackwhite)) success=false;
    }
    printf("{\"event\":\"scan_result\",\"complete_stream\":%s,\"end_record\":%s,\"measurement_received\":%s,\"reference_applied\":%s,\"image_bytes\":%zu,\"usb_bytes\":%zu,\"device_error\":%s,\"canon_reference_validated\":false}\n",
           success?"true":"false",s->end?"true":"false",s->measured?"true":"false",s->correction_applied?"true":"false",s->images,s->received,s->device_error?"true":"false");
    bjc_usb_close(&s->usb);
    if (s->raw) fclose(s->raw);
    if (s->records) fclose(s->records);
    is12_preview_close(&s->preview);
    is12_image_destroy(&s->image);
    free(s);
    return success?0:1;
}
