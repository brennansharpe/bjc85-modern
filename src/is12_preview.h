#ifndef IS12_PREVIEW_H
#define IS12_PREVIEW_H
#include "is12_image.h"
#include <stdio.h>

/* Optional, append-only 90 dpi RGB preview. Only complete bands are published.
 * JSON notifications follow fflush so readers never see announced partial rows.
 * Failure disables the preview without affecting acquisition or final images. */
typedef struct {
    FILE *file;
    unsigned rows;
    bool blackwhite;
} is12_preview;
bool is12_preview_open(is12_preview *preview, const char *directory, bool blackwhite);
void is12_preview_update(is12_preview *preview, const is12_image *image);
void is12_preview_close(is12_preview *preview);
#endif
