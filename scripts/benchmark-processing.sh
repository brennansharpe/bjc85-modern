#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$project_dir/build-hardening-tests"
mkdir -p "$out"
python3 "$project_dir/tests/make_synthetic_fixture.py" "$out/full-resolution.png"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos14.0 \
  -module-cache-path "$out/cache" -framework AppKit -framework ImageIO \
  "$project_dir/app/Models/ScanSettings.swift" "$project_dir/app/Localization.swift" \
  "$project_dir/app/ScanDocument.swift" "$project_dir/app/ScanExport.swift" "$project_dir/app/ScanProcessing.swift" "$project_dir/app/ImageProcessingService.swift" \
  "$project_dir/src/FileIdentity.swift" "$project_dir/tests/processing_worker_test.swift" -o "$out/processing-worker"
BJC85_OFFLINE_TEST=1 /usr/bin/time -l "$out/processing-worker" "$out/full-resolution.png"
