# Native IS-12 acquisition: hardware evidence

On September 13, 2026, this M1 Mac acquired both printed test charts directly
through the BJC-85's USB interface. It then measured a clean white sheet and
used the reconstructed Canon correction algorithm to acquire visibly corrected
charts at 90 and 180 dpi. All executable code in the acquisition and PNG path
is ARM64. The Canon DLLs were statically analysed, never executed.

## Completed acquisitions

| Capture | Reference download | Resolution / saved pixels | Received rows | Result |
|---|---|---|---|---|
| `is12-scan-001` | None | 90 dpi / 720 × 972 | 976 each | First printed chart; strong background cast |
| `is12-scan-002` | None | 90 dpi / 720 × 972 | 976 each | Second printed chart; same cast |
| `is12-calibration-001` | Measurement only | 12,337-byte reference | Not an image | Complete `S/c`, saved and checksummed |
| `is12-scan-003` | Rejected before download | 90 dpi requested | 0 | Cache check incorrectly treated mutable mode fields as identity; no feed |
| `is12-scan-004` | Plain-paper reference | 90 dpi / 720 × 972 | 976 each | Readable chart, white background, CMY patches |
| `is12-scan-005` | None | 180 dpi requested | 0 | Printer powered off; no USB commands sent |
| `is12-scan-006` | Same reference after power cycle | 180 dpi / 1440 × 1944 | 1952 each | Readable corrected chart; complete page |
| `is12-app-scan-360dpi` | Same reference through AppKit app | 360 dpi / 2880 × 3888 | 3888 each | Blank sheet; complete native page |
| `is12-scan-007` | Plain-paper reference | 90 dpi grayscale | Partial | Decoder initially assumed colour band height; stopped once with Q, recovered |
| `is12-scan-008` | Plain-paper reference | 90 dpi gray / 720 × 972 | K: 992 | Complete blank sheet; 32-row bands, clipped 20 rows |
| `is12-scan-009` | Plain-paper reference | 90 dpi gray cancellation | K: 32 | SIGINT after one band; Q accepted once; no completed PNG |
| `is12-calibration-002` | Measurement only | 12,337-byte reference | Not an image | New complete reference after cancellation, now selected by the app |
| `is12-scan-010` | New reference | 90 dpi one-bit / 720 × 972 | K: 992 | Complete blank sheet; MSB-first bit decoding verified |
| eSCL `502FE6CE…` | New reference | 90 dpi gray / 720 × 972 native | K: 992 | Apple ImageCaptureCore saved the requested cropped region |
| eSCL `A494DCDA…` | New reference through packaged helper | 360 dpi gray / 2880 × 3888 native | K: 3888 | Installed Apple scanning integration saved 2580 × 3642 PNG |
| `is12-scan-011` | New reference | 360 dpi direct packed one-bit | K: 3840 of 3888 | Device sent E after 30 × 128-row bands; rejected as incomplete, no PNG |
| `is12-scan-012` | New reference | 360 dpi full-page black-and-white / 2880 × 3888 | K: 3888 | Complete gray acquisition, native threshold 128, real one-bit PNG; competing USB client rejected |

Each successful 90/180 dpi chart capture contains 61 physical bands, an `S/E` end record,
equal complete RGB planes, and no implied zero padding. The 90 dpi mode returns
16 rows per band; the 180 dpi mode returns 32. The final whole band extends
past the requested height. The native decoder clips to the requested area,
following `BjsInfo!biReadImagePreCalc`, instead of misreporting the overscan as
image corruption. At 360 dpi colour, the hardware returned **48 rows per band**,
81 bands, and exactly the requested height. Grayscale has a different band height:
32 rows at 90 dpi. The decoder learns this from the first complete band, with
a bounded allocation, rather than assuming a colour-only resolution formula.
The 360 dpi grayscale capture returns 81 bands of 48 rows, exactly 3888.
Both native grayscale and one-bit data arrive in `S/K` records: eight-bit
samples are unchanged, while one-bit samples use MSB-first packing, 0 = black,
1 = white. This agrees with the original BJSDM DIB palette construction.

Native C + ImageIO PNG pixels match the independent Python record decoder
exactly for the completed colour, grayscale and one-bit captures, including
the app's 360 dpi capture and the 360 dpi grayscale service scan. The latest
ASAN replay matrix is in `is12-replay-acceptance.jsonl`.
There is no host whitening, contrast change, ICC transform, or generative image
processing in these files. The device applies the downloaded correction table.

The direct one-bit 360 dpi experiment (`is12-scan-011`) returned only 3840 rows,
although 3888 were requested and echoed in C. Its band height is 128 rows. The
end marker therefore does not establish a complete image: the native decoder
rejects it and the acquisition sends Q once. A trailing-band/paper-length
constraint is a hypothesis, not yet a proven explanation. The original holder
is unavailable, and no shorter-area qualification has been performed.

For full-page black-and-white output, the app and bridge now use `--mode bw`:
the proven grayscale acquisition followed by native one-bit packing at threshold
128. Original grayscale samples are retained. This explicit image operation is
recorded as `output_threshold` in acquisition logs; it does not pad missing data.
`is12-bw-output-acceptance.jsonl` validates the threshold boundary, bit packing,
180° rotation, full 360 dpi dimensions, and rejection of the short packed capture.
The real `is12-scan-012` acquisition then passed this path using the packaged
app helper. Its 11,197,440 grayscale bytes produced a complete 2880 × 3888
one-bit PNG. `is12-bw-hardware-acceptance.jsonl` records the completion, and
`is12-usb-contention-hardware.jsonl` confirms a second native USB client was
blocked before device access while this acquisition was in progress.

Deliverables are under `scans/2026-09-13/`. Raw USB bytes, reconstructed inner
records, and both native image orientations remain under `.state/is12-scan-*`.
Commands/status are retained in the corresponding JSONL files in this directory.
The [scan manifest](is12-native-scan-manifest.json) records hashes and acceptance.

## Image transaction

For the observed BJC-85 `s` command family:

1. Read selectors `R 00`, `R 01`, and `R 02`; require Canon's scanner-head checks.
2. For a reference download, read raw temperature with `R 03` and validate the cache.
3. Send `D 10 88 0c 78 divisor`, with divisor 4, 2, or 1 for 90, 180, or 360 dpi.
4. Send `C` with four big-endian u16 values: x = 0, y = 43, width = 2880,
   height = 3888. Coordinates use 360 dpi units. The y offset follows Canon's
   3 mm leading-margin calculation. The requested area is 8 × 10.8 inches.
5. When using a reference, send `T 01` and the selected transformed 2056-byte
   block. Wait for the successful status response before feeding paper.
6. Query status. If paper is not at the scan position, send `L` once and wait
   for the observed `20 00 00` → `10 00 00` transition.
7. Send `B` once. Warm-up status may precede the image records.
8. Assemble `S/R`, `S/G`, and `S/B` records, signed line advances, `S/P` bands,
   and `S/E` end of page. Preserve all incoming bytes before interpreting them.

For example the 90 dpi `D` wire request is `1b 28 73 06 00 44 10 88 0c 78 04`;
the 180 dpi request changes only the final byte to `02`. The area request is
`1b 28 73 09 00 43 00 00 00 2b 0b 40 0f 30`.

`ESC ! e` carries a **signed big-endian line advance**, not an error. Positive
values commit rows; negative values rewind the logical position between colour
planes. Errors are derived from the three-byte scanner status. Misclassifying
`e` as a vendor error would stop a valid scan at its first row.

The reference measurement/download sequence and exact arithmetic are in
[the calibration trace](is12-calibration-trace.md).

## Native commands and application

Pause the print queue and stop its service while the IS-12 is installed. The
application's Connect action checks for pending jobs, pauses the named queue,
stops the named service, enters scanner mode, and verifies the IS-12.

```sh
sh scripts/build-scanner-app.sh
open 'build/BJC-85 Scanner.app'
```

The AppKit application supports calibration, resolution selection, one-page
capture, progress, cancellation, rotation, and PNG/TIFF/PDF saving. Its local
development bundle is ad-hoc signed and contains native libusb. It still uses
this workspace for state and service scripts and is not a notarized release.
The local-only eSCL service also integrates with Apple's ImageCaptureCore;
see [its acceptance record](is12-imagecapture.md).

The equivalent terminal workflow is:

```sh
build/bjc85-is12 status --scanner-installed --enter-scanner-mode
build/bjc85-is12 calibrate --scanner-installed --plain-paper-reference .state/new-reference
# Load a document after the white sheet ejects:
build/bjc85-is12 scan --scanner-installed --dpi 180 --calibration .state/new-reference/reference.bin .state/new-scan
# Offline recovery, matching the acquisition's resolution:
build/bjc85-is12 image .state/new-scan/records.bin recovered.png --dpi 180 --rotate180
```

Directories and image files must be new. Captures are bounded to 64 MiB, with
30-minute total and 60-second data-idle limits (180 seconds during warm-up or
reference measurement). A partial or failed outgoing transfer is never retried.
When interrupting a known-intact acquisition, the original driver's `Q` stop
command is sent once and replies are drained for a bounded time. No USB reset
or automatic replay is used. `is12-scan-009` physically exercised cancellation;
the subsequent status check, calibration, and scans confirm recovery.

`--uncalibrated` means no `T` download for that operation. It does not clear a
table that may remain in the device. An image-record file alone cannot reveal
the correction state; the acquisition log establishes whether `T` was accepted.

## What these results establish

Both printing and colour scanning now work natively on the physical machine.
The white-paper correction removes the gross cast and broad shading visible
in the initial chart scans. Ordinary paper is not Canon's reference standard;
clipped highlights, residual banding, and absolute colour accuracy need further
validation. The photo targets do not establish calibrated colourimetry.

The user has no scanning holder. Loose plain-paper feeding succeeded in these
tests; that does not qualify photographs, fragile originals, or other media.
The remaining original-era work includes content-bearing acceptance of higher
resolutions and mono modes, additional legacy resolution/area options, image
controls, maintenance, broader print acceptance, and portable distribution.
The Device menu prepares printing after the physical cartridge swap, so a saved
scan can be printed through the normal queue. Image Capture registration and
real acquisition now succeed. The black ink-delivery fault remains physical.
