"""An unclosed journal must block bridge startup before discovery or USB."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
bridge = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='is12-recovery-') as temporary:
    directory = Path(temporary) / '.state/escl-jobs/TEST-INTERRUPTED-JOB'
    directory.mkdir(parents=True)
    marker = directory / 'acquisition-started.json'
    marker.write_text('{"test_fixture":true}\n')
    result = subprocess.run([bridge, '--scanner-installed', '/usr/bin/false', Path(temporary) / 'reference.bin'],
                            cwd=temporary, env=dict(os.environ,BJC85_RUNTIME_DIRECTORY=temporary,BJC85_STATE_DIRECTORY=temporary,BJC85_ESCL_ADVERTISE='0'),capture_output=True, text=True, timeout=5)
    assert result.returncode == 1
    assert 'interrupted scan needs inspection' in result.stderr
    assert not result.stdout
    assert marker.exists() and not (directory / 'acquisition-ended.json').exists()
    print(json.dumps({'case':'restart blocked on an unclosed acquisition journal', 'passed':True,
                      'usb_commands_sent':0,'journal_retained':True}))
