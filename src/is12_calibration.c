#include "is12_calibration.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <zlib.h>

static uint16_t be16(const uint8_t *p) { return (uint16_t)((unsigned)p[0]*256+p[1]); }
static uint16_t le16(const uint8_t *p) { return (uint16_t)((unsigned)p[1]*256+p[0]); }
static void set_be16(uint8_t *p,uint16_t v) { p[0]=(uint8_t)(v>>8); p[1]=(uint8_t)v; }
static void set_le16(uint8_t *p,uint16_t v) { p[1]=(uint8_t)(v>>8); p[0]=(uint8_t)v; }

/* Match the original x86 signed 32-bit multiplication without C overflow UB. */
static int64_t signed32(uint32_t v) { return v<=INT32_MAX?(int64_t)v:(int64_t)v-4294967296LL; }

bool is12_correction(const uint8_t measurement[IS12_MEASUREMENT_SIZE],
                    uint8_t reference_temperature,uint8_t current_temperature,
                    unsigned dpi,uint8_t parameters[IS12_CORRECTION_SIZE]) {
    if (!measurement || !parameters || (dpi!=90 && dpi!=180 && dpi!=360)) return false;
    int delta=(int)current_temperature-reference_temperature;
    /* Bjshidrv!10009478 selects cached measurements within +/-10 raw units. */
    if (delta < -10 || delta > 10) return false;
    uint8_t corrected[12336]; memcpy(corrected,measurement+1,sizeof(corrected));
    for (unsigned group=0;group<6;group++) {
        for (unsigned channel=1;channel<=2;channel++) {
            uint8_t *base=corrected+group*2056+channel*514;
            /* 10009d5e: one LE field per channel, before caching. */
            uint16_t old=le16(base+256);
            uint32_t factor=channel==1?50000:20000;
            int64_t adjustment=signed32((uint32_t)(old+64)*(0U-factor))/998400;
            set_le16(base+256,(uint16_t)((uint16_t)(old+adjustment)&0xff00));
            /* 1000a28f -> 1000a3a9: temperature correction of 128 BE words. */
            uint32_t rate=channel==1?50:20;
            for (unsigned byte=0;byte<256;byte+=2) {
                uint16_t value=be16(base+byte);
                int64_t change=signed32((uint32_t)delta*value*rate)/10000;
                set_be16(base+byte,(uint16_t)(value-change));
            }
        }
    }
    unsigned block=dpi==360?0:dpi==180?1:2;
    parameters[0]=1; memcpy(parameters+1,corrected+block*2056,2056);
    /* BjsInfo!biGetCarrierIdTable BJC-85 row 10009f62; 1000a9a5(1).
     * Four 514-byte channels, scaling the initial 128 BE words in each. */
    const unsigned percentages[]={82,81,82,82};
    for (unsigned channel=0;channel<4;channel++) {
        uint8_t *base=parameters+1+channel*514;
        for (unsigned byte=0;byte<256;byte+=2)
            set_be16(base+byte,(uint16_t)((unsigned)be16(base+byte)*percentages[channel]/100));
    }
    return true;
}

static uint32_t read32(const uint8_t *p) {
    return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;
}
static void write32(uint8_t *p,uint32_t v) { for (unsigned i=0;i<4;i++) p[i]=(uint8_t)(v>>(8*i)); }

bool is12_reference_save(const char *filename,const uint8_t *measurement,uint8_t temperature,
                         const char *serial,const uint8_t carrier[12]) {
    if (!filename || !measurement || !serial || !serial[0] || strlen(serial)>31 || !carrier) return false;
    uint8_t header[64]={0}; memcpy(header,"IS12REF1",8);
    header[8]=1; /* Experimental plain-paper reference. */
    header[9]=temperature;
    write32(header+12,(uint32_t)crc32(0,measurement,IS12_MEASUREMENT_SIZE));
    memcpy(header+16,serial,strlen(serial)); memcpy(header+48,carrier,12);
    write32(header+60,IS12_MEASUREMENT_SIZE);
    FILE *out=fopen(filename,"wbx"); if (!out) return false;
    bool ok=fwrite(header,1,sizeof(header),out)==sizeof(header) &&
            fwrite(measurement,1,IS12_MEASUREMENT_SIZE,out)==IS12_MEASUREMENT_SIZE;
    if (fflush(out) || fsync(fileno(out))) ok=false;
    if (fclose(out)) ok=false;
    return ok;
}

bool is12_reference_load(const char *filename,uint8_t *measurement,uint8_t *temperature,
                         const char *serial,const uint8_t carrier[12]) {
    if (!filename || !measurement || !temperature || !serial || !serial[0] || strlen(serial)>31 || !carrier) return false;
    FILE *in=fopen(filename,"rb"); if (!in) return false;
    uint8_t header[64]; char serial_field[32]={0}; memcpy(serial_field,serial,strlen(serial));
    bool ok=fread(header,1,sizeof(header),in)==sizeof(header) &&
            fread(measurement,1,IS12_MEASUREMENT_SIZE,in)==IS12_MEASUREMENT_SIZE &&
            fgetc(in)==EOF && !ferror(in);
    fclose(in);
    if (!ok || memcmp(header,"IS12REF1",8) || header[8]!=1 || header[10] || header[11] ||
        memcmp(header+16,serial_field,32) || (header[48]&0xe0)!=(carrier[0]&0xe0) ||
        header[59]!=carrier[11] ||
        read32(header+60)!=IS12_MEASUREMENT_SIZE ||
        read32(header+12)!=(uint32_t)crc32(0,measurement,IS12_MEASUREMENT_SIZE)) return false;
    *temperature=header[9];
    return true;
}
