# Feature parity acceptance ledger — 2026-09-14

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
