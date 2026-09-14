#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=${1:-"$project_dir/build-handover/swift-tests"}
mkdir -p "$test_dir"
for name in canon_presets device_coordinator copy_workflow print_settings_mapping privacy_retention scan_processing accessibility_smoke; do
    /usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
        -module-cache-path "$test_dir/module-cache" -framework AppKit -framework ImageIO \
        "$project_dir"/app/Models/*.swift "$project_dir/app/DeviceCoordinator.swift" "$project_dir/app/CopyWorkflow.swift" \
        "$project_dir/app/ScanProcessing.swift" "$project_dir/app/PrivacyRetention.swift" "$project_dir/app/Localization.swift" "$project_dir/src/DriverOutcome.swift" \
        "$project_dir"/app/UI/*.swift "$project_dir/tests/${name}_test.swift" -o "$test_dir/$name"
    "$test_dir/$name"
done
