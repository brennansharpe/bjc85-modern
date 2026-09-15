#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$project_dir/build-hardening-tests"
mkdir -p "$out"
# Isolate lock files as well as document/runtime roots. The offline flag alone
# must never let fixture state inspection acquire the owner's live admission.
fixture_locks=$(mktemp -d /tmp/bjc85-swift-locks.XXXXXX)
trap 'rm -rf "$fixture_locks"' EXIT
export BJC85_OFFLINE_TEST=1
export BJC85_ADMISSION_PATH="$fixture_locks/admission.lock"
export BJC85_USB_LEASE_PATH="$fixture_locks/usb.lock"
python3 "$project_dir/tests/make_synthetic_fixture.py" "$out/full-resolution.png"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$out/cache" -framework AppKit -framework ImageIO \
  -D BJC85_TESTING -assert-config Debug -framework UniformTypeIdentifiers \
  "$project_dir"/app/*.swift "$project_dir"/app/Models/*.swift "$project_dir"/app/UI/*.swift \
  "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" \
  "$project_dir/tests/processing_worker_test.swift" -o "$out/processing-worker"
BJC85_OFFLINE_TEST=1 "$out/processing-worker" "$out/full-resolution.png"
