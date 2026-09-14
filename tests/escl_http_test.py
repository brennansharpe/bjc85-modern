"""Exercise an idle bridge's HTTP validation. Never submit a valid scan job."""
import http.client
import json
import os
from pathlib import Path

settings = (Path(__file__).resolve().parent / 'fixtures/escl-scan-settings.xml').read_bytes()


def request(method, path, body=None, headers=None):
    connection = http.client.HTTPConnection('127.0.0.1', int(os.environ.get('BJC85_ESCL_TEST_PORT','8641')), timeout=5)
    connection.request(method, path, body=body, headers=headers or {})
    response = connection.getresponse()
    status, location, data = response.status, response.getheader('Location'), response.read()
    connection.close()
    return status, location, data


status, _, data = request('GET', '/eSCL/ScannerCapabilities')
assert status == 200 and b'ScannerCapabilities' in data
for label, body, headers, expected in [
    ('browser origin', settings, {'Content-Type':'text/xml', 'Origin':'https://example.invalid'}, 403),
    ('untrusted host', settings, {'Content-Type':'text/xml', 'Host':'example.invalid'}, 403),
    ('form content', settings, {'Content-Type':'text/plain'}, 415),
    ('DTD', settings.replace(b'<scan:ScanSettings', b'<!DOCTYPE root []><scan:ScanSettings', 1), {'Content-Type':'text/xml'}, 400),
    ('unsupported dpi', settings.replace(b'>90<', b'>150<'), {'Content-Type':'text/xml'}, 400),
    ('oversized area', settings.replace(b'>2400<', b'>3000<'), {'Content-Type':'text/xml'}, 400),
    ('duplicate dpi', settings.replace(b'<scan:XResolution>90</scan:XResolution>', b'<scan:XResolution>90</scan:XResolution>'*2), {'Content-Type':'text/xml'}, 400),
]:
    actual, _, _ = request('POST', '/eSCL/ScanJobs', body, headers)
    assert actual == expected, (label, actual)
    print(json.dumps({'case':label, 'status':actual}))
