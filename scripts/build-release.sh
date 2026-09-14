#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prefix="$project_dir/build-release-deps/install"
build_dir="$project_dir/build-release"
app_dir="$project_dir/dist/BJC-85 Utility.app"
identity=${BJC85_SIGNING_IDENTITY:--}
sign_binary() {
    if [ "$identity" = - ]; then
        # Hardened library validation requires a Team ID; ad-hoc has none.
        /usr/bin/codesign --force --sign - "$1"
    else
        /usr/bin/codesign --force --sign "$identity" --options runtime "$1"
    fi
}
sh "$project_dir/scripts/build-release-deps.sh"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
cmake -S "$project_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DGUTENPRINT_ROOT="$prefix" -DLIBUSB_INCLUDE_DIR="$prefix/include/libusb-1.0" -DLIBUSB_LIBRARY="$prefix/lib/libusb-1.0.0.dylib"
cmake --build "$build_dir" -j "${BJC85_BUILD_JOBS:-6}"
ctest --test-dir "$build_dir" --output-on-failure
if /usr/bin/pgrep -f "$app_dir/Contents/" >/dev/null; then echo 'Quit the staged Utility and its helpers before rebuilding this bundle.' >&2; exit 1; fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources/Licenses" "$build_dir/escl-main"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
    -module-cache-path "$build_dir/swift-module-cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
    "$project_dir"/app/*.swift "$project_dir"/app/Models/*.swift "$project_dir"/app/UI/*.swift \
    "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" -o "$app_dir/Contents/MacOS/BJC85Scanner"
cp "$project_dir/src/escl_bridge.swift" "$build_dir/escl-main/main.swift"
/usr/bin/xcrun clang -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
    -c "$project_dir/src/escl_publish.c" -o "$build_dir/escl_publish.o"
/usr/bin/xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
    -module-cache-path "$build_dir/swift-module-cache" -import-objc-header "$project_dir/src/escl_publish.h" \
    -framework Network -framework ImageIO "$build_dir/escl-main/main.swift" "$project_dir/src/DriverOutcome.swift" "$project_dir/src/SharedDeviceState.swift" "$project_dir/src/FileIdentity.swift" "$project_dir/src/LocalServiceIdentity.swift" \
    "$project_dir/app/PrivacyRetention.swift" "$build_dir/escl_publish.o" -o "$app_dir/Contents/Helpers/is12-escl-bridge"
for helper in bjc85-job-query bjc85-is12 bjc85-ipp bjc85-render bjc85-usb; do cp "$build_dir/$helper" "$app_dir/Contents/Helpers/"; done
for library in libusb-1.0.0.dylib libssl.3.dylib libcrypto.3.dylib; do
    cp "$prefix/lib/$library" "$app_dir/Contents/Frameworks/"
    chmod u+w "$app_dir/Contents/Frameworks/$library"
    /usr/bin/install_name_tool -id "@rpath/$library" "$app_dir/Contents/Frameworks/$library"
done
for binary in "$app_dir/Contents/Helpers/"* "$app_dir/Contents/Frameworks/"*; do
    case "$binary" in */Frameworks/*) relative=@loader_path ;; *) relative=@executable_path/../Frameworks ;; esac
    for library in libusb-1.0.0.dylib libssl.3.dylib libcrypto.3.dylib; do
        /usr/bin/install_name_tool -change "$prefix/lib/$library" "$relative/$library" "$binary"
    done
done
mkdir -p "$app_dir/Contents/Resources/gutenprint"
cp -R "$prefix/share/gutenprint/5.3/xml" "$app_dir/Contents/Resources/gutenprint/"
for guide in USER-GUIDE document-lifecycle physical-acceptance-plan RELEASE release-acceptance macos27-ui-ux-audit workflow-state-tests; do
    cp "$project_dir/docs/$guide.md" "$app_dir/Contents/Resources/$guide.md"
done
cp "$project_dir/THIRD_PARTY.md" "$app_dir/Contents/Resources/Licenses/THIRD_PARTY.md"
cp "$project_dir/build-release-deps/work/gutenprint-5.3.5/COPYING" "$app_dir/Contents/Resources/Licenses/Gutenprint-COPYING"
cp "$project_dir/build-release-deps/work/libusb-1.0.30/COPYING" "$app_dir/Contents/Resources/Licenses/libusb-COPYING"
cp "$project_dir/build-release-deps/work/openssl-3.6.4/LICENSE.txt" "$app_dir/Contents/Resources/Licenses/OpenSSL-LICENSE.txt"
cp "$project_dir/build-release-deps/work/pappl-1.4.12/LICENSE" "$app_dir/Contents/Resources/Licenses/PAPPL-LICENSE"
cp "$project_dir/build-release-deps/work/pappl-1.4.12/NOTICE" "$app_dir/Contents/Resources/Licenses/PAPPL-NOTICE"
python3 "$project_dir/scripts/release-metadata.py" "$app_dir"
for binary in "$app_dir/Contents/Frameworks/"* "$app_dir/Contents/Helpers/"*; do
    sign_binary "$binary"
done
sign_binary "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"
python3 "$project_dir/scripts/audit-release.py" "$app_dir"
echo "Built: $app_dir (signing identity: $identity)"
