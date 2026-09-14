/* Read-only CUPS Get-Job-Attributes. A missing history entry is UNKNOWN. */
#include <cups/cups.h>
#include <cups/ipp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void json_string(const char *s) {
    putchar('"'); for (;s && *s;s++) { unsigned char c=(unsigned char)*s; if (c=='"'||c=='\\') putchar('\\'); if(c>=32) putchar(c); } putchar('"');
}
int main(int argc,char **argv) {
    if (argc!=3 || strcmp(argv[1],"BJC85_Native")) return 2;
    char *end; long id=strtol(argv[2],&end,10); if (*end || id<1 || id>2147483647) return 2;
    http_t *http=httpConnect2("localhost",631,NULL,AF_UNSPEC,HTTP_ENCRYPTION_IF_REQUESTED,1,3000,NULL);
    if (!http) return 1;
    httpSetTimeout(http,5,NULL,NULL);
    char uri[256]; snprintf(uri,sizeof(uri),"ipp://localhost/jobs/%ld",id);
    ipp_t *request=ippNewRequest(IPP_OP_GET_JOB_ATTRIBUTES);
    ippAddString(request,IPP_TAG_OPERATION,IPP_TAG_URI,"job-uri",NULL,uri);
    ippAddString(request,IPP_TAG_OPERATION,IPP_TAG_NAME,"requesting-user-name",NULL,cupsUser());
    const char *attrs[]={"job-id","job-printer-uri","job-state","job-state-reasons"};
    ippAddStrings(request,IPP_TAG_OPERATION,IPP_TAG_KEYWORD,"requested-attributes",4,NULL,attrs);
    ipp_t *reply=cupsDoRequest(http,request,"/");
    if (!reply || ippGetStatusCode(reply)>IPP_STATUS_OK_EVENTS_COMPLETE) { if(reply) ippDelete(reply); httpClose(http); return 1; }
    ipp_attribute_t *state=ippFindAttribute(reply,"job-state",IPP_TAG_ENUM), *printer=ippFindAttribute(reply,"job-printer-uri",IPP_TAG_URI);
    ipp_attribute_t *job=ippFindAttribute(reply,"job-id",IPP_TAG_INTEGER);
    const char *printer_uri=printer?ippGetString(printer,0,NULL):NULL;
    const char *tail=printer_uri?strrchr(printer_uri,'/'):NULL;
    if (!job || ippGetInteger(job,0)!=id || !state || !tail || strcmp(tail+1,argv[1])) { ippDelete(reply); httpClose(http); return 1; }
    printf("{\"state\":%d,\"destination\":",ippGetInteger(state,0));json_string(argv[1]);printf(",\"id\":%ld,\"reasons\":[",id);
    ipp_attribute_t *reasons=ippFindAttribute(reply,"job-state-reasons",IPP_TAG_KEYWORD);
    for (int i=0;reasons && i<ippGetCount(reasons);i++) { if(i) putchar(','); json_string(ippGetString(reasons,i,NULL)); }
    puts("]}");ippDelete(reply);httpClose(http);return 0;
}
