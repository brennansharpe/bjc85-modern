# Hardening verification records

> This dated record describes the original verification run. Subsequent privacy
> derivatives/history cleanup and source-alpha checks are recorded in
> [publication readiness](../../publication-readiness.md). Original private
> captures are not required by `scripts/test-source-alpha.sh`.

Baseline: `software-milestone-2026-09-14` (clean checkout). Host: macOS 27.0 `26A428`, Xcode 27.0
`27A5237l`, SDK 27.0, ARM64/macOS 14.0 target, Swift 5. Source files remain
uncommitted for review; `source-sha256.json` identifies the tested source.

The following commands were run locally. No command in this verification set
installs a production service/queue, opens live USB or submits a real print job.
Python image comparisons require Pillow/pypdf and the existing private capture
fixtures. These fixtures were available on this Mac; a fresh checkout without
them cannot claim replay acceptance.

```sh
sh scripts/build-release.sh
sh scripts/test-swift.sh
sh scripts/test-hardening.sh
sh scripts/test-isolated-services.sh
sh scripts/benchmark-processing.sh
python3 tests/usb_lease_test.py
```

Separate sanitizer configuration used `build-hardening-asan`, CMake Debug,
macOS 14.0, `CMAKE_C_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer`
and `CMAKE_EXE_LINKER_FLAGS=-fsanitize=address,undefined`, with the existing
release dependency prefix. Built with CMake and ran CTest: 10/10 pass.
`BJC85_TEST_HELPER` selected that helper for `tests/replay_scans_test.py` and
`tests/bw_output_test.py`; `tests/live_preview_test.py` used its
`is12-preview-replay` executable. The export CLI was freshly compiled from
`tests/scan_export_cli.swift`, `app/ScanExport.swift` and `app/Localization.swift`,
then selected by `BJC85_TEST_EXPORTER` for `tests/export_formats_test.py`.

The complete isolation diagnostic command also ran successfully:

```sh
xcrun swiftc -swift-version 5 -D BJC85_TESTING -parse-as-library -typecheck \
  -warn-concurrency -strict-concurrency=complete -warnings-as-errors \
  -target arm64-apple-macos14.0 -module-cache-path build-hardening-tests/cache \
  -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  app/*.swift app/Models/*.swift app/UI/*.swift \
  src/DriverOutcome.swift src/SharedDeviceState.swift \
  src/FileIdentity.swift src/LocalServiceIdentity.swift
```

`concurrency-audit.txt` contains compiler diagnostics (empty on success).
`hardening-tests.txt` reports each controller/document boundary; `swift.txt`
contains seven existing suite results. The release build runs the native CTest
suite and bundle signature/dependency/architecture audit. `relocated-bundle.json`
records a separate copied-bundle audit with non-USB helper execution.

The full-size benchmark report preserves actual wall time, CPU time, memory
and main-loop heartbeat observations. It does not measure the unlocked
graphical application's event latency or VoiceOver. Pixel comparisons and
physical PDF dimensions are independent of those timing results.

The `ui/` directory contains five real **before** screenshots and actual **after**
captures with synthetic content. The user later unlocked the Mac and requested
the deferred checks. See [the unlocked check record](ui-checks.md) and
[UI audit](../../macos27-ui-ux-audit.md) for keyboard, native exports, appearance,
window sizes/display switching and explicit VoiceOver/Inspector limits.
`ui/manifest.json` records capture dimensions and hashes; capture pixels must not
be confused with logical window-point sizes. `ui-export-check.json` independently
verifies actual native-panel output and stable rendered page pixels across tint.
`unlocked-*.txt` logs are reruns after the graphical findings were fixed; earlier
engine/replay/benchmark records remain distinct and unchanged.
Development-only failed-build/debug logs were kept separately under ignored
`tmp/hardening-development-logs/`; they are not final acceptance evidence.

`source-privacy-audit.json` inventories tracked files and reachable history using
bounded patterns. Draft redacted historical evidence and hash provenance are
separate under ignored `tmp/redacted-evidence-macos27/`. Historical originals,
private captures and Git objects were not modified or uploaded. The test result
logs here can contain local paths; do not treat this verification directory as
a publication-ready source export.

Physical and signing gates remain open; see
[release acceptance](../../release-acceptance.md) and
[opt-in physical acceptance](../../physical-acceptance-plan.md).
