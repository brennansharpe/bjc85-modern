#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir="$project_dir/build-hardening-tests"
mkdir -p "$test_dir"
# Isolate lock files as well as document/runtime roots. The offline flag alone
# must never let fixture state inspection acquire the owner's live admission.
fixture_locks=$(mktemp -d /tmp/bjc85-swift-locks.XXXXXX)
trap 'rm -rf "$fixture_locks"' EXIT
export BJC85_OFFLINE_TEST=1
export BJC85_ADMISSION_PATH="$fixture_locks/admission.lock"
export BJC85_USB_LEASE_PATH="$fixture_locks/usb.lock"
for name in ${BJC85_TEST_SUITES:-document_pipeline workflow_controller shared_device_state service_transition review_repairs}; do
    xcrun swiftc -swift-version 5 -D BJC85_TESTING -parse-as-library -O -assert-config Debug -target arm64-apple-macos14.0 \
      -module-cache-path "$test_dir/cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
      "$project_dir"/app/*.swift "$project_dir"/app/Models/*.swift "$project_dir"/app/UI/*.swift \
      "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" \
      "$project_dir/tests/${name}_test.swift" -o "$test_dir/$name"
    BJC85_OFFLINE_TEST=1 "$test_dir/$name"
done
