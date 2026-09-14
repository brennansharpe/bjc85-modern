# Building and qualifying BJC-85 Utility 0.2.0

> Current source-alpha note (2026-09-14): this document describes future/local
> binary packaging. No binary is published by the source-alpha task. An optional
> project-wide licence has not been selected; third-party terms still apply.
> See [publication readiness](publication-readiness.md) and [THIRD_PARTY](../THIRD_PARTY.md)
> for the current source/binary boundary and unresolved publication gate.

This is a locally built feature milestone, not a qualified public release.
Use the [acceptance ledger](release-acceptance.md) for the remaining gates.
Normal application startup does not start a scan, feed paper or install services.

The macOS 27 hardening build was compiled using macOS 27.0 (`26A428`), Xcode 27.0
(`27A5237l`) and SDK 27.0, preserving ARM64/macOS 14.0 and Swift language mode 5.
Its native job-query helper brings the bundle to ten Mach-O binaries. No new
package installation, notarization or publication was performed. The current
[UI audit](macos27-ui-ux-audit.md) records real before/after fixture screenshots,
keyboard, appearance and adaptive-layout checks, with explicit limits for
VoiceOver and Accessibility Inspector automation.

## Build and package

Xcode command-line tools, CMake, pkg-config, make and Python 3 are build tools.
They are not runtime dependencies. An initial build downloads checksum-pinned
upstream sources and builds all dependencies for `arm64-apple-macos14.0`.

```sh
sh scripts/build-release.sh
sh scripts/package-pkg.sh
```

The output is `dist/BJC-85 Utility.app` and, without release identities,
`dist/BJC85-Utility-unsigned.pkg`. Building or packaging does not install either
artifact, replace the existing prototype or change launchd/CUPS services.
The package has no scripts that start printer operations.

The bundle contains the app, native scanner/eSCL/IPP/render/USB/job-query helpers,
libusb 1.0.30, OpenSSL 3.6.4, static PAPPL 1.4.12 and Gutenprint 5.3.5, Gutenprint
data, the user guide and license notices. `scripts/audit-release.py` verifies
ARM64, each Mach-O deployment target, system/relative library references,
signatures and exclusion of Canon binary/resource/profile formats.
Gutenprint's data path is derived from the running bundle.

`build-release-deps/` is reproducible local build storage. Archive hashes are
in `scripts/build-release-deps.sh`. A new build directory must be used if the
deployment target or dependency recipe changes. The original `.local` and
Homebrew libraries were unsuitable for a macOS 14 release and are not bundled.

## Signing and notarization

```sh
BJC85_SIGNING_IDENTITY='Developer ID Application: YOUR IDENTITY' sh scripts/build-release.sh
BJC85_INSTALLER_IDENTITY='Developer ID Installer: YOUR IDENTITY' sh scripts/package-pkg.sh
BJC85_NOTARY_PROFILE='EXISTING-KEYCHAIN-PROFILE' sh scripts/notarize.sh dist/BJC85-Utility.pkg
```

Every helper/library is signed before the app. Developer ID builds enable
hardened runtime. Local ad-hoc builds omit hardened runtime because ad-hoc
signatures have no Team ID for library validation; no platform setting is changed.
The notarization script rejects ad-hoc/development identities, submits through
notarytool, and staples and validates the resulting ticket. None of these release
credentials was available for this milestone; only ad-hoc signing was performed.
Do not disable SIP or Gatekeeper to claim release acceptance. Complete the
normal signed/notarized workflow and test the downloaded artifact on a clean Mac.

Gutenprint is statically linked. Before public distribution, select a compatible
project distribution license and supply complete corresponding source/build
instructions under the applicable licenses. The notices do not substitute for
those obligations. Canon research files must stay outside source releases too.

## Relocation, services and uninstall

Move the app to its intended location before using Connect or Switch to printing.
Those explicit actions write current-user LaunchAgents with the actual bundle
path and runtime directory. If the app is moved again, use the appropriate
confirmed connection action to regenerate service paths. No checkout is required.

Runtime state is under
`~/Library/Application Support/local.bjc85.utility/`. The app uses `.state/scanner-app`,
eSCL uses `.state/escl-jobs`, and printing uses `.state/print-spool`. The shared
`recovery-required.json` protects all native clients. Do not delete it as a
troubleshooting shortcut. An orphaned operation requires inspection and an
explicit recovery decision before its marker can be archived.

Editable documents are under `Documents/<UUID>` and follow the separate
[lifecycle policy](document-lifecycle.md). Outstanding print references restore
without resubmission. Discovery uses a private stable per-installation UUID;
the physical serial is still used locally for calibration validation but is
not the eSCL discovery identity. Services remain loopback-only.

Service transition admission prevents new native work during idle checks and
switching. An old installed eSCL bridge without `/utility/idle` fails quiescence
closed. Upgrade it only after confirming that the previous service is idle;
the app does not forcibly stop an unrecognized/active acquisition.

To uninstall when no job is active: quit the app; boot out and disable
`gui/$(id -u)/local.bjc85.native-scan` and `local.bjc85.native-print` with launchctl;
remove those two plist files from `~/Library/LaunchAgents`; remove only the
`BJC85_Native` CUPS queue after checking its URI is this utility's
`ipp://localhost:8631/ipp/print`; move the app to Trash. Preserve exports,
calibration references and recovery data. Delete the Application Support folder
only after reviewing those files. No kernel extension or system scanner driver
is installed. The .pkg receipt can be forgotten with pkgutil after uninstall;
its receipt identifier is available from `pkgutil --pkgs`.

## Offline and physical verification

Build C tests with AddressSanitizer/UndefinedBehaviorSanitizer, run CTest, then
run `scripts/test-swift.sh`. Existing pixel, export and live-preview tests accept
the new helper paths as documented in the acceptance ledger. eSCL tests use a
fake child, isolated ports and disabled advertisement. IPP tests require
`--dry-run` and an isolated spool. None of these requires printer access.

Compiler/link audits establish deployment metadata and SDK availability, not
execution on every OS. Runtime acceptance on macOS 14 and newer supported
versions, full VoiceOver, installation/uninstallation and notarization remain
separate release gates. Physical tests are postponed until the user explicitly
says they are ready; the printer currently contains the IS-12 and blank paper.
