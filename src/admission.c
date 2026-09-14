#include "admission.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
int bjc_admission_acquire(void) {
    char path[4096];
    const char *test=getenv("BJC85_OFFLINE_TEST"), *override=getenv("BJC85_ADMISSION_PATH");
    int n=(test && !strcmp(test,"1") && override)?snprintf(path,sizeof(path),"%s",override):
        snprintf(path,sizeof(path),"/tmp/bjc85-admission-%lu.lock",(unsigned long)getuid());
    if (n<0 || n>=(int)sizeof(path)) return -1;
    int fd=open(path,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600); struct stat st;
    if (fd<0) return -1;
    if (fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_uid!=getuid() || st.st_nlink!=1 || (st.st_mode&077) || flock(fd,LOCK_SH|LOCK_NB)) { close(fd); return -1; }
    return fd;
}
