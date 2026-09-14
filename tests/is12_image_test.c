#include "is12_image.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static bool record(is12_image *image,uint8_t family,uint8_t token,const uint8_t *payload,size_t length) {
    const is12_reply reply={.kind='!',.family=family,.token=token,.payload=payload,.length=length};
    return is12_image_record(image,&reply);
}

static void fixture(is12_image *image,bool end,unsigned dpi) {
    assert(is12_image_init(image,dpi));
    const uint8_t extent=(uint8_t)(2*360/dpi);
    const uint8_t area[]={0,0,0,43,0,extent,0,extent};
    const uint8_t forward[]={0,1},rewind[]={255,254};
    assert(record(image,'s','C',area,8));
    for (unsigned c=0;c<3;c++) {
        for (unsigned y=0;y<2;y++) {
            uint8_t pixels[]={(uint8_t)(c*4+y*2+1),(uint8_t)(c*4+y*2+2)};
            assert(record(image,'S',"RGB"[c],pixels,2));
            assert(record(image,'e',0,forward,2));
        }
        if (c<2) assert(record(image,'e',0,rewind,2));
    }
    assert(record(image,'S','P',NULL,0));
    if (end) assert(record(image,'S','E',NULL,0));
}

int main(void) {
    is12_image image;
    const unsigned resolutions[]={90,180,360};
    for (unsigned r=0;r<3;r++) {
    fixture(&image,true,resolutions[r]);
    assert(image.width==2 && image.height==2 && image.dpi==resolutions[r]);
    assert(is12_image_complete(&image));
    const uint8_t expected[]={1,5,9,2,6,10,3,7,11,4,8,12};
    uint8_t *rgb=is12_image_rgb(&image,false);
    assert(rgb && !memcmp(rgb,expected,sizeof(expected))); free(rgb);
    rgb=is12_image_rgb(&image,true);
    const uint8_t rotated[]={4,8,12,3,7,11,2,6,10,1,5,9};
    assert(rgb && !memcmp(rgb,rotated,sizeof(rotated))); free(rgb);
    is12_image_destroy(&image);
    }
    assert(!is12_image_init(&image,200));
    fixture(&image,false,90);
    assert(!is12_image_complete(&image));
    assert(!is12_image_rgb(&image,false));
    is12_image_destroy(&image);
    assert(is12_image_init(&image,90));
    const uint8_t area[]={0,0,0,43,0,8,0,8};
    assert(record(&image,'s','C',area,8));
    const uint8_t value=7,forward[]={0,1},huge[]={127,255};
    assert(record(&image,'S','R',&value,1));
    assert(record(&image,'e',0,forward,2));
    assert(image.padding==1 && image.planes[0][0]==7 && image.planes[0][1]==0);
    assert(!record(&image,'e',0,huge,2));
    assert(image.failed && !is12_image_complete(&image));
    is12_image_destroy(&image);
    assert(is12_image_init(&image,90));
    const uint8_t oversized[]={0,0,0,0,255,255,255,255};
    assert(!record(&image,'s','C',oversized,8));
    is12_image_destroy(&image);
    /* Full 360 dpi sheets end with 16 extra rows if the physical band is 64.
     * Accept one bounded final band, preserving only requested pixels. */
    assert(is12_image_init(&image,360));
    const uint8_t final_area[]={0,0,0,0,0,1,0,48};
    assert(record(&image,'s','C',final_area,8));
    const uint8_t final_pixels[64]={0};
    const uint8_t final_advance[]={0,64};
    for (unsigned c=0;c<3;c++) {
        assert(record(&image,'S',"RGB"[c],final_pixels,sizeof(final_pixels)));
        assert(record(&image,'e',0,final_advance,2));
    }
    assert(record(&image,'S','E',NULL,0));
    assert(is12_image_complete(&image));
    assert(image.height==48 && image.committed[0]==64);
    is12_image_destroy(&image);
    assert(is12_image_init(&image,90)); image.grayscale=true;
    const uint8_t gray_area[]={0,0,0,43,0,8,0,4},gray_pixels[]={10,200};
    assert(record(&image,'s','C',gray_area,8));
    assert(record(&image,'S','K',gray_pixels,2));
    assert(record(&image,'e',0,forward,2));
    assert(record(&image,'S','E',NULL,0) && is12_image_complete(&image));
    uint8_t *gray_rgb=is12_image_rgb(&image,true);
    const uint8_t gray_expected[]={200,200,200,10,10,10};
    assert(gray_rgb && !memcmp(gray_rgb,gray_expected,sizeof(gray_expected)));
    free(gray_rgb); is12_image_destroy(&image);
    assert(is12_image_init(&image,90)); image.grayscale=true;
    assert(record(&image,'s','C',gray_area,8));
    assert(!record(&image,'S','R',gray_pixels,2));
    is12_image_destroy(&image);
    /* Grayscale's 32-row band exceeds colour's 16 at 90 dpi. */
    assert(is12_image_init(&image,90)); image.grayscale=true;
    const uint8_t gray_band_area[]={0,0,0,43,0,4,0,68},gray_band_pixels[32]={0},gray_band_advance[]={0,32};
    assert(record(&image,'s','C',gray_band_area,8));
    assert(record(&image,'S','K',gray_band_pixels,32));
    assert(record(&image,'e',0,gray_band_advance,2));
    assert(record(&image,'S','P',NULL,0));
    assert(record(&image,'S','E',NULL,0) && is12_image_complete(&image));
    assert(image.band_rows==32 && image.height==17 && image.committed[0]==32);
    is12_image_destroy(&image);
    assert(is12_image_init(&image,90)); image.lineart=true;
    const uint8_t bit_area[]={0,0,0,43,0,40,0,8};
    const uint8_t bit_row1[]={0x80,0x40}, bit_row2[]={0x55,0x80};
    assert(record(&image,'s','C',bit_area,8));
    assert(image.row_bytes==2 && image.grayscale);
    assert(record(&image,'S','K',bit_row1,2) && record(&image,'e',0,forward,2));
    assert(record(&image,'S','K',bit_row2,2) && record(&image,'e',0,forward,2));
    assert(record(&image,'S','P',NULL,0) && record(&image,'S','E',NULL,0));
    uint8_t *bits=is12_image_rgb(&image,false);
    const uint8_t expected_bits[]={1,0,0,0,0,0,0,0,0,1, 0,1,0,1,0,1,0,1,1,0};
    assert(bits);
    for (unsigned p=0;p<20;p++) for (unsigned c=0;c<3;c++) assert(bits[p*3+c]==expected_bits[p]*255);
    free(bits); is12_image_destroy(&image);
    return 0;
}
