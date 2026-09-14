#include "is12_image.h"
#include <stdlib.h>
#include <string.h>

bool is12_image_init(is12_image *image, unsigned dpi) {
    if (!image) return false;
    memset(image,0,sizeof(*image));
    if (dpi != 90 && dpi != 180 && dpi != 360) return false;
    image->dpi=dpi;
    return true;
}

void is12_image_destroy(is12_image *image) {
    if (!image) return;
    for (unsigned c=0;c<3;c++) free(image->planes[c]);
    memset(image,0,sizeof(*image));
}

static unsigned be16(const uint8_t *data) { return (unsigned)data[0]*256+data[1]; }

static size_t image_limit(const is12_image *image) {
    return (size_t)image->row_bytes*(image->height+(image->band_rows?image->band_rows:512)-1);
}

bool is12_image_record(is12_image *image,const is12_reply *reply) {
    if (!image || !reply || image->failed || (!reply->payload && reply->length)) return false;
    if (reply->family == 's') {
        if (reply->token != 'C') return true;
        if (reply->length != 8 || image->configured || !image->dpi) goto fail;
        unsigned divisor=360/image->dpi;
        unsigned width=be16(reply->payload+4), height=be16(reply->payload+6);
        if (width%divisor || height%divisor) goto fail;
        image->width=width/divisor; image->height=height/divisor;
        if (!image->width || image->width>3000 || !image->height || image->height>5000) goto fail;
        if (image->lineart) image->grayscale=true;
        image->row_bytes=image->lineart?(image->width+7)/8:image->width;
        /* Band height depends on colour mode as well as resolution. Bound the
         * first band, then enforce the observed height for later bands. */
        image->capacity=image_limit(image);
        for (unsigned c=0;c<(image->grayscale?1U:3U);c++) {
            image->planes[c]=malloc(image->capacity);
            if (!image->planes[c]) goto fail;
        }
        image->configured=true;
        return true;
    }
    if (!image->configured || image->ended) goto fail;
    if (reply->family == 'S') {
        int channel=image->grayscale?(reply->token=='K'?0:-1):
            reply->token=='R'?0:reply->token=='G'?1:reply->token=='B'?2:-1;
        if (channel>=0) {
            if (image->band_end>=image->height) goto fail;
            image->has_channel=true; image->active=(unsigned)channel;
            size_t used=image->committed[channel]+image->pending[channel];
            if (used>image_limit(image) || reply->length>image_limit(image)-used) goto fail;
            memcpy(image->planes[channel]+used,reply->payload,reply->length);
            image->pending[channel]+=reply->length;
            return true;
        }
        if ((reply->token!='P' && reply->token!='E') || reply->length) goto fail;
        for (unsigned c=0;c<3;c++) if (image->pending[c]) goto fail;
        if (reply->token=='P') {
            for (unsigned c=0;c<(image->grayscale?1U:3U);c++)
                if (image->committed[c]!=image->committed[0] || image->committed[c]%image->row_bytes) goto fail;
            size_t end=image->committed[0]/image->row_bytes, rows=end-image->band_end;
            if (!rows || rows>512 || (image->band_rows && rows>image->band_rows)) goto fail;
            if (!image->band_rows) image->band_rows=(unsigned)rows;
            image->band_end=end; image->bands++;
        }
        else image->ended=true;
        return true;
    }
    if (reply->family == 'e') {
        if (reply->length!=2 || !image->has_channel) goto fail;
        int advance=(int)be16(reply->payload);
        if (advance>=32768) advance-=65536;
        unsigned c=image->active;
        if (advance<=0) {
            if (image->pending[c]) goto fail;
            return true; /* Plane rewind; each channel has its own write cursor. */
        }
        size_t expected=(size_t)image->row_bytes*(unsigned)advance;
        if (image->pending[c]>expected || image->committed[c]>image_limit(image) ||
            expected>image_limit(image)-image->committed[c]) goto fail;
        size_t padding=expected-image->pending[c];
        memset(image->planes[c]+image->committed[c]+image->pending[c],0,padding);
        image->padding+=padding; image->committed[c]+=expected; image->pending[c]=0;
        return true;
    }
fail:
    image->failed=true;
    return false;
}

bool is12_image_complete(const is12_image *image) {
    if (!image || image->failed || !image->configured || !image->ended) return false;
    size_t required=(size_t)image->row_bytes*image->height;
    for (unsigned c=0;c<(image->grayscale?1U:3U);c++) {
        if (image->pending[c] || image->committed[c]<required || image->committed[c]>image_limit(image) ||
            image->committed[c]%image->row_bytes || image->committed[c]!=image->committed[0]) return false;
    }
    return true;
}

uint8_t *is12_image_rgb(const is12_image *image,bool rotate180) {
    if (!is12_image_complete(image)) return NULL;
    size_t pixels=(size_t)image->width*image->height;
    uint8_t *rgb=malloc(pixels*3);
    if (!rgb) return NULL;
    for (size_t p=0;p<pixels;p++) {
        size_t source=rotate180?pixels-1-p:p;
        if (image->lineart) {
            /* Original BJSDM!100098f0: DIB palette index 0 black, 1 white.
             * Packed DIB scan rows are MSB first; ignore the final byte's pad bits. */
            size_t x=source%image->width,y=source/image->width;
            uint8_t value=(image->planes[0][y*image->row_bytes+x/8] & (0x80>>(x%8)))?255:0;
            for (unsigned c=0;c<3;c++) rgb[p*3+c]=value;
        } else for (unsigned c=0;c<3;c++) rgb[p*3+c]=image->planes[image->grayscale?0:c][source];
    }
    return rgb;
}
