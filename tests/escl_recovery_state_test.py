"""Exercise the real HTTP service with a fake child; no USB/discovery/real jobs."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
bridge = Path(sys.argv[1] if len(sys.argv) > 1 else root / 'build-handover/is12-escl-bridge').resolve()
xml = (root / 'tests/fixtures/escl-scan-settings.xml').read_bytes()
fake_source = '''#!/usr/bin/env python3
import json, os, sys, struct, zlib, time
from pathlib import Path
case=os.environ['FAKE_OUTCOME']
with open(os.environ['FAKE_CALLS'],'a') as f: f.write(sys.argv[1]+'\\n')
if sys.argv[1]=='status':
    ready=case!='wrongHead'
    print(json.dumps(dict(event='readiness',kind='ready' if ready else 'wrongHead',transport_ok=True,replies_ok=True,head_matches=ready,ready=ready,reference_valid=case!='invalidReference')))
    print(json.dumps(dict(event='operation_outcome',outcome='completedSafe' if ready else 'preflightFailedSafe')))
    sys.exit(0)  # Deliberately reproduces the old zero-exit readiness bug.
path=Path(sys.argv[-1]); path.mkdir()
if case.startswith('success'):
    marker=Path(os.environ['BJC85_RUNTIME_DIRECTORY'])/'recovery-required.json'
    marker.write_text('{}')
    deadline=time.monotonic()+5
    while not Path(os.environ['FAKE_RELEASE']).exists():
        if time.monotonic()>deadline: sys.exit(7)
        time.sleep(.01)
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    png=bytes.fromhex('89504e470d0a1a0a')+chunk(b'IHDR',struct.pack('>IIBBBBB',720,972,8,2,0,0,0))
    png+=chunk(b'IDAT',zlib.compress((bytes([0])+bytes([127,128,255])*720)*972))+chunk(b'IEND',b'')
    (path/'scan-raw.png').write_bytes(png)
    (path/'records.bin').write_bytes(b'fake pixels')
    (path/'outcome.json').write_text(json.dumps(dict(outcome='completedSafe',image_complete=True)))
    marker.unlink()
    print(json.dumps(dict(event='operation_outcome',outcome='completedSafe')))
    sys.exit(0)
if case!='missingReceipt':
    (path/'outcome.json').write_text(json.dumps(dict(outcome='recoveryRequired',image_complete=False)))
print(json.dumps(dict(event='operation_outcome',outcome='recoveryRequired')))
sys.exit(7)
'''

def request(base, method, path, body=None):
    req = urllib.request.Request(base + path, data=body, method=method,
                                 headers={'Content-Type': 'text/xml'})
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read(), response.headers
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.headers

def until(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate(): return
        except (OSError, urllib.error.URLError): pass
        time.sleep(0.03)
    raise AssertionError('Timed out waiting for offline service')

for case in ['wrongHead', 'invalidReference', 'ambiguous', 'missingReceipt', 'success', 'successRetained']:
    with tempfile.TemporaryDirectory(prefix='is12-escl-outcome-') as tmp:
        directory = Path(tmp)
        helper = directory / 'fake-driver'
        helper.write_text(fake_source); helper.chmod(0o700)
        calls = directory / 'calls.txt'
        release = directory / 'release'
        if case == 'successRetained': (directory / 'retain-diagnostics').touch()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        env = dict(os.environ, BJC85_RUNTIME_DIRECTORY=tmp, BJC85_ESCL_PORT=str(port),
                   BJC85_ESCL_ADVERTISE='0', FAKE_OUTCOME=case, FAKE_CALLS=str(calls), FAKE_RELEASE=str(release))
        args = [str(bridge), '--scanner-installed', str(helper), str(directory / 'reference.bin')]
        process = subprocess.Popen(args, cwd=tmp, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        base = f'http://127.0.0.1:{port}'
        try:
            until(lambda: request(base, 'GET', '/eSCL/ScannerCapabilities')[0] == 200)
            status, _, headers = request(base, 'POST', '/eSCL/ScanJobs', xml)
            job_path=urllib.parse.urlparse(headers['Location']).path
            assert status == 201, status
            jobs = directory / '.state/escl-jobs'
            if case.startswith('success'):
                until(lambda: (directory / 'recovery-required.json').exists())
                assert b'<pwg:State>Processing</pwg:State>' in request(base, 'GET', '/eSCL/ScannerStatus')[1]
                assert request(base, 'POST', '/eSCL/ScanJobs', xml)[0] == 503
                release.touch()
            until(lambda: bool(list(jobs.glob('*/acquisition-ended.json'))))
            ended = json.loads(next(jobs.glob('*/acquisition-ended.json')).read_text())
            if case in ['wrongHead', 'invalidReference']:
                assert calls.read_text().splitlines() == ['status']
                assert ended['outcome'] in ['preflightFailedSafe','completedSafe']
            elif case.startswith('success'):
                assert ended['outcome'] == 'completedSafe'
                until(lambda: b'<pwg:JobState>Completed</pwg:JobState>' in request(base,'GET',job_path)[1])
                assert request(base,'GET',job_path+'/NextDocument')[0] == 200
                capture=next(jobs.glob('*/capture'))
                if case == 'success': until(lambda: not (capture/'records.bin').exists())
                else: assert (capture/'records.bin').exists()
                assert (capture/'outcome.json').exists()
                assert b'<pwg:State>Idle</pwg:State>' in request(base,'GET','/eSCL/ScannerStatus')[1]
                assert request(base, 'POST', '/eSCL/ScanJobs', xml)[0] == 201
                until(lambda: len(list(jobs.glob('*/acquisition-ended.json')))==2)
            else:
                assert calls.read_text().splitlines() == ['status', 'scan']
                assert ended['outcome'] == 'recoveryRequired'
                assert request(base, 'POST', '/eSCL/ScanJobs', xml)[0] == 503
                assert b'<pwg:State>Stopped</pwg:State>' in request(base, 'GET', '/eSCL/ScannerStatus')[1]
        finally:
            process.terminate()
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == 0, (stdout, stderr)
        if case in ['ambiguous', 'missingReceipt']:
            restart = subprocess.run(args, cwd=tmp, env=env, capture_output=True, timeout=5)
            assert restart.returncode == 1 and b'interrupted scan needs inspection' in restart.stderr
            assert calls.read_text().splitlines() == ['status', 'scan']
        print(json.dumps({'case': case, 'passed': True, 'usb_access': False}))
