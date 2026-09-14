#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir="$project_dir/build-hardening-tests"
mkdir -p "$test_dir"
for name in document_pipeline workflow_controller shared_device_state service_transition; do
    xcrun swiftc -swift-version 5 -D BJC85_TESTING -parse-as-library -O -target arm64-apple-macos14.0 \
      -module-cache-path "$test_dir/cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
      "$project_dir"/app/*.swift "$project_dir"/app/Models/*.swift "$project_dir"/app/UI/*.swift \
      "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" \
      "$project_dir/tests/${name}_test.swift" -o "$test_dir/$name"
    BJC85_OFFLINE_TEST=1 "$test_dir/$name"
done
