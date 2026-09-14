#include "recovery.h"
#include "usb.h"
#include <assert.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
int main(void) {
    char directory[]="/tmp/bjc85-recovery-test-XXXXXX"; assert(mkdtemp(directory));
    assert(setenv("BJC85_STATE_DIRECTORY",directory,1)==0);
    char lease[4096], admission[4096];
    snprintf(lease,sizeof(lease),"%s/usb.lock",directory); snprintf(admission,sizeof(admission),"%s/admission.lock",directory);
    assert(setenv("BJC85_OFFLINE_TEST","1",1)==0);
    assert(setenv("BJC85_USB_LEASE_PATH",lease,1)==0); assert(setenv("BJC85_ADMISSION_PATH",admission,1)==0);
    assert(!bjc_recovery_required());
    pid_t child=fork(); assert(child>=0);
    if (!child) { assert(bjc_recovery_begin("scan")); _exit(0); }
    int result; assert(waitpid(child,&result,0)==child && WIFEXITED(result) && WEXITSTATUS(result)==0);
    assert(bjc_recovery_required());
    bjc_usb usb; assert(bjc_usb_open(&usb)==LIBUSB_ERROR_BUSY);
    assert(usb.handle==NULL && usb.context==NULL); /* blocked before libusb_init */
    assert(!bjc_recovery_begin("print"));
    char path[4096]; assert(bjc_recovery_path(path,sizeof(path)));
    struct stat st; assert(stat(path,&st)==0 && (st.st_mode&0777)==0600);
    assert(bjc_recovery_finish_safe()); assert(!bjc_recovery_required());
    assert(symlink("/nonexistent",path)==0);
    assert(bjc_recovery_required()); /* broken/symlinked marker is never absent */
    assert(unlink(path)==0); assert(unlink(lease)==0); assert(unlink(admission)==0); assert(rmdir(directory)==0);
    puts("Recovery survives exit and blocks scan/print before USB initialization.");
    return 0;
}
