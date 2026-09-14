#include "is12_preview.h"
#include <stdlib.h>

bool is12_preview_open(is12_preview *preview,const char *directory,bool blackwhite) {
    *preview=(is12_preview){.blackwhite=blackwhite};
    char path[4096];
    if (snprintf(path,sizeof(path),"%s/live-preview.rgb",directory)>=(int)sizeof(path)) return false;
    preview->file=fopen(path,"wbx");
    return preview->file!=NULL;
}

void is12_preview_close(is12_preview *preview) {
    if (preview->file) fclose(preview->file);
    preview->file=NULL;
}

void is12_preview_update(is12_preview *preview,const is12_image *image) {
    if (!preview->file || !image->configured || image->failed) return;
    unsigned step=image->dpi/90;
    if (!step || (preview->blackwhite && !image->grayscale)) return;
    size_t available=is12_image_complete(image)?image->height:image->band_end;
    if (available>image->height) available=image->height;
    unsigned width=(image->width+step-1)/step,height=(image->height+step-1)/step;
    unsigned rows=((unsigned)available+step-1)/step;
    if (rows<=preview->rows) return;
    /* band_end changes only after every colour plane has been committed. */
    size_t size=(size_t)(rows-preview->rows)*width*3;
    uint8_t *pixels=malloc(size);
    if (!pixels) goto failed;
    for (unsigned y=preview->rows;y<rows;y++) for (unsigned x=0;x<width;x++) {
        size_t target=((size_t)(y-preview->rows)*width+x)*3;
        size_t source=(size_t)y*step*image->width+x*step;
        for (unsigned c=0;c<3;c++) {
            uint8_t value;
            if (image->lineart) {
                size_t offset=(size_t)y*step*image->row_bytes+x*step/8;
                value=(image->planes[0][offset] & (0x80>>(x*step%8)))?255:0;
            } else value=image->planes[image->grayscale?0:c][source];
            pixels[target+c]=preview->blackwhite?(value>=128?255:0):value;
        }
    }
    bool success=fwrite(pixels,1,size,preview->file)==size && !fflush(preview->file);
    free(pixels);
    if (!success) goto failed;
    preview->rows=rows;
    printf("{\"event\":\"scan_preview\",\"width\":%u,\"height\":%u,\"rows\":%u}\n",width,height,rows);
    fflush(stdout);
    return;
failed:
    is12_preview_close(preview);
    puts("{\"event\":\"scan_preview_unavailable\"}"); fflush(stdout);
}
