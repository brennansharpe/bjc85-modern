#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=${1:-"$project_dir/build-handover/swift-tests"}
mkdir -p "$test_dir"
for name in canon_presets device_coordinator copy_workflow print_settings_mapping privacy_retention scan_processing accessibility_smoke; do
    /usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
        -O -module-cache-path "$test_dir/module-cache" -framework AppKit -framework ImageIO \
        -D BJC85_TESTING -framework UniformTypeIdentifiers \
        "$project_dir"/app/*.swift "$project_dir"/app/Models/*.swift "$project_dir"/app/UI/*.swift \
        "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" \
        "$project_dir/tests/${name}_test.swift" -o "$test_dir/$name"
    BJC85_OFFLINE_TEST=1 "$test_dir/$name"
done
