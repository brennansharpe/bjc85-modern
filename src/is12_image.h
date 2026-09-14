#ifndef IS12_IMAGE_H
#define IS12_IMAGE_H
#include "is12_protocol.h"

/* A full 360 dpi RGB page is about 34 MiB before framing. */
#define IS12_CAPTURE_LIMIT (64U * 1024 * 1024)

typedef struct {
    unsigned dpi, width, height, active, band_rows, row_bytes;
    uint8_t *planes[3];
    size_t capacity, committed[3], pending[3], bands, padding, band_end;
    bool configured, has_channel, ended, failed, grayscale, lineart;
} is12_image;

bool is12_image_init(is12_image *image, unsigned dpi);
void is12_image_destroy(is12_image *image);
bool is12_image_record(is12_image *image, const is12_reply *reply);
bool is12_image_complete(const is12_image *image);
/* Caller frees the returned device RGB pixels, with no host tone adjustment. Whole final bands are
 * clipped to the requested area, as Canon's biReadImagePreCalc does. */
uint8_t *is12_image_rgb(const is12_image *image, bool rotate180);
bool is12_image_png(const is12_image *image, const char *filename, bool rotate180, bool blackwhite);
int is12_image_decode_file(const char *input, const char *output, bool rotate180, unsigned dpi, bool grayscale, bool lineart, bool blackwhite);
#endif
