/* Offline capture replay through the exact preview publisher used by USB scans. */
#include "is12_preview.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc,char **argv) {
    if (argc!=5) return 2;
    is12_image image;
    if (!is12_image_init(&image,(unsigned)atoi(argv[3]))) return 2;
    bool bw=!strcmp(argv[4],"bw");
    image.grayscale=bw || !strcmp(argv[4],"gray"); image.lineart=!strcmp(argv[4],"lineart");
    FILE *file=fopen(argv[1],"rb");
    is12_preview preview;
    if (!file || !is12_preview_open(&preview,argv[2],bw)) return 2;
    if (fseek(file,0,SEEK_END)) return 2;
    long size=ftell(file);
    if (size<=0 || (unsigned long)size>IS12_CAPTURE_LIMIT || fseek(file,0,SEEK_SET)) return 2;
    uint8_t *bytes=malloc((size_t)size);
    if (!bytes || fread(bytes,1,(size_t)size,file)!=(size_t)size) return 2;
    size_t offset=0; bool valid=true;
    while (offset<(size_t)size) {
        is12_reply reply;
        if (is12_parse_reply(bytes+offset,(size_t)size-offset,&reply)!=IS12_COMPLETE ||
            !is12_image_record(&image,&reply)) { valid=false; break; }
        offset+=reply.consumed;
        is12_preview_update(&preview,&image);
    }
    valid=valid && is12_image_complete(&image);
    is12_preview_close(&preview); is12_image_destroy(&image); fclose(file); free(bytes);
    return valid?0:1;
}
