#include "is12_image.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

bool is12_image_png(const is12_image *image,const char *filename,bool rotate180,bool blackwhite) {
    if (blackwhite && (!image->grayscale || image->lineart)) return false;
    uint8_t *rgb=is12_image_rgb(image,rotate180);
    if (!rgb) return false;
    bool packed=image->lineart || blackwhite;
    unsigned bits=packed?1:8;
    unsigned pixel_bits=image->grayscale?bits:24;
    size_t stride=image->grayscale?(packed?(image->width+7)/8:image->width):image->width*3;
    if (image->grayscale) {
        uint8_t *gray=calloc(stride,image->height);
        if (!gray) { free(rgb); return false; }
        for (unsigned y=0;y<image->height;y++) for (unsigned x=0;x<image->width;x++) {
            uint8_t value=rgb[((size_t)y*image->width+x)*3];
            if (packed) { if (value >= (blackwhite?128:1)) gray[y*stride+x/8]|=(uint8_t)(0x80>>(x%8)); }
            else gray[y*stride+x]=value;
        }
        free(rgb); rgb=gray;
    }
    bool success=false;
    CGColorSpaceRef colour=image->grayscale?CGColorSpaceCreateDeviceGray():CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,rgb,stride*image->height,NULL);
    CGImageRef bitmap=NULL;
    CFMutableDataRef data=CFDataCreateMutable(NULL,0);
    CGImageDestinationRef destination=NULL;
    if (!colour || !provider || !data) goto done;
    bitmap=CGImageCreate(image->width,image->height,bits,pixel_bits,stride,colour,
                         kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
    if (!bitmap) goto done;
    destination=CGImageDestinationCreateWithData(data,CFSTR("public.png"),1,NULL);
    if (!destination) goto done;
    int dpi=(int)image->dpi;
    CFNumberRef resolution=CFNumberCreate(NULL,kCFNumberIntType,&dpi);
    const void *keys[]={kCGImagePropertyDPIWidth,kCGImagePropertyDPIHeight};
    const void *values[]={resolution,resolution};
    CFDictionaryRef properties=resolution?CFDictionaryCreate(NULL,keys,values,2,
        &kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks):NULL;
    CGImageDestinationAddImage(destination,bitmap,properties);
    if (properties) CFRelease(properties);
    if (resolution) CFRelease(resolution);
    if (!CGImageDestinationFinalize(destination)) goto done;
    FILE *output=fopen(filename,"wbx");
    if (!output) goto done;
    size_t size=(size_t)CFDataGetLength(data);
    success=fwrite(CFDataGetBytePtr(data),1,size,output)==size;
    if (fflush(output) || fsync(fileno(output))) success=false;
    if (fclose(output)) success=false;
done:
    if (destination) CFRelease(destination);
    if (data) CFRelease(data);
    if (bitmap) CGImageRelease(bitmap);
    if (provider) CGDataProviderRelease(provider);
    if (colour) CGColorSpaceRelease(colour);
    free(rgb);
    return success;
}

int is12_image_decode_file(const char *input,const char *output,bool rotate180,unsigned dpi,bool grayscale,bool lineart,bool blackwhite) {
    FILE *file=fopen(input,"rb");
    if (!file) { perror("Open image records"); return 1; }
    uint8_t *data=NULL;
    bool success=false;
    is12_image image;
    if (!is12_image_init(&image,dpi)) { fclose(file); return 2; }
    image.grayscale=grayscale;
    image.lineart=lineart;
    if (fseek(file,0,SEEK_END)) goto done;
    long length=ftell(file);
    if (length<=0 || (unsigned long)length>IS12_CAPTURE_LIMIT || fseek(file,0,SEEK_SET)) goto done;
    data=malloc((size_t)length);
    if (!data || fread(data,1,(size_t)length,file)!=(size_t)length) goto done;
    size_t position=0;
    while (position<(size_t)length) {
        is12_reply reply;
        if (is12_parse_reply(data+position,(size_t)length-position,&reply)!=IS12_COMPLETE ||
            !is12_image_record(&image,&reply)) goto done;
        position+=reply.consumed;
    }
    success=is12_image_complete(&image) && is12_image_png(&image,output,rotate180,blackwhite);
    printf("{\"event\":\"image_decode\",\"complete\":%s,\"width\":%u,\"height\":%u,\"dpi\":%u,\"mode\":\"%s\",\"device_correction\":\"not encoded in image records\",\"host_tone_adjustment\":%s,\"host_threshold\":%s,\"rotation_degrees\":%u}\n",
           success?"true":"false",image.width,image.height,image.dpi,blackwhite?"bw":lineart?"lineart":grayscale?"gray":"color",blackwhite?"true":"false",blackwhite?"128":"null",rotate180?180:0);
done:
    if (!success) fputs("No complete image written; retain the original capture.\n",stderr);
    is12_image_destroy(&image); free(data); fclose(file);
    return success?0:1;
}
