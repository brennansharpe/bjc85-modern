# Incremental preview in BJC-85 Scanner

The native app starts scans with `--live-preview`. After the existing decoder
commits a complete band across all colour planes, the helper appends new 90 dpi
RGB rows to `live-preview.rgb` in that scan's private capture directory. It
flushes those bytes before emitting a `scan_preview` JSON event containing
`width`, `height`, and cumulative `rows`. No scanner commands change.

Preview construction samples the first pixel in each `dpi / 90` block. It uses
the same device-corrected planes as the final image; black-and-white mode applies
the same threshold of 128. Pending channel data never appears. The file is bounded
to the requested area, about 2 MiB for the standard page, and is append-only.
It is optional: a preview write failure disables previews without invalidating
the raw capture or the final full-resolution PNGs. Image Capture's eSCL service
does not request this app-specific side channel.

The app reads only newly announced bytes on a serial background queue. A full-page
gray canvas holds the unscanned region; real rows replace it without changing
the page's size. Rotation applies to that entire canvas, including the unscanned
area, so a bottom-first page grows upwards. Queued frames carry a revision and
operation identity, preventing stale frames from replacing a completed image,
a new scan, or a more recent rotation choice. Successful completion replaces
the preview with the final PNG. Cancellation retains the partial view and raw
files, leaves Save disabled, and continues to use the existing stop command.

## Offline verification

- `tests/live_preview_test.py` replays six real captures through the same C
  publisher under AddressSanitizer/UndefinedBehaviorSanitizer. It compares preview
  pixels against independent Python decoding for colour at 90/180/360 dpi,
  grayscale, direct line art, and 360 dpi thresholded black-and-white.
- Synthetic captures verify that a single colour plane, or even all planes
  before band commitment, emits no frame; a cancelled or short page emits only
  its valid partial rows and remains incomplete.
- `tests/live_preview_test.swift` exercises the actual app renderer: partial
  canvas, rotation, incremental reads, incomplete files, invalid geometry,
  decreasing row counts, and immutable previously rendered frames.
- The existing seven C tests pass under sanitizers.

Run the preview checks after building `is12-preview-replay` in `build-asan`:

```sh
python3 tests/live_preview_test.py
xcrun swiftc -swift-version 5 -parse-as-library -framework CoreGraphics \
  app/LiveScanPreview.swift tests/live_preview_test.swift -o build/live-preview-tests
build/live-preview-tests
```

## Hardware and window verification — 2026-09-14

A complete 90 dpi colour scan delivered 61 incremental frames, beginning with
16 rows and ending at 972. Its final preview bytes exactly matched the saved
full-resolution PNG. Changing rotation during acquisition moved the captured
portion to the opposite end of the page.

A second scan in the final installed build verified that the entire page and
controls stay fitted within the window. Cancellation after 11 frames (176 rows)
retained the partial preview, disabled Save, retained the raw data, and sent
exactly one existing Q stop command. No completed PNG was produced. The test
sheets were blank, so these checks establish acquisition and display behaviour;
the real chart replays establish nonblank pixel correctness. Details are in
[`is12-live-preview-acceptance.json`](is12-live-preview-acceptance.json).
