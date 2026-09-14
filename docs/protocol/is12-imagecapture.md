# Native Image Capture integration

Apple's installed ImageCaptureCore framework discovers the service named
**Canon BJC-85 IS-12 Native**, loads
`/System/Library/Image Capture/Devices/AirScanScanner.app`, opens it as an ADF,
and scans a real sheet through the project's native USB helper. This succeeds
without running any Canon executable, emulator, Rosetta process, replacement
system module, or kernel extension.

## Acceptance

`is12-imagecapture-discovery.jsonl` records discovery, an opened session, and a
ready document feeder. Early acquisition attempts exposed two implementation
problems: the client needed an explicitly selected ready feeder, and it needed
job status immediately after POST `/eSCL/ScanJobs`. A later full physical scan
completed, but its HTTP request had timed out; a retained stale socket lost
delivery. That capture remains in job `00000000-0000-4000-8000-000000000001`.

The corrected bridge starts the native acquisition once on POST, returns job
status while it runs, and responds promptly with HTTP 503 and `Retry-After: 1`
to `NextDocument` until the complete image exists. The client retries downloads
without causing another paper feed. A delivered single page is followed by 404
to end the one-page ADF job.

The actual successful Apple-framework acceptance is
[`is12-imagecapture-native-scan-004.jsonl`](is12-imagecapture-native-scan-004.jsonl):
ready feeder → request at 90 dpi → `scan_saved` → completion with no error.
The saved file is `scans/2026-09-13/imagecapture-native-gray-90dpi.png`.
Job `00000000-0000-4000-8000-000000000005` retains its settings, native raw
acquisition, and JPEG document. Apple requested 2150 × 3033 units of 1/300 inch,
so delivery is 645 × 910 pixels, cropped from the full 720 × 972 native capture.
The source was a blank sheet, so this acceptance establishes communication,
acquisition, transfer, and file saving; it does not measure grayscale contrast.

The installed, bundled service subsequently passed 360 dpi grayscale acquisition
and Apple-framework file saving in `is12-imagecapture-native-scan-005.jsonl`.
Job `00000000-0000-4000-8000-00000000000B` captured 2880 × 3888 grayscale
pixels, with 81 bands of 48 rows. Native ASAN decoding matches every independently
decoded pixel. Apple requested a smaller 2150 × 3035 region in 1/300-inch units,
and saved a 2580 × 3642 PNG. The packaged helper entered scanner mode and passed
head checks before acquisition, using the fresh reference automatically.

`is12-imagecapture-native-scan-006.jsonl` requested black-and-white with bit depth
1 through Apple's API and saved a result successfully. However, the eSCL request
in job `00000000-0000-4000-8000-00000000000A` specifies **Grayscale8**, and the
driver correctly acquired eight-bit data. This is another grayscale transport
acceptance, not proof of the IS-12's one-bit mode at 360 dpi. The dedicated app
now uses `--mode bw` for complete grayscale acquisition and native one-bit output.
The lower-level `--mode lineart` remains available for device-side packed-bit experiments.

The Mac was locked during framework testing. The **Image Capture application UI
itself has not been visually exercised**. The earlier AppKit 360 dpi colour
scan was initiated through its actual UI before the lock; native logs and
completed image files establish its acquisition result.

## Installed service and native components

The current-user LaunchAgent `local.bjc85.native-scan` runs the app's embedded
`is12-escl-bridge` and `bjc85-is12`. Both, the AppKit executable, and bundled
libusb are ARM64 and ad-hoc signed. System Foundation, Network, ImageIO,
CoreGraphics, ImageCaptureCore, and DNS-SD provide the rest of the scan path.

The service binds only to IPv4 loopback. DNSServiceRegister uses
`kDNSServiceInterfaceIndexLocalOnly`, with target `localhost.`. It is not a LAN
scanner advertisement. The native HTTP service requires a local Host header,
rejects Origin-bearing requests and unsupported Content-Type, forbids XML
DOCTYPE/external entities, bounds request sizes and scan areas, and permits only
supported simplex modes. These checks pass in
`is12-escl-http-acceptance-final.jsonl` without submitting a valid job.

For each new job the bridge enters scanner mode and verifies its head, then runs
the native acquisition with the latest reference from the app settings. Native
USB clients share an exclusive file lock; its contention and crash release are
tested in `is12-usb-lease-acceptance.jsonl`. Native cancellation sends Canon's Q
once and retains partial data. DELETE interrupts only the matching active child.

An immutable acquisition-started journal precedes device work. A terminal journal
records the child's outcome. An unclosed journal blocks service startup;
`is12-escl-recovery-acceptance.jsonl` verifies this before discovery or USB access.
No job is reloaded for automatic acquisition, and launchd KeepAlive is false.
All raw files remain available for offline recovery. Restart does not restore
an old HTTP download session; recover completed captures through the native CLI.

The scanner service is enabled across login while scanning is selected; the
print service is disabled. The app's Device menu switches these services after
the operator confirms the physical BC-11e swap. The print transition has not
been physically exercised while the IS-12 is installed.

## Scope and interoperability

The bridge advertises 90/180/360 dpi, RGB24, Grayscale8, and BlackAndWhite1,
simplex, and PNG/JPEG. It acquires one 8 × 10.8 inch sheet per job and crops on
the host to the requested region. Apple chooses JPEG transport in observed
requests; its saved PNG therefore contains a JPEG-decoded image. The native app
and native CLI preserve lossless pixel data. A blank-sheet scan cannot establish
geometry, orientation, or tonal fidelity of the Image Capture path.
The feeder status assumes an operator has loaded a sheet; the bridge does not
advertise hardware detection of a loaded stack. The native load operation
detects failure to acquire a sheet. Crop boundaries are rounded at both endpoints
so a valid region touching the page edge cannot exceed the acquired raster.

The app exports native PNG, TIFF, and PDF using the scanner's saved DPI. An
independent Pillow/pypdf check verifies every embedded pixel and PDF dimensions
for both chart resolutions and one-bit line art. TIFF preserves bit depth via
ImageIO's source-based export. See `is12-export-acceptance.jsonl`.

Primary references used for the implementation:

- [Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore)
  and the installed SDK's ICScannerDevice/ICScannerFunctionalUnits headers.
- Installed `dns_sd.h` documents LocalOnly registration semantics; Apple's
  AirScanScanner DeviceMatchingInfo.plist declares `_uscan._tcp.` matching.
- [OpenPrinting eSCL job status model](https://raw.githubusercontent.com/OpenPrinting/go-mfp/master/proto/escl/jobinfo.go)
  and [scanner status model](https://raw.githubusercontent.com/OpenPrinting/go-mfp/master/proto/escl/scannerstatus.go).
- [sane-airscan's eSCL client](https://raw.githubusercontent.com/alexpevzner/sane-airscan/master/airscan-escl.c)
  for request fields and the job/download sequence.
- [OpenPrinting ipp-usb discovery](https://raw.githubusercontent.com/OpenPrinting/ipp-usb/master/escl.go)
  for DNS-SD TXT field conventions.
