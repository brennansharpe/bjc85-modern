#ifndef BJC85_ADMISSION_H
#define BJC85_ADMISSION_H
/* Nonblocking, shared job admission; close() releases. -1 fails closed. */
int bjc_admission_acquire(void);
#endif
