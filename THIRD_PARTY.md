# Third-party components and research material

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
