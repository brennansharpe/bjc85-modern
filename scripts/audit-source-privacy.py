"""Read-only inventory of tracked files and reachable history; optional redacted evidence.

This is a bounded pattern audit, not permission to publish or a secret-scanner
certification. Originals and Git objects are never changed. Derivatives require
manual review and must go outside the tracked documentation tree.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--redacted-dir', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
def git(*values):
    return subprocess.check_output(['git', '-C', str(root), *values])

# Read the known test device identifiers locally; never print their values.
serials = set()
for file in (root / 'docs/protocol').glob('usb-*-baseline.json'):
    value = json.loads(file.read_text()).get('serial')
    if value:
        serials.add(value)
patterns = [
    ('user-home-path', re.compile(r'/Users/[^/\s"\'<>]+')),
    ('email-address', re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')),
    ('private-key-header', re.compile(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----')),
]
if serials:
    patterns.append(('test-device-serial', re.compile('|'.join(re.escape(v) for v in sorted(serials)))))

def categories(data):
    text = data.decode('utf-8', errors='replace')
    return [name for name, pattern in patterns if pattern.search(text)]

tracked = git('ls-files', '-z').decode().split('\0')[:-1]
tracked_hits = []
derivatives = []
destination = args.redacted_dir.resolve() if args.redacted_dir else None
if destination:
    # Never overwrite a source directory or existing derivative/evidence set.
    if destination == root or root / 'docs' in destination.parents or destination.exists():
        raise SystemExit('Choose a new derivative directory outside docs and existing evidence.')
    destination.mkdir(parents=True, mode=0o700)
for name in tracked:
    path = root / name
    if not path.is_file():
        continue
    data = path.read_bytes()
    matches = categories(data)
    if not matches:
        continue
    tracked_hits.append(dict(path=name, categories=matches))
    if destination and name.startswith(('docs/protocol/', 'docs/verification/')) and '\0' not in data.decode('utf-8', errors='replace'):
        text = data.decode('utf-8')
        for category, pattern in patterns:
            text = pattern.sub('[REDACTED-' + category.upper() + ']', text)
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        redacted = text.encode()
        target.write_bytes(redacted)
        derivatives.append(dict(source=name, source_sha256=hashlib.sha256(data).hexdigest(),
                                derivative=str(target.relative_to(destination)),
                                derivative_sha256=hashlib.sha256(redacted).hexdigest(), redactions=matches))

history_hits = []
blob_count = 0
for line in git('rev-list', '--objects', '--all').decode().splitlines():
    oid, _, name = line.partition(' ')
    if git('cat-file', '-t', oid).strip() != b'blob':
        continue
    blob_count += 1
    matches = categories(git('cat-file', 'blob', oid))
    if matches:
        history_hits.append(dict(object=oid, path=name, categories=matches))
report = dict(baseline=git('rev-parse', 'HEAD').decode().strip(),
              tracked_files=len(tracked), reachable_commits=int(git('rev-list', '--count', '--all')),
              reachable_blobs=blob_count, tracked_hits=tracked_hits, history_hits=history_hits,
              limitations='Pattern matches require manual review; email hits include upstream credits. Ignored private captures are not audited. No license or publication approval is implied.')
if destination:
    manifest = dict(provenance='Redacted from current tracked local evidence; originals and Git history preserved.',
                    status='Draft public derivatives: owner review required; not uploaded.', files=derivatives)
    (destination / 'provenance.json').write_text(json.dumps(manifest, indent=2) + '\n')
    report['redacted_derivative_count'] = len(derivatives)
print(json.dumps(report, indent=2))
