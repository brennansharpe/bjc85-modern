# Third-party components and research material

## Source-alpha publication boundary — 2026-09-14

No project-wide open-source licence has yet been granted. This concerns the
project-owned source, documentation and mockups only; third-party components
retain their own terms and required credits. No new licence is selected here.
The dated build and review records below are historical, not current clearance.
[Publication readiness](docs/publication-readiness.md) supersedes their release
and privacy status. The repository is now public source alpha. Residual historical-object retention
and an owner/support decision remain unresolved; public visibility is not
server-side erasure, legal clearance or a binary-release qualification.

The source repository contains original interoperability/application code,
protocol descriptions, metadata-only research provenance and bounded hardware
status/calibration fixtures. It does not vendor the dependency implementations,
Canon installers/manuals, extracted artwork/profiles/resource payloads or full
decompilation outputs. Local research originals remain outside public refs.
Static analysis informed interoperability work; no independently staffed
clean-room process or Canon endorsement is claimed.

The actual pinned dependency notices were inspected locally:

| Component | Current pin | Actual notices | Use |
| --- | --- | --- | --- |
| Gutenprint | 5.3.5 | `COPYING` (GPL v2) and `src/main/print-canon.c` (GPL v2 or later) | Unmodified, statically linked by local builds |
| PAPPL | 1.4.12 | `LICENSE` (Apache 2.0), `NOTICE` (optional embedding/GPLv2 exceptions and credits) | Unmodified, statically linked by local builds |
| libusb | 1.0.30 | `COPYING` (LGPL 2.1), core source notice (2.1 or later) | Unmodified, dynamically linked |
| OpenSSL | 3.6.4 | `LICENSE.txt` (Apache 2.0) | Unmodified, dynamically linked |

Source pins remain in `scripts/build-release-deps.sh`. The local build copies
upstream notices; no downloaded dependency tree or binary is committed by this
publication work. Apple's frameworks/CUPS and system zlib are platform inputs.
Research-only Canon inputs retain their original ownership; provenance hashes
and resource IDs do not grant redistribution rights to their payloads.

For a future combined binary, evaluate a GPLv3-compatible licensing route using
Gutenprint's "or later" option, with an explicit owner decision and a complete
component review. Apache 2.0 can be combined into GPLv3 works; do not describe
this linked distribution as GPL-2.0-only. See the
[Apache compatibility guidance](https://www.apache.org/licenses/GPL-compatibility)
and [GNU compatibility guide](https://www.gnu.org/licenses/quick-guide-gplv3.pdf).
Complete corresponding source/build materials, GPL notices, LGPL replacement
and relinking rights as applicable, Apache notices and modification notices are
pending binary-distribution work. Signing/notarization and physical acceptance
are also pending; no binary release is part of this source alpha.

## Repository privacy cleanup — 2026-09-14

The initial GitHub upload included private identifiers in the evidence and Git
metadata. The source tree and reachable history have since been sanitized; see
[the cleanup scope and verification](docs/REPOSITORY-PRIVACY.md). Earlier audit
records below describe the state before this cleanup. Sanitized evidence is a
derivative, and original local evidence must not be uploaded or merged back.
Dependency licensing and distribution obligations below still apply.

## Hardening and macOS 27 pass — 2026-09-14

This pass retains the dependency versions and source pins below. The new
`bjc85-job-query` helper uses Apple's system CUPS; it adds no bundled dependency.
No repository license was selected, signing credentials changed, or release
uploaded. Applicable distribution obligations remain an owner/release gate.

A read-only inventory inspected all 263 tracked files and 247 reachable blobs
across two commits. The known test printer identifier and local user paths are
present in current and historical evidence. Seven redacted draft evidence files
were created separately under `tmp/redacted-evidence-macos27/`, with source and
derivative SHA-256 hashes in `provenance.json`; originals and Git history were
left untouched. These are review derivatives, not a published/source-release
approval. `scripts/audit-source-privacy.py` now runs the broader repository check;
it is not an exhaustive secret or legal-compliance assessment. The historical
bounded audit is recorded in
`docs/verification/macos27-hardening/source-privacy-audit.json`.

Production eSCL discovery now uses a private, stable random installation UUID
instead of a hardcoded test serial/shared UUID. Local calibration validation
still uses the physical identity as required by the existing engine. Historical
research/discovery experiments are not part of the bundle. Canon installers,
artwork, decompilation outputs and private captures remain excluded from
distributable artifacts. That original history required privacy cleanup before
distribution; never reintroduce it from a backup or an older clone.

## Utility 0.2.0 release build — 2026-09-14

The new `dist/BJC-85 Utility.app` rebuilds its dependencies for ARM64/macOS 14.
It bundles libusb 1.0.30 and OpenSSL 3.6.4 dylibs with relative loader paths,
links Gutenprint 5.3.5 and PAPPL 1.4.12 statically, and copies their license
notices into `Contents/Resources/Licenses`. Gutenprint XML data is bundled too.
Apple CUPS, zlib and frameworks are provided by macOS. No Homebrew or repository
path is a runtime dependency of this staged bundle.

Reproducible source locations and SHA-256 pins are in
`scripts/build-release-deps.sh`. Additional release archive pins:

* libusb 1.0.30: `fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf`
* OpenSSL 3.6.4: `9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef`

OpenSSL 3.6.4 was selected from its
[official release](https://github.com/openssl/openssl/releases/tag/openssl-3.6.4)
instead of carrying the older Homebrew 3.6.3 into a newly rebuilt distribution.
The checksum-pinned original scanner/printer libraries remain unchanged.

This is an ad-hoc signed local milestone. Public distribution still requires
a compatible project license, complete corresponding source/build materials,
LGPL compliance, Developer ID signatures and notarization. No redistribution
permission for Canon binaries, resource payloads, artwork or profiles is claimed;
they are excluded from the bundle and prospective source releases.

The sections below preserve the original development dependency provenance.
Their Homebrew/workspace descriptions refer to the baseline prototype, not the
new release build.

## Gutenprint 5.3.5

Source: https://sourceforge.net/projects/gimp-print/files/gutenprint-5.3/5.3.5/

SHA-256: `f5a9f47de28530b1ae2069cfbc647a9a641baeeabe809bb0ef2b3ec5b9668d70`

The source and its `COPYING` and file-level notices are retained under
`artifacts/source/gutenprint-5.3.5/`. The Canon engine is GPL-2.0-or-later. The
native renderer statically links Gutenprint. Distribution must preserve the
applicable GPL source and notice obligations; a project-wide distribution
license and release package have not been selected or prepared. No upstream
source changes were needed for this ARM64 build. C17 was selected explicitly.
Upstream emits existing alignment/unused-code warnings; our targets build with
warnings treated as errors.

## libusb

The USB tool links native Homebrew libusb 1.0.30, under LGPL-2.1-or-later.
Source/project: https://github.com/libusb/libusb

The development binary refers to the Homebrew installation. A distributable app
will need a deliberate dependency-bundling and signing workflow.

## PAPPL 1.4.12 and IPP dependencies

Source: https://github.com/michaelrsweet/pappl/releases/tag/v1.4.12

SHA-256: `1684c4e06446e9f7d93a39729fa0ba56f07a4007560080fdad7d0e2076a3615f`

The release archive and source are preserved locally. PAPPL uses Apache-2.0
with optional exceptions recorded in its `NOTICE`; see that file and `LICENSE`.
Its unmodified ARM64 static library handles local IPP, Apple/PWG Raster input,
job tracking, and the local status pages. The application supplies an explicit
footer to avoid PAPPL 1.4.12's null-key localization crash and formats its own
log messages with standard `vsnprintf` before passing them to PAPPL.

The development service links the existing native Homebrew OpenSSL 3.6.3
(`openssl@3`, Apache-2.0), Apple's system CUPS/zlib, and Apple frameworks. It uses
loopback HTTP/IPP without TLS. PAPPL's optional JPEG/PNG libraries, generic libusb
backend, and PAM support were disabled. These dependencies and Gutenprint's GPL
requirements must be addressed in any future release packaging.

## Canon material

The original IS Scan 2.6 MacBinary, IS Scan 3.50 Windows installer, and IS-12
manual are preserved for local interoperability research. Their SHA-256 hashes
and retrieval details are in `artifacts/manifests/`. The software came from a
third-party mirror; matching filenames and internal Canon notices do not
independently authenticate the binaries. The manual came from Canon's server.

Original downloads are read-only. Extraction happens into separate directories.
Mac resource forks are preserved both from the outer MacBinary and as AppleDouble
files produced by `unar -k visible`. The Windows installer was opened as a ZIP
and its InstallShield cabinets unpacked with `unshield`; no Canon executable was
run. Canon binaries, disassemblies, extracted resources, and logos are not
included in the native runtime or a distributable package. This work is static
interoperability analysis, not a claim of independently staffed clean-room work.

## Local development tools installed during bring-up

Homebrew installed `pkgconf`, `unar`, and `unshield`. `unshield` pulled its
`openssl@4` dependency. Homebrew also refreshed its own portable Ruby during its
normal update. No existing printer queue or macOS driver was replaced.

Ghidra 12.1.3 and Adoptium Temurin JDK 21.0.12.1+1 were downloaded from their
official GitHub releases into `.tools/` for static scanner analysis. Both archive
SHA-256 values matched their official release metadata. Ghidra's decompiler was
built locally for `mac_arm_64`; both it and `java` are ARM64 Mach-O executables.
The toolchain is not part of the printer/scanner runtime. Ghidra's distribution
contains Apache-2.0 and separately identified third-party/GPL components; retain
its bundled license notices. Temurin carries its bundled OpenJDK licenses.
The manifest is recorded in `docs/protocol/is12-native-scan-manifest.json`.

The scanner application's `Contents/Frameworks` includes the existing native
Homebrew libusb library. Its LGPL COPYING and AUTHORS files are included under
`Contents/Resources/Licenses`. The helper's library reference is relative to the
bundle, and every embedded Mach-O is ad-hoc signed after packaging. This local
development build still relies on the workspace for scripts and saved data.
