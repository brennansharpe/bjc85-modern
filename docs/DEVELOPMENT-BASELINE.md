# Historical development instructions — baseline native-hardware-baseline-2026-09-14

These notes describe the previously installed prototype. For the new relocatable
Utility, use the current README and USER-GUIDE. Paths and retention behaviour
below are historical, preserved for reproducibility.

# Canon BJC-85 / IS-12 native macOS revival

Native ARM64 printing and IS-12 scanning on a modern Apple Silicon Mac, including
a macOS print queue, an AppKit scanner app, and local Image Capture integration.
Plain white paper supplies experimental shading correction. The core print and
scan paths work on the actual machine; full original-driver feature parity and
factory colour accuracy are not yet established.

For scanning, open **BJC-85 Scanner** from your personal Applications folder
(a shortcut to `build/BJC-85 Scanner.app`) or select **Canon BJC-85 IS-12
Native** in Image Capture. The local scanner login service is installed. Keep
the IS-12 installed for scanning. After replacing it with BC-11e, use the app's
**Device → Switch to printing…** command to resume the print queue.

## Current result

On September 13, 2026, this project built and ran on an Apple Silicon Mac with
macOS 27.0 (26A428) and Apple Clang 21. The native USB probe opened the actual
BJC-85, claimed its printer interface, read its IEEE-1284 identity, and queried
status. All 111,591 bytes of a Gutenprint monochrome test page reached the
printer. The user observed paper/head movement but a **blank page**; the installed
BC-11e cartridge expired approximately 14 years ago. A subsequent printer-generated
nozzle check produced cyan, magenta, and yellow patterns with no visible black.
This establishes a black ink-delivery problem independently of the native driver;
it does not distinguish an empty/dried tank from clogged or failed black nozzles.
The subsequent native colour test produced upright, readable text, cyan/magenta/
yellow patches, and visible fine lines. Its black control patch was blank.
The photographed ruler is consistent with a one-inch horizontal square edge;
precise two-axis measurements and full print-quality validation remain pending.

The PDF path rendered all 38 pages of the supplied handoff to a 9,572,037-byte
print stream on disk, without sending that document to the printer. Colour and
monochrome fixtures also rendered successfully. All 209,181 bytes of a colour
test with blue text and geometry marks were accepted in one uninterrupted
submission. The user's photograph confirms visible native colour printing.

The subsequent page sent through the **Canon BJC-85 Native** macOS queue also
printed correctly, as confirmed by the user. The complete path is macOS CUPS
and Apple Raster → native PAPPL adapter → Gutenprint → native libusb → BJC-85.
The queue is installed as `BJC85_Native`, backed by a local login service on
`ipp://localhost:8631/ipp/print`. It does not change the default printer.

The renderer, USB executable, IPP service, static Gutenprint/PAPPL libraries,
and libusb are ARM64.
No Rosetta, emulator, Windows program, or legacy Canon executable is used by the
print path. Canon packages are local research material only.

With the IS-12 installed, the native diagnostic entered scanner command mode and
received carrier, scanner-information, and status replies. The returned bytes
pass the BJC-85/IS-12 head checks reconstructed from Canon's driver. See the
[wire reconstruction and hardware log](docs/protocol/is12-wire.md).
Both printed test charts were subsequently scanned at 90 dpi: each acquisition
returned 976 rows in each RGB channel and a valid end-of-page record. Native C
decoding and Apple's ImageIO produce 720 × 972 PNGs, clipping four extra rows
from the final scanner band. The independent Python decoder matches every pixel.
The uncorrected scans have a strong cast and horizontal banding. A clean blank
sheet then produced the complete 12,337-byte white-reference measurement, and
the native program downloaded Canon's per-resolution correction. Corrected
charts at both 90 and 180 dpi have readable text, visible CMY patches, and a
white background. Native and independent decoding agree on every pixel.
See [the acquisition record](docs/protocol/is12-acquisition.md).

The user does not have Canon's white calibration sheet or scanning holder;
plain-paper reference results do not establish factory colour accuracy.
The native AppKit scanner application provides colour, grayscale, and one-bit
black-and-white modes; 90/180/360 dpi; calibration; progress and cancellation;
rotation; and PNG/TIFF/PDF saving. Colour 360 dpi and grayscale/black-and-white
90 dpi completed on the loaded blank sheets. A native cancellation test stopped
after one band and a subsequent calibration and scan succeeded.
The packaged app helper also completed full-page 360 dpi black-and-white output;
an attempted second native USB client was blocked during that real acquisition.

Full-page black-and-white output uses complete eight-bit grayscale acquisition
and a native threshold at 128, producing a genuine one-bit PNG. The scanner's
direct packed one-bit mode works at 90 dpi, but its 360 dpi test returned an
end record 48 rows short with this paper and was rejected. No missing rows are
filled in. Raw grayscale data is retained before thresholding.

Apple's **AirScanScanner** module discovered the local service, opened a session,
requested a real 90 dpi grayscale scan, and saved the downloaded PNG through
ImageCaptureCore. This is actual acquisition through Apple's framework; the
Image Capture application's GUI has not been checked because the Mac was locked.
See [the integration record](docs/protocol/is12-imagecapture.md).

**Current hardware state: IS-12 installed.** The print service is stopped and
`BJC85_Native` is paused for scanner testing. Restore the BC-11e before resuming
printing with the commands below.

## Print from macOS

Choose **Canon BJC-85 Native** in an application's Print dialog. Use Letter or
A4 plain paper and the BC-11e cartridge. The current prototype provides colour
or monochrome at 360 dpi, single-sided printing, and copies. Letter colour is
physically verified; A4, grayscale, multiple pages, and copies passed raster
tests without USB output and still need hardware acceptance.

**Black ink is currently unavailable.** Selecting Colour does not force black
content to use colour inks: ordinary black text can still be absent. The visible
test used blue text deliberately. This limitation is also present in the
printer's own nozzle check and requires attention to the ink tank/printhead.

The login service is `local.bjc85.native-print`; its settings, retained raw
jobs, and logs are private to this user under `.state/`. It listens only on
loopback and does not advertise or share the printer on the network. The local
status page is [http://localhost:8631/](http://localhost:8631/).

**Stop the service before rebuilding, using the direct USB sender, or replacing
the BC-11e with the IS-12.** Cartridge detection is not automatic. With the queue
idle, stop it using:

```sh
cupsdisable -r 'IS-12 scanner installed; resume only after restoring the BC-11e.' BJC85_Native
launchctl bootout "gui/$(id -u)/local.bjc85.native-print"
```

With the BC-11e installed again, use **Device → Switch to printing…** in the
scanner app, or restart it using:

```sh
sh scripts/resume-printing.sh --bc11e-installed
```

To remove this integration, stop it, remove that specific LaunchAgent plist,
and run `lpadmin -x BJC85_Native`. Retained research and spool files stay in the
project. No original queue or system driver needs to be removed.

## Build

Prerequisites: Xcode Command Line Tools (or Xcode), native Homebrew `cmake`,
`libusb`, `pkgconf`, and `openssl@3`. The existing machine already had CMake and libusb;
pkgconf was installed during bring-up. The archive tools `unar` and `unshield`
were also installed for static Canon package inspection.

```sh
sh scripts/build-gutenprint.sh
sh scripts/build-pappl.sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j 4
ctest --test-dir build --output-on-failure
```

Gutenprint 5.3.5 is checksum-pinned and installed under `.local/` in this
workspace. Build logs are under `build-gutenprint/`. The library uses this
absolute installation prefix for its XML data, so rebuild after moving the
project. The build does not install CUPS filters or replace system drivers.
PAPPL 1.4.12 is also checksum-pinned and built as an ARM64 static library. Its
optional JPEG/PNG decoding and USB backend are disabled; macOS rasterizes the
document and this project's transport owns USB delivery. OpenSSL 3.6.3 and the
system CUPS library are linked natively.

After building, install the local login service and queue with:

```sh
sh scripts/install-print-service.sh --prepare-only  # creates a reviewable plist
sh scripts/install-print-service.sh
```

This is a development installation tied to this workspace and its Homebrew
dependencies. Stop the service before moving or rebuilding the project.

## Use

### Scanner application

```sh
sh scripts/build-scanner-app.sh
open 'build/BJC-85 Scanner.app'
```

Install the IS-12 before choosing **Connect scanner**. The app checks for pending
print jobs, pauses `BJC85_Native`, disables its print service, enables the local
scanner service, and verifies scanner identity. Load a clean blank sheet for **Calibrate white sheet**, then load your
document and choose **Scan page**. A validated reference from this development
session is already available on this machine. **Sheet was fed bottom first**
rotates the preview and saved image without rescanning. **Save image…** supports
PNG, TIFF, and PDF; PDF retains physical scan dimensions.

The page preview now fills in as complete scan bands arrive. Unscanned areas are
gray, and rotation works during acquisition. The lightweight live view uses
90 dpi; completed scans and exports retain the selected resolution. Cancelling
keeps the partial view and capture files without enabling Save. See the
[live-preview implementation and checks](docs/protocol/is12-live-preview.md).

The development app, its helpers, and its bundled libusb are ARM64 and locally
ad-hoc signed. The scanner bundle has no runtime Homebrew-library dependency;
it still uses this workspace for settings and service scripts. Quit the app and
stop its service before rebuilding it. Its private logs, references, and captures are in
`.state/scanner-app/`; use **Show files** to inspect them. Printing stays paused
after closing the scanner: restore BC-11e before using the resume commands.

### Image Capture integration

The service `local.bjc85.native-scan` binds **127.0.0.1:8641** and publishes
`_uscan._tcp.` through Apple's **LocalOnly** DNS-SD interface. It is visible only
on this Mac. No system scanner module or kernel extension is installed.

```sh
sh scripts/install-scanner-service.sh --prepare-only
sh scripts/install-scanner-service.sh --scanner-installed
# Before rebuilding, or to turn off macOS scanner discovery:
sh scripts/install-scanner-service.sh --stop
```

Each scan job captures one physical sheet. Image Capture's paper-size selection
may crop within the driver's 8 × 10.8 inch region; the app saves the entire region.
Apple currently requests JPEG transport, then saves PNG; use the native app for
lossless capture and export. The service enters scanner mode, verifies the head,
and uses the latest saved white reference for every job. It never repeats an
acquisition in response to a download retry. Reference validation must pass
before paper feeds. Job settings, USB captures, and outputs are retained under
`.state/escl-jobs/` and may contain document content.

Stopping scanning disables its login service across logins; connecting in the app
enables it again. Printing and scanning have mutually exclusive login-service
settings. All native USB clients also share a kernel file lock, released on exit.
An interrupted service journal blocks startup until its physical/capture state
has been inspected. The service does not automatically restart after a crash.

### Command-line tools

Read-only device inspection and upstream model inventory:

```sh
build/bjc85-usb probe
build/bjc85-render capabilities
```

The probe opens the sole device matching the observed `04a9:1055` identifier.
It derives endpoints from descriptors and makes read-only standard/class
requests. It does not reset the printer, switch configuration, or detach a
kernel driver. Codex's command sandbox hides USB devices from libusb; the
hardware probe ran successfully with a sandbox exception, as the ordinary user.
This is not a requirement to disable macOS security.

With the IS-12 installed, and after pausing/stopping printing as described above:

```sh
build/bjc85-is12 plan                              # lists requests; no USB access
build/bjc85-is12 status --scanner-installed          # already in scanner mode
build/bjc85-is12 decode tests/fixtures/is12-extended-status.usb  # offline replay
```

Add `--enter-scanner-mode` to `status` when scanner mode needs to be entered.
The diagnostic queries head identity, scanner information, status, a raw
temperature value, and extended information. It records every USB byte and
handles fragmented replies. It does not feed paper or acquire an image.

To capture a loaded sheet, use a **new** output directory for each operation:

```sh
build/bjc85-is12 scan --scanner-installed --uncalibrated .state/my-scan
```

This captures an 8 × 10.8 inch region at 90 dpi and writes raw USB
and image records, `scan-raw.png`, and `scan-upright.png`. The upright version is
rotated 180° for the test charts, which were fed bottom first. Pixel values have
no host tone adjustment. `--uncalibrated` omits a correction download; it does
not guarantee that a previously downloaded device table has been cleared.

For a plain-paper calibration experiment, load a clean, blank white sheet:

```sh
build/bjc85-is12 calibrate --scanner-installed --plain-paper-reference .state/my-reference
# After the reference sheet ejects, load the document:
build/bjc85-is12 scan --scanner-installed --dpi 180 --calibration .state/my-reference/reference.bin .state/my-corrected-scan
```

The reference file is checksummed, bound to the printer's USB serial and Canon's
head-type checks, and accepted only within ±10 raw temperature units, matching
the original driver's cache selection. A replacement IS-12 needs a fresh
reference: this model does not expose a unique scanner-cartridge serial here.
These development commands preserve partial data and use bounded waits. They
never replay a partial paper-moving write or reset the USB device. Interrupting
an acquisition sends the traced `Q` stop command when the outgoing stream is
known to be intact. The physical grayscale cancellation test passed and a later
calibration and scan confirmed recovery without resetting USB.

Add `--mode gray` or `--mode bw` to `scan` and offline `image` for eight-bit
grayscale or one-bit output from grayscale. `bw` applies a native threshold of
128; the original samples remain in `records.bin` and can be replayed as `gray`.
`--mode lineart` selects the device's direct packed one-bit protocol for research.
That mode passed at 90 dpi but ended short at 360 dpi with the loaded paper.
Use the acquisition's resolution and encoding when replaying saved records.

Existing records can be decoded entirely natively without touching USB:

```sh
build/bjc85-is12 image .state/my-scan/records.bin recovered.png --rotate180 --dpi 90
```

Render to files, with one PNG preview per page:

```sh
build/bjc85-render test-page build/test-mono.bjc mono Letter
build/bjc85-render test-page build/test-color.bjc color A4
build/bjc85-render pdf input.pdf build/document.bjc mono Letter
```

The PDF command processes all pages, fits each page proportionally inside the
printable area, and respects PDF page rotation. It supports Letter or A4 plain
paper, automatic feed, 360 x 360 dpi, and monochrome or CMYK output. Password-
protected PDFs are rejected. Unsupported settings are not silently substituted.
The PNG previews show source content, not a simulation of final ink/dithering.
The colour test chart uses blue text and outlines, with separate cyan, magenta,
yellow, and black control patches, so its main marks remain visible if black
ink is unavailable.

Only after checking the preview, installing a working BC-11e, and loading paper:

```sh
build/bjc85-usb send build/test-mono.bjc --print-cartridge=bc11e --paper-loaded
```

This command physically prints. The two flags assert operator-observed cartridge
and paper state; they do not imply automatic cartridge detection. USB class
status cannot establish cartridge type or ink availability and can report a
benign status on printers unable to sense a condition. Only one program should
use the physical device at a time.

The sender handles short writes and one-second USB timeouts by advancing by
exactly the accepted byte count. It stops on disconnect/error or 60 seconds
without progress. It never restarts a partially accepted job automatically.
If interrupted, preserve the printed byte count and device state; do not blindly
submit the complete job again. USB acceptance alone does not confirm printing.
Jobs are currently limited to 64 MiB. The direct sender does not implement queued
cancellation or persistent recovery. The IPP adapter checks cancellation during
rendering and between USB transfers and persists printer settings/job history.
It writes a recovery marker before USB output and blocks new transfers after a
crash or a known partial failure. A partial failure also pauses its internal
printer. Preserve the marker, byte count, raw job and printer state for inspection;
do not replay a job or delete the marker blindly. Paper already accepted by the
printer may continue printing after a cancel. Physical cancellation, disconnect,
and sleep/wake behaviour still need hardware validation.

Raw `.bjc` jobs are retained for development and recovery, even after completion.
They may contain document content and are not automatically pruned. Completed
jobs can be removed from the private spool when no recovery is outstanding.

## Evidence and next work

- [Bring-up report](docs/bringup-2026-09-13.md): results, hardware limits, and next experiments.
- [USB baseline](docs/protocol/usb-bc11e-baseline.json): actual descriptors and identity.
- [Scanner analysis](docs/protocol/is12-analysis.md): extracted components and trace targets.
- [IS-12 wire protocol](docs/protocol/is12-wire.md): reconstructed requests and actual scanner replies.
- [Acquisition and calibration](docs/protocol/is12-acquisition.md): real scan evidence, wire records, native commands, and remaining work.
- [Calibration trace](docs/protocol/is12-calibration-trace.md): original driver addresses and correction-table processing.
- [Image Capture integration](docs/protocol/is12-imagecapture.md): native Apple-framework acceptance and service operation.
- [Source provenance](artifacts/manifests/provenance.json): acquired bytes, origins, sizes, hashes.
- [Third-party components](THIRD_PARTY.md): dependency and research-material boundaries.

Remaining work includes content-bearing higher-resolution/mode acceptance,
preview selection and image controls beyond the OS tools, additional legacy
resolution/media modes, maintenance, portable distribution/notarization, and
a visible monochrome print with working black ink. Saved scans can be printed
through the normal macOS queue after the cartridge swap.
The original Mac workflow remains the feature target. Experimental paper
correction does not establish Canon-reference colour accuracy or full parity.
