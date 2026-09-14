/* Local-only AirScan discovery experiment. No USB or scan commands. */
#include <dns_sd.h>
#include <arpa/inet.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <time.h>

static volatile sig_atomic_t stopped;
static void stop(int value) { (void)value; stopped=1; }
static void registered(DNSServiceRef ref,DNSServiceFlags flags,DNSServiceErrorType error,
                       const char *name,const char *type,const char *domain,void *context) {
    (void)ref; (void)flags; (void)type; (void)domain; (void)context;
    printf("{\"event\":\"bonjour_registration\",\"error\":%d,\"name\":\"%s\",\"local_only\":true}\n",error,name);
    fflush(stdout);
    if (error) stopped=1;
}
int main(void) {
    DNSServiceRef service=NULL;
    TXTRecordRef txt; TXTRecordCreate(&txt,0,NULL);
    const char *keys[]={"txtvers","vers","rs","ty","pdl","cs","is","duplex","UUID"};
    const char *values[]={"1","2.0","eSCL","Canon BJC-85 IS-12 Native Discovery Test",
        "image/png,image/jpeg","color,grayscale","adf","F","00000000-0000-4000-8000-00000000000d"};
    for (unsigned i=0;i<9;i++) {
        unsigned length=0; while (values[i][length]) length++;
        if (TXTRecordSetValue(&txt,keys[i],(uint8_t)length,values[i])) return 1;
    }
    DNSServiceErrorType rc=DNSServiceRegister(&service,0,kDNSServiceInterfaceIndexLocalOnly,
        "BJC-85 IS-12 Native Discovery Test","_uscan._tcp.","local.","localhost.",htons(8640),
        TXTRecordGetLength(&txt),TXTRecordGetBytesPtr(&txt),registered,NULL);
    TXTRecordDeallocate(&txt);
    if (rc) { fprintf(stderr,"DNSServiceRegister: %d\n",rc); return 1; }
    signal(SIGINT,stop); signal(SIGTERM,stop);
    struct pollfd fd={.fd=DNSServiceRefSockFD(service),.events=POLLIN};
    time_t deadline=time(NULL)+600;
    while (!stopped && time(NULL)<deadline) {
        if (poll(&fd,1,500)>0 && (fd.revents&POLLIN))
            if (DNSServiceProcessResult(service)) break;
    }
    DNSServiceRefDeallocate(service);
    return 0;
}
