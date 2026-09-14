#include "recovery.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static int directory(void) {
    char path[PATH_MAX]; const char *override=getenv("BJC85_STATE_DIRECTORY");
    struct passwd *user=getpwuid(getuid());
    int n=override?snprintf(path,sizeof(path),"%s",override):
        user?snprintf(path,sizeof(path),"%s/Library/Application Support/local.bjc85.utility",user->pw_dir):-1;
    if (n<0 || n>=(int)sizeof(path) || path[0]!='/') return -1;
    /* Create missing parents, but never change existing permissions. */
    for (char *p=path+1;*p;p++) if (*p=='/') {
        *p=0; int rc=mkdir(path,0700); *p='/'; if (rc && errno!=EEXIST) return -1;
    }
    if (mkdir(path,0700) && errno!=EEXIST) return -1;
    int fd=open(path,O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW); struct stat st;
    if (fd<0) return -1;
    if (fstat(fd,&st) || st.st_uid!=getuid() || (st.st_mode&077)) { close(fd); return -1; }
    return fd;
}
bool bjc_recovery_path(char *path,size_t capacity) {
    const char *override=getenv("BJC85_STATE_DIRECTORY"); struct passwd *user=getpwuid(getuid());
    int n=override?snprintf(path,capacity,"%s/recovery-required.json",override):
        user?snprintf(path,capacity,"%s/Library/Application Support/local.bjc85.utility/recovery-required.json",user->pw_dir):-1;
    return n>=0 && (size_t)n<capacity;
}
bool bjc_recovery_required(void) {
    int fd=directory(); if (fd<0) return true;
    struct stat st; int rc=fstatat(fd,"recovery-required.json",&st,AT_SYMLINK_NOFOLLOW);
    bool required=rc==0 || errno!=ENOENT; close(fd); return required;
}
bool bjc_recovery_begin(const char *operation) {
    if (!operation || strspn(operation,"abcdefghijklmnopqrstuvwxyz-")!=strlen(operation)) return false;
    int dir=directory(); if (dir<0) return false;
    int fd=openat(dir,"recovery-required.json",O_CREAT|O_EXCL|O_WRONLY|O_CLOEXEC|O_NOFOLLOW,0600);
    if (fd<0) { close(dir); return false; }
    char body[256]; int n=snprintf(body,sizeof(body),"{\"schema_version\":1,\"outcome\":\"recoveryRequired\",\"operation\":\"%s\",\"pid\":%ld}\n",operation,(long)getpid());
    bool ok=n>0 && n<(int)sizeof(body) && write(fd,body,(size_t)n)==n && fsync(fd)==0;
    if (close(fd)) ok=false;
    if (fsync(dir)) ok=false;
    close(dir); return ok;
}
bool bjc_recovery_finish_safe(void) {
    int dir=directory(); if (dir<0) return false;
    bool ok=unlinkat(dir,"recovery-required.json",0)==0;
    if (ok && fsync(dir)) ok=false;
    close(dir); return ok;
}
