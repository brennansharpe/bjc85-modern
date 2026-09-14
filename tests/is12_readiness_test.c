#include "fake_is12_usb.h"
#include <assert.h>
#include <stdlib.h>
#define main is12_cli_entry
#include "../src/is12_cli.c"
#undef main
static void reference_case(const char *path,bool valid) {
    char *args[]={"bjc85-is12","status","--scanner-installed","--reference",(char *)path,NULL};
    FILE *capture=tmpfile(); assert(capture);
    fflush(stdout); int saved=dup(STDOUT_FILENO); assert(saved>=0 && dup2(fileno(capture),STDOUT_FILENO)>=0);
    fake_usb_reset(); assert(is12_cli_entry(5,args)==0);
    fflush(stdout); assert(dup2(saved,STDOUT_FILENO)>=0); close(saved);
    rewind(capture); char text[16384]={0}; assert(fread(text,1,sizeof(text)-1,capture)>0); fclose(capture);
    assert(strstr(text,valid ? "\"reference_valid\":true" : "\"reference_valid\":false"));
    assert(!fake_usb_writes('T') && !fake_usb_writes('L') && !fake_usb_writes('B'));
}
int main(void) {
    char *args[]={"bjc85-is12","status","--scanner-installed",NULL};
    fake_usb_reset(); fake_usb_head(false);
    assert(is12_cli_entry(3,args)!=0);
    assert(fake_usb_writes('B')==0 && fake_usb_writes('L')==0);
    fake_usb_reset(); fake_usb_warming(true);
    assert(is12_cli_entry(3,args)!=0);
    fake_usb_reset();
    assert(is12_cli_entry(3,args)==0);
    char directory[]="/tmp/is12-reference-status-XXXXXX"; assert(mkdtemp(directory));
    char path[512]; snprintf(path,sizeof(path),"%s/reference.bin",directory);
    uint8_t measurement[IS12_MEASUREMENT_SIZE]={0};
    const uint8_t carrier[]={0xb0,1,0x0e,0x80,1,0,0,0x0b,0x40,0,0x10,0x0e};
    reference_case(path,false);
    assert(is12_reference_save(path,measurement,52,"FAKE01",carrier)); reference_case(path,true); assert(!unlink(path));
    assert(is12_reference_save(path,measurement,65,"FAKE01",carrier)); reference_case(path,false); assert(!unlink(path));
    assert(is12_reference_save(path,measurement,52,"OTHER",carrier)); reference_case(path,false); assert(!unlink(path));
    char blocked[512]; snprintf(blocked,sizeof(blocked),"%s/blocked",directory);
    fake_usb_reset(); fake_usb_recovery(true);
    assert(is12_scan_main(blocked,false,NULL,90,false,false,false,false)==7);
    assert(!fake_usb_writes('R') && !fake_usb_writes('L') && !fake_usb_writes('B'));
    for (size_t i=0;i<3;i++) {
        char file[1024]; const char *names[]={"records.bin","usb-in.bin","outcome.json"};
        snprintf(file,sizeof(file),"%s/%s",blocked,names[i]); assert(!unlink(file));
    }
    assert(!rmdir(blocked));
    assert(!rmdir(directory));
    puts("Readiness rejects wrong heads and warming replies without paper motion.");
    return 0;
}
