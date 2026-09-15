#!/bin/sh
# Offline only: C tests use fake transports or committed status/calibration fixtures.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
export BJC85_OFFLINE_TEST=1
python3 tests/repository_privacy_test.py
prefix=${BJC85_DEPENDENCY_PREFIX:-"$project_dir/build-source-deps/install"}
[ -f "$prefix/lib/libusb-1.0.0.dylib" ] || { echo "Run sh scripts/setup-source-alpha.sh once, or set BJC85_DEPENDENCY_PREFIX to the rebuilt dependency prefix." >&2; exit 1; }
cmake -S . -B build-source-alpha -DCMAKE_BUILD_TYPE=Debug -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DLIBUSB_INCLUDE_DIR="$prefix/include/libusb-1.0" -DLIBUSB_LIBRARY="$prefix/lib/libusb-1.0.0.dylib"
cmake --build build-source-alpha --parallel 4
ctest --test-dir build-source-alpha --output-on-failure
if [ ! -f "$project_dir/.local/lib/libgutenprint.a" ]; then
    echo "SKIP: optional Gutenprint capability test (no local static library); core native tests remain required."
fi
sh scripts/test-swift.sh build-source-alpha/swift-tests
sh scripts/test-hardening.sh

# Compile the complete production AppKit application, with its real entry point.
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
    -module-cache-path build-source-alpha/swift-tests/module-cache \
    -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
    app/*.swift app/Models/*.swift app/UI/*.swift \
    src/DriverOutcome.swift src/SharedDeviceState.swift src/FileIdentity.swift src/LocalServiceIdentity.swift \
    -o build-source-alpha/BJC85Scanner
printf '%s\n' 'PASS: production application compiled; not launched or packaged.'
printf '%s\n' 'SKIP: physical operations and private-capture replays are separate acceptance work.'
