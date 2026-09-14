#include "is12_calibration.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static unsigned be16(const uint8_t *p) { return (unsigned)p[0]*256+p[1]; }
static void read_fixture(const char *filename,uint8_t *data,size_t size) {
    FILE *file=fopen(filename,"rb"); assert(file);
    assert(fread(data,1,size,file)==size && fgetc(file)==EOF && !ferror(file));
    assert(!fclose(file));
}

int main(int argc,char **argv) {
    uint8_t measurement[IS12_MEASUREMENT_SIZE]={0},out[IS12_CORRECTION_SIZE];
    for (unsigned c=0;c<4;c++) {
        uint8_t *channel=measurement+1+4112+c*514;
        for (unsigned b=0;b<256;b+=2) { channel[b]=0x10; channel[b+1]=0; }
        channel[256]=0; channel[257]=0x40;
    }
    assert(is12_correction(measurement,52,52,90,out));
    assert(out[0]==1 && be16(out+1)==3358 && be16(out+1+514)==3317);
    assert(out[1+514+256]==0 && out[1+514+257]==0x3c);
    assert(out[1+1028+256]==0 && out[1+1028+257]==0x3e);
    assert(is12_correction(measurement,52,53,90,out));
    assert(be16(out+1+514)==3301 && be16(out+1+1028)==3352);
    assert(!is12_correction(measurement,52,63,90,out));
    assert(!is12_correction(measurement,52,41,90,out));
    assert(!is12_correction(measurement,52,52,200,out));
    assert(is12_correction(measurement,52,52,180,out) && be16(out+1)==0);
    char directory[]="/tmp/is12-reference-test-XXXXXX";
    assert(mkdtemp(directory));
    char filename[256]; snprintf(filename,sizeof(filename),"%s/reference.bin",directory);
    const uint8_t carrier[]={0xb0,1,0xe,0x80,1,0,0,0xb,0x40,0,0x10,0xe};
    assert(is12_reference_save(filename,measurement,52,"test-device",carrier));
    assert(!is12_reference_save(filename,measurement,52,"test-device",carrier));
    uint8_t decoded[IS12_MEASUREMENT_SIZE],temperature=0;
    assert(is12_reference_load(filename,decoded,&temperature,"test-device",carrier));
    assert(temperature==52 && !memcmp(decoded,measurement,sizeof(measurement)));
    uint8_t changed_mode[12]; memcpy(changed_mode,carrier,12);
    changed_mode[1]=0x88; changed_mode[2]=0; changed_mode[3]=0x80; changed_mode[4]=1;
    changed_mode[10]=0x30; /* Measurement updates this field; it is not head identity. */
    assert(is12_reference_load(filename,decoded,&temperature,"test-device",changed_mode));
    changed_mode[11]=0x4e;
    assert(!is12_reference_load(filename,decoded,&temperature,"test-device",changed_mode));
    assert(!is12_reference_load(filename,decoded,&temperature,"another-device",carrier));
    FILE *file=fopen(filename,"r+b"); assert(file);
    assert(!fseek(file,65,SEEK_SET) && fputc(7,file)!=EOF && !fclose(file));
    assert(!is12_reference_load(filename,decoded,&temperature,"test-device",carrier));
    unlink(filename); rmdir(directory);
    if (argc==4) {
        read_fixture(argv[1],measurement,sizeof(measurement));
        uint8_t expected[IS12_CORRECTION_SIZE];
        read_fixture(argv[2],expected,sizeof(expected));
        assert(is12_correction(measurement,53,55,90,out));
        assert(!memcmp(out,expected,sizeof(out)));
        read_fixture(argv[3],expected,sizeof(expected));
        assert(is12_correction(measurement,53,56,180,out));
        assert(!memcmp(out,expected,sizeof(out)));
    } else assert(argc==1);
    return 0;
}
