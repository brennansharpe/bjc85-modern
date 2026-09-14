# Feature parity implementation

Brief: the final engineering prompt in the 49-page research handover supplied on
2026-09-14. Preserve working native engines; reconstruct documented Canon
behaviour with modern macOS UI. Reference originals remain private research.

Baseline: Git tag `native-hardware-baseline-2026-09-14`, commit `native-hardware-baseline-2026-09-14`.
Seven pre-existing CTest cases passed in a fresh `build-handover` directory.
Installed scanner app/service were running and were not rebuilt in place.

Work sequence:
1. Typed readiness, cancellation barriers, persistent shared recovery outcomes;
   reproduce defects with fake USB before fixing them.
2. Shared device coordinator, settings/preset models, scan workspace with crop,
   adjustments, guided calibration, copy workflow, print settings and utilities.
3. Reproducible Canon resource research and manual/resource-to-UI map. Unsupported
   200/300 dpi and unknown maintenance commands stay unavailable.
4. Relocatable app/helpers, private retention defaults, release build/sign/package
   tooling, localization, accessibility, offline integration verification.
5. Physical content-bearing scan/print/copy/maintenance qualification and signed,
   notarized release acceptance require evidence before claiming completion.

New regression tests first failed on the baseline: wrong-head status exited 0;
cancellation during final readiness still transmitted B. The tests execute real
CLI/acquisition code linked against a fake USB implementation and never touch USB.

The first macOS 14 link exposed prebuilt Gutenprint/PAPPL objects with deployment
target 27 and Homebrew libusb/OpenSSL with target 26. Release dependencies must be
rebuilt for 14; successfully compiling application code is insufficient.

The software milestone now builds as a relocatable ARM64/macOS 14 app with
checksum-pinned rebuilt dependencies. Wrong-head/cancel/recovery tests pass,
as do 12 physical-capture replays, live-preview/export checks, seven Swift suites,
isolated eSCL lifecycle/HTTP validation, and nine IPP dry-run checks. Runtime
relocation testing found and fixed the ad-hoc library-validation and Gutenprint
XML path issues. Physical work and final release credentials are deferred.

See release-acceptance.md for the full 18-gate status. Canon Text Enhanced,
200/300 dpi, advanced print options and native maintenance remain unavailable;
resource container extraction is incomplete. This milestone is not full parity.
