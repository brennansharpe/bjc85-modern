# Canon BJC-85 / IS-12 Native Utility

Native ARM64 macOS printing and scanning, preserving the hardware-tested
PAPPL/Gutenprint and C/libusb engines. The modern AppKit utility adds Canon
preset concepts, crop/effects, guided calibration, copy transitions and shared
recovery protection. Original Canon software is research material only.

**Current status: software milestone, physical qualification deferred.** The
user is away from the printer, which contains the IS-12 and blank sheets. No
paper-moving operations were performed during this implementation. Full feature
parity is not complete; see [all 18 acceptance gates](docs/release-acceptance.md).

## Build

```sh
sh scripts/build-release.sh
sh scripts/package-pkg.sh
```

Outputs: `dist/BJC-85 Utility.app` and the unsigned review package. The app and
all bundled libraries target macOS 14 and ARM64. This local build is ad-hoc
signed; Developer ID signing, notarization and clean-machine acceptance are
pending. See [release instructions](docs/RELEASE.md). No installation, service
switching, or device command occurs as part of the build.

[User guide](docs/USER-GUIDE.md) · [Canon UI evidence map](docs/legacy-ui-map.md) ·
[Implemented layout wireframe](docs/mockups/scan-workspace.svg) ·
[Research provenance](research/manifests/provenance.json)

## Behaviour and limitations

* Typed readiness separates transport, replies, scanner identity and readiness.
  Wrong heads and warming states fail readiness. Existing references are checked
  for checksum, serial, head class and raw temperature before acquisition.
* Cancellation barriers prevent L/B/W commands after observed cancellation.
  Ambiguous writes never replay. Persistent recovery guards block new native
  operations across app/helper/service restart; process exit alone is not recovery.
* Scan workspace: presets, 90/180/360 dpi, colour/grayscale/thresholded B&W,
  full-page prescan, draggable and keyboard/numeric crop, rotation, zoom,
  deterministic brightness/contrast/sharpen/soften/despeckle/invert, PNG/TIFF/PDF.
* Copy retains the completed image through an explicitly confirmed IS-12 to
  BC-11e swap, with copies/paper/colour/brightness and reprint without rescanning.
  This new complete physical cycle has not yet been exercised.
* Printing uses the existing localhost IPP queue. Letter/A4, mono/colour,
  360 dpi, copies and mapped draft/normal/high quality are exposed. Media is
  plain paper and feed automatic. Advanced unmapped options stay unavailable.
* 200/300 dpi, Canon Text Enhanced, Canon colour matching/edge processing and
  native cleaning/deep-clean/alignment/ink-level commands are unavailable.
  [Resolution evidence](docs/protocol/is12-200-300dpi.md) records the uncertainty.
* English (Canada) string catalogue, locale-aware crop dimensions, standard
  AppKit controls and labelled keyboard-adjustable crop. Full VoiceOver and
  supported-OS runtime acceptance are still pending.
* Diagnostic retention defaults off. Successful app captures are removed after
  export; copy raw captures after retaining the copy image; eSCL captures after
  delivery (or 24-hour expiry if undelivered, checked hourly); raw print spool after safe completion. Ambiguous captures remain
  available for recovery. Existing research/baseline captures are untouched.

## Baseline and verification

Git tag `native-hardware-baseline-2026-09-14` (`native-hardware-baseline-2026-09-14`) freezes the previous
working source. Its [historical development guide](docs/DEVELOPMENT-BASELINE.md)
retains the original tool and URF-fixture commands.

Baseline physical evidence includes Letter colour printing, content-bearing
90/180 dpi colour scans, blank-sheet 360 dpi colour/grayscale/B&W, calibration,
live preview/cancel and ImageCaptureCore acquisition. Blank-sheet success does
not establish image quality. Black ink delivery remains a hardware problem.

New offline evidence is under `docs/verification/2026-09-14/`: native C regression
and sanitizer tests, independent scan pixel/live-preview/export comparisons,
Swift settings/state/crop/privacy/accessibility tests, isolated eSCL outcomes and
IPP dry runs, and a relocated bundle dependency audit. See the acceptance ledger
for exact evidence and pending work.

The architecture remains AppKit → service coordination → existing native helper;
Image Capture → localhost eSCL → the same scanner engine; Command-P → CUPS/IPP →
PAPPL → Gutenprint → the same exclusive USB transport. No Rosetta, kernel
extension, proprietary runtime or disabled platform protection is required.

[Third-party notices and distribution obligations](THIRD_PARTY.md)
