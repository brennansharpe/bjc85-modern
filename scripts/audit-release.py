"""Fail closed on undeclared runtime dependencies, architectures and deployment targets."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert 'BJC85ProjectRoot' not in metadata
records = []
for directory in ['MacOS', 'Helpers', 'Frameworks']:
    for path in sorted((app / 'Contents' / directory).iterdir()):
        arch = subprocess.check_output(['lipo', '-archs', str(path)], text=True).strip()
        assert arch == 'arm64', (path, arch)
        builds = subprocess.check_output(['vtool', '-show-build', str(path)], text=True)
        minimum = re.findall(r'\bminos\s+(\d+(?:\.\d+)*)', builds)
        assert minimum and all(tuple(map(int, x.split('.'))) <= (14, 0, 0) for x in minimum), (path, minimum)
        dependencies = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]
        for line in dependencies:
            dependency = line.strip().split(' (', 1)[0]
            assert dependency.startswith(('/usr/lib/', '/System/Library/', '@')), (path, dependency)
            assert '/opt/homebrew/' not in dependency
        records.append(dict(file=str(path.relative_to(app)), architecture=arch, minimum_os=minimum))
for path in app.rglob('*'):
    assert path.suffix.lower() not in {'.dll', '.exe', '.rsrc', '.icc', '.icm', '.bin', '.sit', '.sea'}, path
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
# Loader/resource failures are invisible to otool. These commands never open USB.
for helper, argument in [('bjc85-render','capabilities'),('bjc85-is12','plan')]:
    subprocess.run([str(app/'Contents/Helpers'/helper),argument],cwd='/tmp',check=True,capture_output=True)
print(json.dumps(dict(bundle=app.name, checks='architecture, minimum OS, runtime links, signature, Canon asset exclusion, offline helper execution', binaries=records), indent=2))
