"""A competing process must fail before USB access; kernel release survives exit."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
helper = Path(os.environ.get('BJC85_TEST_HELPER', root / 'dist/BJC-85 Utility.app/Contents/Helpers/bjc85-is12'))
temporary = tempfile.TemporaryDirectory(prefix='bjc85-lease-test-')
runtime = Path(temporary.name)
lease = runtime / 'usb.lock'
environment = dict(os.environ, BJC85_OFFLINE_TEST='1',
                   BJC85_ADMISSION_PATH=str(runtime / 'admission.lock'),
                   BJC85_USB_LEASE_PATH=str(lease),
                   BJC85_RUNTIME_DIRECTORY=str(runtime), BJC85_STATE_DIRECTORY=str(runtime))
fd = os.open(lease, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
result = subprocess.run([helper, 'status', '--scanner-installed'], env=environment, capture_output=True, text=True, timeout=10)
assert result.returncode != 0
assert 'Another native BJC-85 operation owns USB' in result.stderr
assert '"event":"write"' not in result.stdout
print(json.dumps({'case':'competing native client blocked before USB', 'passed':True}))
os.close(fd)
child = subprocess.Popen([sys.executable, '-c',
    'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR); fcntl.flock(fd,fcntl.LOCK_EX); print("locked",flush=True); time.sleep(60)', str(lease)], stdout=subprocess.PIPE, text=True)
try:
    assert child.stdout.readline().strip() == 'locked'
    child.kill()
    child.wait(timeout=5)
    fd = os.open(lease, os.O_RDWR)
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    os.close(fd)
    print(json.dumps({'case':'owner crash releases lease without removing inode', 'passed':True}))
finally:
    if child.poll() is None: child.kill(); child.wait()
result = subprocess.run([helper, 'status', '--scanner-installed'], env=environment, capture_output=True, text=True, timeout=10)
assert result.returncode != 0  # The native offline guard still refuses USB after release.
assert 'Another native BJC-85 operation owns USB' not in result.stderr
assert '"event":"write"' not in result.stdout
assert '"event":"read"' not in result.stdout
print(json.dumps({'case':'released lease never bypasses offline USB guard', 'passed':True}))
temporary.cleanup()
