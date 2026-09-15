"""Run HTTP validation against a temporary bridge with an inert child adapter."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="bjc85-http-fixture-") as tmp:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, BJC85_RUNTIME_DIRECTORY=tmp, BJC85_STATE_DIRECTORY=tmp,
               BJC85_ESCL_PORT=str(port), BJC85_ESCL_TEST_PORT=str(port),
               BJC85_ESCL_ADVERTISE="0", BJC85_OFFLINE_TEST="1")
    process = subprocess.Popen([sys.argv[1], "--scanner-installed", "/usr/bin/false", str(Path(tmp)/"reference.bin")],
                               cwd=tmp, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError("Fixture bridge failed to start")
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=.1): break
            except OSError: time.sleep(.03)
        else: raise RuntimeError("Fixture bridge start timed out")
        subprocess.run([sys.executable, str(Path(__file__).with_name("escl_http_test.py"))], env=env, check=True)
    finally:
        process.terminate()
        process.wait(timeout=10)
