"""Exercise bundled PAPPL/Gutenprint with an isolated dry-run spool; never USB."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
helper = Path(sys.argv[1]).resolve()
fixtures=Path(os.environ['BJC85_TEST_FIXTURE_DIR'])
letter, a4 = (fixtures/'letter.urf', fixtures/'a4.urf')
assert letter.exists() and a4.exists(), 'Generate synthetic URF fixtures with test-isolated-services.sh first.'
with tempfile.TemporaryDirectory(prefix='bjc85-ipp-dry-') as temporary:
    spool = Path(temporary)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
    url=f'ipp://localhost:{port}/ipp/print'
    def start():
        log=(spool/'test-service.log').open('ab')
        process=subprocess.Popen([str(helper),'--dry-run','--spool-dir',temporary,'--port',str(port)],cwd=temporary,stdout=log,stderr=log)
        for _ in range(100):
            assert process.poll() is None, (spool/'test-service.log').read_text()
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1): return process,log
            except OSError: time.sleep(.03)
        process.terminate(); process.wait(timeout=5); log.close()
        raise AssertionError('Dry-run service did not start')
    def stop(process,log):
        process.terminate(); process.wait(timeout=10); log.close()
    def check(name):
        result=subprocess.run(['/usr/bin/ipptool','-t','-d',f'letter={letter}','-d',f'a4={a4}',url,str(root/'tests'/name)],capture_output=True,text=True,timeout=90)
        print(result.stdout)
        assert result.returncode==0, result.stderr
    process,log=start()
    try: check('ipp-acceptance.test')
    finally: stop(process,log)
    process,log=start()
    try:
        check('ipp-restart.test')
        (spool/'usb-recovery-required.txt').write_text('offline test marker')
        check('ipp-recovery.test')
    finally: stop(process,log)
print(json.dumps({'ipp_dry_run':True,'restart':True,'recovery_gate':True,'usb_access':False}))
