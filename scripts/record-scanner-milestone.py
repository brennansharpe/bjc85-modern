#!/usr/bin/env python3
"""Record local scanner evidence and hashes; does not open USB or run Canon code."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()


def main():
    acquisitions = []
    logs = list((ROOT / 'docs/protocol').glob('is12-*.jsonl'))
    logs += list((ROOT / '.state/escl-jobs').glob('*/driver.jsonl'))
    for log in sorted(logs):
        rows = [json.loads(line) for line in log.read_text().splitlines() if line.startswith('{')]
        result = next((row for row in reversed(rows) if row.get('event') == 'scan_result'), None)
        if result is None:
            continue
        start = next((row for row in rows if row.get('event') == 'scan_start'), {})
        writes = [row for row in rows if row.get('event') == 'write']
        acquisitions.append(dict(log=str(log.relative_to(ROOT)), sha256=digest(log),
                                 settings=start, result=result,
                                 usb_writes=len(writes),
                                 all_writes_accepted=all(row['accepted'] == row['requested'] and row['usb_result'] == 0 for row in writes)))
    binaries = [ROOT / name for name in [
        'build/bjc85-is12', 'build-asan/bjc85-is12',
        'build/BJC-85 Scanner.app/Contents/MacOS/BJC85Scanner',
        'build/BJC-85 Scanner.app/Contents/Helpers/bjc85-is12',
        'build/BJC-85 Scanner.app/Contents/Helpers/is12-escl-bridge',
        'build/BJC-85 Scanner.app/Contents/Frameworks/libusb-1.0.0.dylib',
        'build/is12-imagecapture-probe', 'build/is12-scan-export',
        '.tools/jdk-21.0.12.1+1/Contents/Home/bin/java',
        '.tools/ghidra_12.1.3_PUBLIC/Ghidra/Features/Decompiler/build/os/mac_arm_64/decompile']]
    files = list((ROOT / 'src').glob('is12*')) + list((ROOT / 'app').glob('*.swift'))
    files += list((ROOT / 'src').glob('escl*')) + [ROOT / 'src/usb.c', ROOT / 'src/usb.h', ROOT / 'src/imagecapture_probe.swift']
    files += list((ROOT / 'scripts').glob('*.sh')) + list((ROOT / 'scripts').glob('*.py'))
    files += list((ROOT / 'tests').glob('*.py')) + list((ROOT / 'tests').glob('*.c'))
    files += [ROOT / 'CMakeLists.txt', ROOT / '.state/local.bjc85.native-scan.plist',
              ROOT / '.state/scanner-app/settings.json', ROOT / 'docs/protocol/is12-final-service-check.json']
    files += list((ROOT / '.state/escl-jobs').rglob('*'))
    files += list((ROOT / 'docs/protocol').glob('is12-*-acceptance*'))
    files += list((ROOT / 'scans/2026-09-13').glob('*'))
    files += list((ROOT / 'tests/fixtures').glob('is12-*'))
    for directory in list((ROOT / '.state').glob('is12-scan-*')) + list((ROOT / '.state').glob('is12-calibration-*')) + list((ROOT / '.state/scanner-app').glob('scan-*')):
        if directory.is_dir():
            files += [path for path in directory.iterdir() if path.is_file() and not path.name.startswith('partial-')]
    manifest = dict(
        recorded_at_utc=datetime.now(timezone.utc).isoformat(),
        native_host=platform.machine(),
        acquisition_logs=acquisitions,
        binaries_at_record_time={str(p.relative_to(ROOT)): dict(sha256=digest(p), architecture=subprocess.check_output(['/usr/bin/file', '-b', str(p)], text=True).strip()) for p in binaries if p.exists()},
        files_at_record_time={str(p.relative_to(ROOT)): dict(bytes=p.stat().st_size, sha256=digest(p)) for p in sorted(set(files)) if p.is_file()},
        source_note='Source hashes describe current development files; historical captures may predate later changes. Preserved driver-tested.bin files identify individual tested executables where available.',
        static_analysis_toolchain=[
            dict(name='Ghidra 12.1.3', url='https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.3_build', archive_sha256='93a5d11a9ad510622acaaf908c556a7b9b764d338e78a7567f3689bf5081fd54', official_digest_matched=True, decompiler_built_locally='mac_arm_64'),
            dict(name='Temurin JDK 21.0.12.1+1', url='https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.12.1%2B1', archive_sha256='3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998', official_digest_matched=True, architecture='aarch64')],
        canon_executable_code_run=False,
        rosetta_used=False,
        canon_reference_colour_accuracy_validated=False,
        tests='Seven CTest checks pass in normal and ASAN/UBSAN builds; six Python image contracts; independent pixel comparison of real captures; native PNG/TIFF/PDF exports; exclusive USB lease, HTTP validation, and interrupted-job startup checks. Detailed acceptance logs are retained alongside this manifest.',
        hardware_state='IS-12 installed; print service stopped and BJC85_Native paused. Do not resume until BC-11e is restored.')
    destination = ROOT / 'docs/protocol/is12-native-scan-manifest.json'
    destination.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Recorded {len(acquisitions)} acquisitions, {len(manifest["files_at_record_time"])} files.')


if __name__ == '__main__':
    main()
