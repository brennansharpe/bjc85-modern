#include "escl_publish.h"
#include <dns_sd.h>
#include <dispatch/dispatch.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>

static DNSServiceRef service;
static void registered(DNSServiceRef ref,DNSServiceFlags flags,DNSServiceErrorType error,
                       const char *name,const char *type,const char *domain,void *context) {
    (void)ref; (void)flags; (void)name; (void)type; (void)domain; (void)context;
    printf("{\"event\":\"airscan_registration\",\"error\":%d,\"local_only\":true}\n",error); fflush(stdout);
}
bool is12_escl_publish(unsigned port) {
    if (service || !port || port>65535) return false;
    TXTRecordRef txt; TXTRecordCreate(&txt,0,NULL);
    const char *keys[]={"txtvers","vers","rs","ty","pdl","cs","is","duplex","UUID"};
    const char *values[]={"1","2.0","eSCL","Canon BJC-85 IS-12 Native",
        "image/png,image/jpeg","color,grayscale,binary","adf","F","00000000-0000-4000-8000-000000000009"};
    bool ok=true;
    for (unsigned i=0;i<9;i++)
        if (TXTRecordSetValue(&txt,keys[i],(uint8_t)strlen(values[i]),values[i])) ok=false;
    DNSServiceErrorType rc=ok?DNSServiceRegister(&service,0,kDNSServiceInterfaceIndexLocalOnly,
        "Canon BJC-85 IS-12 Native","_uscan._tcp.","local.","localhost.",htons((uint16_t)port),
        TXTRecordGetLength(&txt),TXTRecordGetBytesPtr(&txt),registered,NULL):kDNSServiceErr_Unknown;
    TXTRecordDeallocate(&txt);
    if (rc || DNSServiceSetDispatchQueue(service,dispatch_get_main_queue())) { is12_escl_unpublish(); return false; }
    return true;
}
void is12_escl_unpublish(void) { if (service) { DNSServiceRefDeallocate(service); service=NULL; } }
