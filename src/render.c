/* Native CoreGraphics rasterization and Gutenprint adapter. */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <gutenprint/gutenprint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct { unsigned char *pixels; int width, height; } raster;
typedef struct { FILE *file; int failed; size_t bytes; } output;

static void no_op(stp_image_t *image) { (void)image; }
static int image_width(stp_image_t *image) { return ((raster *)image->rep)->width; }
static int image_height(stp_image_t *image) { return ((raster *)image->rep)->height; }
static const char *app_name(stp_image_t *image) { (void)image; return "BJC85 Native ARM64"; }
static stp_image_status_t image_row(stp_image_t *image, unsigned char *data, size_t limit, int row) {
    raster *r = image->rep;
    if (row < 0 || row >= r->height || limit < (size_t)r->width * 3) return STP_IMAGE_STATUS_ABORT;
    const unsigned char *p = r->pixels + (size_t)row * r->width * 4;
    for (int x = 0; x < r->width; x++) memcpy(data + x * 3, p + x * 4, 3);
    return STP_IMAGE_STATUS_OK;
}
static void write_output(void *user, const char *data, size_t length) {
    output *out = user;
    if (out->failed) return;
    size_t written = fwrite(data, 1, length, out->file);
    out->bytes += written;
    if (written != length) out->failed = 1;
}
static void write_error(void *user, const char *data, size_t length) { (void)user; fwrite(data, 1, length, stderr); }

static CFURLRef file_url(const char *filename) {
    return CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)filename, (CFIndex)strlen(filename), false);
}
static void text_at(CGContextRef context, const char *text, double x, double y, double size) {
    CFStringRef string = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);
    const void *keys[] = { kCTFontAttributeName, kCTForegroundColorFromContextAttributeName };
    const void *values[] = { font, kCFBooleanTrue };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attr = CFAttributedStringCreate(NULL, string, attrs);
    CTLineRef line = CTLineCreateWithAttributedString(attr);
    CGContextSetTextPosition(context, x, y);
    CTLineDraw(line, context);
    CFRelease(line); CFRelease(attr); CFRelease(attrs); CFRelease(font); CFRelease(string);
}
static void test_page(CGContextRef context, double width, double height, int color) {
    /* Saturated blue uses the working colour channels for the test's labels.
       The black patch remains an independent control for the black ink path. */
    CGContextSetRGBFillColor(context, 0, 0, color ? 1 : 0, 1);
    text_at(context, "Canon BJC-85 / native ARM64", 24, height-40, 20);
    text_at(context, "BC-11e cartridge - plain paper - 360 dpi", 24, height-62, 11);
    text_at(context, color ? "COLOR TEST - C / M / Y / K" : "MONOCHROME TEST", 24, height-92, 12);
    text_at(context, "Top of page: text should be upright and readable.", 24, height-112, 10);
    const double inks[4][3] = {{0,1,1},{1,0,1},{1,1,0},{0,0,0}};
    const char *ink_names[] = {"Cyan", "Magenta", "Yellow", "Black control"};
    for (int i = 0; i < 4; i++) {
        if (color) CGContextSetRGBFillColor(context, inks[i][0], inks[i][1], inks[i][2], 1);
        else CGContextSetGrayFillColor(context, i/4.0, 1);
        CGContextFillRect(context, CGRectMake(24 + i*78, height-164, 48, 24));
        if (color) {
            CGContextSetRGBFillColor(context, 0, 0, 1, 1);
            text_at(context, ink_names[i], 24+i*78, height-180, 9);
        }
    }
    CGContextSetRGBFillColor(context, 0, 0, color ? 1 : 0, 1);
    CGContextSetRGBStrokeColor(context, 0, 0, color ? 1 : 0, 1);
    CGContextSetLineWidth(context, 0.5);
    CGContextStrokeRect(context, CGRectMake(24, height-270, 72, 72));
    text_at(context, "This square should measure 1 inch (25.4 mm).", 112, height-232, 10);
    text_at(context, "0123456789  ABCDEFGHIJKLMNOPQRSTUVWXYZ", 24, height-300, 12);
    text_at(context, "abcdefghijklmnopqrstuvwxyz  /  fine lines below", 24, height-322, 10);
    for (int i = 0; i < 10; i++) {
        CGContextMoveToPoint(context, 24, height-340-i*3);
        CGContextAddLineToPoint(context, width-24, height-340-i*3);
    }
    CGContextStrokePath(context);
}

static int save_preview(CGContextRef context, const char *filename) {
    CFURLRef url = file_url(filename);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    CFRelease(url);
    if (!destination) return 0;
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGImageDestinationAddImage(destination, image, NULL);
    int result = CGImageDestinationFinalize(destination);
    CGImageRelease(image); CFRelease(destination);
    return result;
}

static void capabilities(stp_vars_t *vars) {
    const char *names[] = {"PageSize", "MediaType", "InputSlot", "Resolution", "InkType", "InkSet", "PrintingMode"};
    printf("Canon BJC-85 (bjc-85), Gutenprint %u.%u.%u\n", stp_major_version, stp_minor_version, stp_micro_version);
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        stp_parameter_t desc;
        stp_describe_parameter(vars, names[i], &desc);
        printf("%s (active=%d):", names[i], desc.is_active);
        if (desc.p_type == STP_PARAMETER_TYPE_STRING_LIST && desc.bounds.str) {
            for (size_t j = 0; j < stp_string_list_count(desc.bounds.str); j++) {
                const stp_param_string_t *item = stp_string_list_param(desc.bounds.str, j);
                printf(" %s", item->name);
            }
        }
        putchar('\n'); stp_parameter_description_destroy(&desc);
    }
}

int main(int argc, char **argv) {
    extern void bjc_runtime_initialize(void);
    bjc_runtime_initialize();
    if (argc < 2) {
        fprintf(stderr, "Usage: %s capabilities\n       %s test-page OUTPUT.bjc [mono|color] [Letter|A4]\n"
                "       %s pdf INPUT.pdf OUTPUT.bjc [mono|color] [Letter|A4]\n"
                "Renders to a file only. A PNG preview is written for each page.\n", argv[0], argv[0], argv[0]);
        return 2;
    }
    if (stp_init()) { fprintf(stderr, "Gutenprint initialization failed.\n"); return 1; }
    const stp_printer_t *printer = stp_get_printer_by_driver("bjc-85");
    if (!printer || strcmp(stp_printer_get_long_name(printer), "Canon BJC-85")) {
        fprintf(stderr, "Exact BJC-85 model not found; check the local Gutenprint XML installation.\n"); return 1;
    }
    stp_vars_t *vars = stp_vars_create();
    stp_set_printer_defaults(vars, printer);
    stp_set_errfunc(vars, write_error);
    if (argc == 2 && !strcmp(argv[1], "capabilities")) { capabilities(vars); stp_vars_destroy(vars); return 0; }
    int is_test = !strcmp(argv[1], "test-page");
    int is_pdf = !strcmp(argv[1], "pdf");
    int output_index = is_test ? 2 : 3;
    if ((!is_test && !is_pdf) || argc < output_index+1 || argc > output_index+3) { stp_vars_destroy(vars); return 2; }
    const char *mode = argc > output_index+1 ? argv[output_index+1] : "mono";
    const char *paper = argc > output_index+2 ? argv[output_index+2] : "Letter";
    if ((strcmp(mode,"mono") && strcmp(mode,"color")) || (strcmp(paper,"Letter") && strcmp(paper,"A4"))) {
        fprintf(stderr, "Mode must be mono/color and paper Letter/A4.\n"); stp_vars_destroy(vars); return 2;
    }
    int color = !strcmp(mode, "color");
    stp_set_string_parameter(vars, "PageSize", paper);
    stp_set_string_parameter(vars, "MediaType", "Plain");
    stp_set_string_parameter(vars, "InputSlot", "Auto");
    stp_set_string_parameter(vars, "Quality", "None");
    stp_set_string_parameter(vars, "Resolution", "360x360dpi");
    stp_set_string_parameter(vars, "InkType", color ? "CMYK" : "Gray");
    stp_set_string_parameter(vars, "PrintingMode", color ? "Color" : "BW");
    stp_set_string_parameter(vars, "InputImageType", "RGB");
    stp_set_string_parameter(vars, "ChannelBitDepth", "8");
    stp_set_string_parameter(vars, "JobMode", "Job");
    stp_dimension_t left, right, bottom, top;
    stp_get_imageable_area(vars, &left, &right, &bottom, &top);
    double width = right-left, height = bottom-top;
    if (width <= 0 || height <= 0 || width > 1000 || height > 2000) { stp_vars_destroy(vars); return 1; }
    stp_set_left(vars, left); stp_set_top(vars, top);
    stp_set_width(vars, width); stp_set_height(vars, height);
    stp_merge_printvars(vars, stp_printer_get_defaults(printer));
    if (!stp_verify(vars)) { fprintf(stderr, "Gutenprint rejected the selected settings.\n"); stp_vars_destroy(vars); return 1; }
    CGPDFDocumentRef pdf = NULL;
    size_t pages = 1;
    if (is_pdf) {
        CFURLRef url = file_url(argv[2]); pdf = CGPDFDocumentCreateWithURL(url); CFRelease(url);
        if (!pdf || CGPDFDocumentIsEncrypted(pdf)) { fprintf(stderr, "PDF unreadable or encrypted.\n"); if (pdf) CGPDFDocumentRelease(pdf); stp_vars_destroy(vars); return 1; }
        pages = CGPDFDocumentGetNumberOfPages(pdf);
        if (!pages || pages > 1000) { CGPDFDocumentRelease(pdf); stp_vars_destroy(vars); return 1; }
    }
    const char *destination = argv[output_index];
    char *temporary = malloc(strlen(destination)+16);
    char *preview = malloc(strlen(destination)+40);
    if (!temporary || !preview) { free(temporary); free(preview); if (pdf) CGPDFDocumentRelease(pdf); stp_vars_destroy(vars); return 1; }
    snprintf(temporary, strlen(destination)+16, "%s.XXXXXX", destination);
    int fd = mkstemp(temporary);
    output out = { .file = fd < 0 ? NULL : fdopen(fd, "wb") };
    if (!out.file) { perror(destination); if (fd >= 0) close(fd); unlink(temporary); free(temporary); free(preview); if (pdf) CGPDFDocumentRelease(pdf); stp_vars_destroy(vars); return 1; }
    stp_set_outfunc(vars, write_output); stp_set_outdata(vars, &out);
    int success = 1;
    for (size_t page = 1; page <= pages && success; page++) {
        raster r = { .width=(int)lround(width*5), .height=(int)lround(height*5) };
        r.pixels = calloc((size_t)r.width*r.height, 4);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = r.pixels ? CGBitmapContextCreate(r.pixels, r.width, r.height, 8, (size_t)r.width*4,
            space, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big) : NULL;
        CGColorSpaceRelease(space);
        if (!context) { free(r.pixels); success=0; break; }
        CGContextScaleCTM(context, r.width/width, r.height/height);
        CGContextSetRGBFillColor(context, 1,1,1,1); CGContextFillRect(context, CGRectMake(0,0,width,height));
        if (is_test) test_page(context, width, height, color);
        else {
            CGPDFPageRef pdf_page = CGPDFDocumentGetPage(pdf, page);
            CGContextConcatCTM(context, CGPDFPageGetDrawingTransform(pdf_page, kCGPDFMediaBox, CGRectMake(0,0,width,height), 0, true));
            CGContextDrawPDFPage(context, pdf_page);
        }
        snprintf(preview, strlen(destination)+40, "%s.page-%03zu.png", destination, page);
        success = save_preview(context, preview);
        stp_image_t image = {no_op,no_op,image_width,image_height,image_row,app_name,no_op,&r};
        if (success && page == 1) success = stp_start_job(vars, &image) == 1;
        if (success) success = stp_print(vars, &image) == 1;
        if (success && page == pages) success = stp_end_job(vars, &image) == 1;
        CGContextRelease(context); free(r.pixels);
        fprintf(stderr, "Page %zu/%zu: %s, imageable area %.1f x %.1f pt, origin %.1f/%.1f pt\n",
                page,pages,success?"rendered":"failed",width,height,left,top);
    }
    if (fclose(out.file)) out.failed=1;
    if (out.failed || !out.bytes) success=0;
    if (success && rename(temporary,destination)) { perror(destination); success=0; }
    if (!success) unlink(temporary);
    if (pdf) CGPDFDocumentRelease(pdf);
    stp_vars_destroy(vars); free(temporary); free(preview);
    fprintf(stderr, "%s: %zu raw bytes. No USB data sent.\n",success?"Complete":"Failed",out.bytes);
    return success?0:1;
}
