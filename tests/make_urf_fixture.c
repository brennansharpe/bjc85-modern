/* Synthetic raster generator only: no printer, queue or CUPS service calls. */
#include <cups/raster.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv) {
    if (argc!=3) return 2;
    const int a4=strcmp(argv[2],"a4")==0, channels=a4?1:3;
    int fd=open(argv[1],O_WRONLY|O_CREAT|O_EXCL,0600);
    if(fd<0) return 1;
    cups_raster_t *r=cupsRasterOpen(fd,CUPS_RASTER_WRITE_APPLE);
    if(!r) { close(fd); return 1; }
    cups_page_header2_t h={0};
    h.HWResolution[0]=h.HWResolution[1]=360;
    h.cupsWidth=a4?2976:3060; h.cupsHeight=a4?4209:3960;
    h.cupsPageSize[0]=a4?595.2756f:612; h.cupsPageSize[1]=a4?841.8898f:792;
    h.PageSize[0]=(unsigned)h.cupsPageSize[0]; h.PageSize[1]=(unsigned)h.cupsPageSize[1];
    h.cupsBitsPerColor=8; h.cupsBitsPerPixel=8*(unsigned)channels;
    h.cupsBytesPerLine=h.cupsWidth*(unsigned)channels; h.cupsNumColors=(unsigned)channels;
    h.cupsColorSpace=a4?CUPS_CSPACE_SW:CUPS_CSPACE_SRGB; h.cupsColorOrder=CUPS_ORDER_CHUNKED;
    unsigned char *row=malloc(h.cupsBytesPerLine); if(!row) return 1;
    for(int page=0;page<(a4?4:1);page++) {
        if(!cupsRasterWriteHeader2(r,&h)) return 1;
        for(unsigned y=0;y<h.cupsHeight;y++) {
            memset(row, y%360<8 ? 80 : 255,h.cupsBytesPerLine);
            if(cupsRasterWritePixels(r,row,h.cupsBytesPerLine)!=h.cupsBytesPerLine) return 1;
        }
    }
    free(row); cupsRasterClose(r); close(fd); return 0;
}
