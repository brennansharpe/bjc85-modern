#ifndef BJC85_TRANSFER_H
#define BJC85_TRANSFER_H
#include <stddef.h>
#include <stdint.h>
typedef int (*bjc_transfer_fn)(void *, const unsigned char *, int, int *);
typedef uint64_t (*bjc_clock_fn)(void *);
int bjc_transfer_all(const unsigned char *data, size_t length, size_t *sent,
                     void *context, bjc_transfer_fn transfer, bjc_clock_fn now);
#endif
