# Release acceptance ledger — hardening / macOS 27 — 2026-09-14

## Current implementation status

**Implemented; release acceptance remains open.** Review baseline and initial
clean HEAD were `software-milestone-2026-09-14`. No checkout reset, dependency upgrade, history rewrite,
publication, installation, production service change or physical operation was
performed. The new `dist/BJC-85 Utility.app` is a separate ad-hoc local build.
The original ARM64 USB, IS-12, PAPPL/Gutenprint and eSCL architecture is retained.

The app now retains immutable masters and revisioned edits across exports,
printing and restoration; rejects managed-path/alias exports; separates Copy
attempts and retryable preflight; serializes native admission across service
transitions; processes immutable full-resolution snapshots off-main; queries
specific CUPS jobs without treating disappearance as success; and uses a native
sidebar/canvas/inspector with shared status and separate Settings.

| Verification actually run | Result and evidence in `verification/macos27-hardening/` |
|---|---|
| Baseline before edits | 10 CTest and seven Swift suites passed (`baseline-c.txt`, `baseline-swift.txt`) |
| Release build and bundle audit | Pass; ARM64, minimum macOS 14, ten Mach-O binaries, system/relative libraries, ad-hoc signatures, asset exclusions and non-USB helper execution (`release-build.txt`) |
| ASAN/UBSAN native tests | 10/10 pass, including wrong-head readiness, cancellation races and persistent recovery (`sanitizers.txt`) |
| Existing Swift regression | Seven suites pass, including constructed accessibility checks (`swift.txt`) |
| New controller/document/service tests | Four executables pass; Copy refusal/retry, canceled swap, corrected settings, stale callbacks, immutable acquisition facts, canceled job versus unsafe device state, restart/no replay, storage collisions and pipeline (`hardening-tests.txt`) |
| Image contract | 48 asymmetric 2D filter/rotation/mode crop-edge combinations pass; PNG pixels, DPI/PDF size, multiformat retention, failed/canceled export and aliases covered by document tests |
| Historical scan replay | 12 capture replays pass independent pixel comparison; no new acquisition (`scan-replay.jsonl`) |
| Live-preview/B&W replay | Six modes plus partial stream and one-bit boundary/short-stream checks pass (`live-preview.jsonl`, `bw-output.jsonl`) |
| Existing export regression | 12 PNG/TIFF/PDF cases pass independent pixel and physical-size checks; one-bit PNG/TIFF retained (`export-formats.jsonl`) |
| Isolated services | Fake-child eSCL outcome/HTTP/startup-recovery tests and nine PAPPL dry-run checks pass (`isolated-services.txt`) |
| Native lease isolation | Three real-helper tests pass using private lock/state paths and an offline libusb guard (`usb-lease.jsonl`) |
| Swift isolation audit | Swift 5 complete strict-concurrency diagnostics and warnings-as-errors typecheck passes (`concurrency-audit.txt` and command record) |
| Full-size worker measurement | 2880 × 3888 nonblank fixture: sharpen + TIFF 0.728 s; despeckle 0.668 s; peak RSS 295,321,600 bytes; maximum command-line main-loop heartbeat gap 23.179 ms (`performance.txt`) |
| Privacy/history inventory | 263 tracked files and 247 reachable blobs across two commits audited by bounded patterns; eight current files/eight historical blobs flagged; seven draft redacted derivatives with hashes/provenance, originals preserved (`source-privacy-audit.json`) |
| Graphical evidence | Five baseline and real after screenshots: all workspaces, Settings, multiple exports, errors/recovery, keyboard focus, Dark Mode, minimum/default/large/tiled sizes and display switching. Native-panel exports and later edits/restoration passed. See `ui-checks.md`; no generated-image substitute |
| Accessibility limits | Keyboard and direct AX checks completed. Native Inspector audit invocation was inconclusive; VoiceOver feedback/launch failed. Full spoken accessibility acceptance remains open, not passed |

The one-bit crop encoder and a macOS `/var` versus `/private/var` path-alias
regression were found and fixed by the new tests. Source renders at full
resolution; the measured heartbeat is not a full graphical responsiveness test.
The build is not proof of HIG compliance or working physical output.

Contracts and evidence: [document lifecycle](document-lifecycle.md),
[controller tests](workflow-state-tests.md), [macOS 27 UI audit](macos27-ui-ux-audit.md),
[updated guide](USER-GUIDE.md), [feature map](legacy-ui-map.md).

Open conditions: conclusive VoiceOver/Inspector acceptance, actual display removal,
additional scaling/translation cases; physical content-bearing acquisition,
calibration, prescan/reload, Copy/swap/
reprint, Command-P, Image Capture, cancel/disconnect and sleep/wake remain opt-in.
See [the separate physical plan](physical-acceptance-plan.md). Runtime on macOS
14–26, installed-service upgrade (older eSCL lacks the new idle handshake),
clean install/uninstall, signed/notarized distribution and owner's licensing/
source-release decision are unqualified. Private history must not be published
as-is. No recovery protection was relaxed to enable a demonstration.

## Historical milestone record at software-milestone-2026-09-14

The sections below preserve the previous acceptance record and its dates. Its
UI observations, package audit and nine-binary count refer to that earlier
build, not the current ten-binary hardening build. Current document retention
and screenshot status are defined above.

**Phase not complete.** This software milestone is ready for review and offline
use. Physical printer work is explicitly deferred until the user says to resume.
The IS-12 and blank sheets are currently installed. No device commands, service
transitions, calibration, feed, scan or print were executed in this implementation
session. The previously installed app and scanner service were preserved.

## Required gates from the supplied handover

| # | Requirement | Evidence / status |
|---|---|---|
| 1 | 90/180/360 content-bearing scan acceptance | **Pending physical qualification.** Baseline 90/180 colour charts pass; 360 and most mono evidence is blank-sheet transport only. Twelve existing captures replay identically. |
| 2 | 200/300 validated or explicitly unsupported | **Documented unsupported.** [Evidence](protocol/is12-200-300dpi.md); disabled settings, preset and eSCL gates. |
| 3 | Prescan/crop source coordinates | **Implemented and offline tested.** Rounded source edges, rotation and threshold/export tests. Actual mouse drag and Shift-arrow movement observed on the new offline UI. Physical prescan/reload/final-scan cycle pending. |
| 4 | Original scan presets represented | **Implemented with declared limitations.** Canon Macintosh manual 70–72; FAX/OCR disabled, Canon matching/edge differences disclosed. |
| 5 | First-class calibration | **Implemented; new physical UI flow pending.** Guided sheet, saved date, experimental-paper type, current serial/head/checksum/temperature validity; fake-reference tests pass. Native calibration baseline preserved. |
| 6 | Copy → swap → print → reprint | **Implemented; physical acceptance pending.** State tests retain the same image across restart; user-confirmed swap and queue checks. No automatic hardware transition. |
| 7 | Normal Command-P | **Baseline physical pass; new installation acceptance pending.** New bundled PAPPL/Gutenprint passes isolated raster, copy accounting and restart dry runs. |
| 8 | Image Capture acquisition | **Baseline framework pass; new installed service pending.** New bundled eSCL passes HTTP/fake-child lifecycle tests. No new Apple-framework physical acquisition. |
| 9 | Nozzle check/cleaning paths | **Open.** Built-in nozzle test baseline has CMY, no black. Native maintenance wire commands remain unqualified and unavailable. Guidance is not command implementation. |
| 10 | Wrong-head readiness | **Offline pass.** Real CLI + fake USB rejects valid replies with a wrong head or warming state; no L/B. |
| 11 | Cancel before B | **Offline pass.** Cancellation during D/C/final ready/L; motion barriers and ambiguous partial writes, including Q, exercised. |
| 12 | Ambiguity → recoveryRequired | **Offline pass.** Persistent common guard before USB, malformed marker rejection, fake eSCL ambiguity/missing receipt, restart blocks, and safe successful reuse. Direct scan also preserves a pre-existing recovery outcome. |
| 13 | No checkout/Homebrew runtime dependency | **Bundle audit and relocation pass.** All nine Mach-O files ARM64/minimum 14.0; relative/system dylibs; moved bundle performs native image replay, model lookup and eSCL validation. New app services require user-triggered installation acceptance. |
| 14 | Document temporary retention | **Implemented/offline pass.** Default off, safe-export cleanup, eSCL delivery/24-hour expiry cleanup and explicit retention override tested. Raw print purge is implemented after a safe physical transfer; dry runs deliberately retain fixtures. |
| 15 | Signing/notarization | **Open.** Ad-hoc local app and unsigned package only. Developer ID Application/Installer and notary profile not available. Release scripts support them; no platform protection was disabled. |
| 16 | Full UI VoiceOver/keyboard | **Partial.** Constructed views expose labels/values/focus; real mouse/Shift-arrow crop observed. Final AX canvas element fix passes source-view tests. Mac subsequently locked; full VoiceOver, all tabs and physical-dialog keyboard flows pending. |
| 17 | Historical feature evidence map | **Delivered with explicit unknowns.** [Map](legacy-ui-map.md) cites the manual, handover, source and genuine installer resources. Actual IS Scan application resources remain inside unresolved containers; missing printer/Copy Utility archives are not invented. |
| 18 | Canon material excluded | **Bundle audit pass.** Original archives/resources/profiles remain ignored research; native runtime contains none. No proprietary code was executed. |

Additional incomplete parity: advanced print cartridge/media/feed/halftone,
ColorSync/profile/gamma/CMY balance/density/user-preset controls; Canon-specific
Text Enhanced/matching/edge processing; full Classic application resource
extraction; clean install/uninstall and runtime tests across macOS 14–27.
No enabled control is presented for these unmapped features.

## New verification records

All paths below are relative to `docs/verification/2026-09-14/`.

| Record | What it establishes |
|---|---|
| `c-sanitizers.txt` | 10 CTest cases pass with ASAN/UBSAN; native code built with warnings as errors. |
| `scan-replay.jsonl` | 12 retained physical captures decode to identical independent and baseline pixels; no new acquisition. |
| `live-preview.jsonl`, `swift-live-preview.txt` | Six capture modes plus partial-stream bounds; actual Swift incremental renderer. |
| `bw-output.jsonl` | Threshold boundary/packed bits and short direct-one-bit rejection. |
| `export-formats.jsonl` | 12 native PNG/TIFF/PDF exports independently verify pixels, bit depth and physical dimensions. |
| `swift-models-ui.txt` | Seven suites: presets, coordinator, copy, IPP mapping, privacy, crop/effects, constructed accessibility. |
| `escl-unclosed-journal.jsonl` | The original interrupted-startup test also passes against the new bundled bridge. |
| `escl-outcomes.jsonl` | Wrong head, invalid reference, ambiguity, missing receipt, successful cleanup, retention override. Fake child only. |
| `escl-http.jsonl` | Seven HTTP validation cases against a relocated bridge on an isolated port and non-USB fake helper. |
| `ipp-dry-run.txt` | Nine checks: capabilities, Letter colour, four A4 gray pages × two copies, accounting, rejected settings, restart and recovery. `--dry-run` only. |
| `package-audit.json` | All 345 expanded package files match the staged app, including modes and signatures. Package is unsigned and was not installed. Nonfatal productbuild write warnings are recorded. |
| `relocated-bundle.json` | Architectures, deployment minimums, dylib paths, signatures, artifact exclusions and offline helper starts after relocation. |

The first relocation attempt exposed hardened ad-hoc library-validation failure;
local ad-hoc builds now omit hardened runtime, while Developer ID builds retain
it. A second loader check caught the Gutenprint XML directory level; runtime
lookup now selects bundled `gutenprint/xml`. The release audit executes model
lookup and the non-USB plan command to catch both regressions.

The layout deliverable is a [labelled SVG wireframe](mockups/scan-workspace.svg)
of the implemented AppKit screen. An offline preview was visually inspected,
but no captured screenshot was saved before the Mac locked. The wireframe is
not a screenshot or a claim of current physical readiness.

## Reproducing checks

`sh scripts/build-release.sh` runs release CTest and the bundle audit.
`sh scripts/test-swift.sh` runs the seven native Swift suites. Build a separate
CMake Debug directory with `-fsanitize=address,undefined -fno-omit-frame-pointer`
and link with `-fsanitize=address,undefined` for the sanitizer tests.

Set `BJC85_TEST_HELPER` to the chosen native helper for
`tests/replay_scans_test.py` and `tests/bw_output_test.py`;
`tests/live_preview_test.py BUILD/is12-preview-replay` accepts a replay executable.
The Python pixel/export tests require Pillow/pypdf and retained baseline captures.
`BJC85_TEST_EXPORTER` selects a freshly compiled `tests/scan_export_cli.swift` with
`app/ScanExport.swift` and `app/Localization.swift`.

`python3 tests/escl_recovery_state_test.py PATH/TO/is12-escl-bridge` creates its
own runtime and fake driver. `python3 tests/ipp_dry_run_test.py PATH/TO/bjc85-ipp`
uses the historical URF fixtures in `build/` and starts only isolated dry runs.
Do not run hardware scripts as substitutes for these tests while access is deferred.

## Physical work, last and only on explicit resumption

1. Confirm mechanical/media condition and status/reference validity without
   inferring readiness from blank paper in the tray. Record a content target.
2. Qualify colour, grayscale and B&W at supported resolutions, prescan/reload,
   crop/export, calibration and safe cancellation with retained journals.
3. Recheck Image Capture and normal Command-P using the newly installed bundle.
4. Perform the confirmed cartridge swap, Copy, multiple copies, reprint and Reset.
5. Investigate black ink delivery. Qualify maintenance only after protocol
   evidence and offline fixtures exist. Finish VoiceOver and release installation
   testing, then sign/notarize with actual release credentials.
