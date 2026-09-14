#include "runtime.h"
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <pwd.h>
#include <unistd.h>
int bjc_runtime_retain_diagnostics(void) {
    const char *override=getenv("BJC85_STATE_DIRECTORY"); struct passwd *user=getpwuid(getuid());
    char path[PATH_MAX];
    int n=override?snprintf(path,sizeof(path),"%s/retain-diagnostics",override):
        user?snprintf(path,sizeof(path),"%s/Library/Application Support/local.bjc85.utility/retain-diagnostics",user->pw_dir):-1;
    return n>0 && n<(int)sizeof(path) && !access(path,F_OK);
}
void bjc_runtime_initialize(void) {
    char executable[PATH_MAX], data[PATH_MAX]; uint32_t size=sizeof(executable);
    if (_NSGetExecutablePath(executable,&size)) return;
    char *end=strrchr(executable,'/'); if (!end) return; *end=0;
    int n=snprintf(data,sizeof(data),"%s/../Resources/gutenprint/xml",executable);
    struct stat st;
    if (n>0 && n<(int)sizeof(data) && !stat(data,&st) && S_ISDIR(st.st_mode)) setenv("STP_DATA_PATH",data,1);
}
