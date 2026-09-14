# IS-12: initial static evidence

## Acquired references

The Mac package `b11q_ukx.bin` and Windows `isscan_v350.exe` were downloaded from
HelpDrivers after the user approved its download-form submission. The downloads
are pinned in `artifacts/manifests/provenance.json`. No legacy program was run.

Canon's original [BJC-85 IS-12 manual](https://gdlp01.c-wss.com/gds/2/0900007432/01/BJC85_IS12_user_manual.pdf)
was obtained directly from its download server (109 PDF pages).

## Windows 3.50

The outer file is a PE32 self-extracting ZIP. Its payload contains InstallShield
cabinets across three disk directories. Copying `data1.hdr` and `data1.cab`
through `data4.cab` into one extraction directory allows native `unshield` to
unpack all 58 listed payload files. The package's Readme identifies Canon,
IS Scan 3.50, and BJC-85 compatibility, including standard bidirectional USB on
Windows 98/2000/Me/XP. This is evidence about the package's claims, not a
cryptographic authenticity check.

| Component | Observed role / evidence | Useful export RVA |
|---|---|---|
| `BjsUsb.dll` | USB port manager; imports `ReadFile`, `WriteFile`, `DeviceIoControl`, `CancelIo`; references SetupAPI device interface discovery | `BjsEnumPorts` 0x1040; `InitializePortManager` 0x1280 |
| `Bjshidrv.dll` | Hardware dispatcher; contains `IS-12`, `WHITE`, and the USB manager name | `ssd_Entry` 0xdc54 |
| `BJSDM.dll` | Named scanner operations and data management | `tdm_BjInitialize` 0x14a0; `tdm_BjScanStart` 0x16e0; `tdm_BjScanEnd` 0x1700 |
| `BjsCm.dll` | Application/TWAIN control and white-reference interface | `tcm_BjsWhiteBase` 0x1730; `tcm_GetImageMemXfer` 0x1ad0 |
| `BjsDc.dll` | Colour/image-processing branch; calls UCS colour transforms, not USB transport | `tdc_GetProcAddress` 0x1810 |
| `BjsInfo.dll` | Model tables, scanner-command selection, head checks and scan/calibration parameters | `biSetScannerCommandType` 0x1f20; `biIsScannerHeadValid` 0x2e30 |
| `BJScan.dll` | Scanner UI and image/progress callbacks | `tui_UIstart` 0xf200; `tui_TransportImage` 0xf280 |
| `BSIS12.PRF` | 29,912-byte ICC v2 scanner profile, RGB input / XYZ connection space; header identifies Canon IS-12 | N/A |
| `Bjscan2.ds` | TWAIN data source | Not yet traced |

Header/import/export listings and x86 disassembly produced by native
`xcrun llvm-objdump` are stored in the ignored local `artifacts/analysis/`
directory. These are static listings, not execution through a translator.

In `Bjshidrv.dll`, image base is `0x10000000`. The dispatcher at VA
`0x1000dc54` takes an operation argument and branches over values including
1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800,
0x1000, 0x2000, and 0x4000. Some branches invoke function pointers initialized
elsewhere. **These are host-side API selector values, not USB command bytes.**
Several paths are now traced in the linked wire notes; the complete dispatcher
and scan pipeline remain unfinished.

`BSIS12.PRF` has the standard `acsp` signature and a bounded, readable ICC tag
table (catalogued locally). This identifies a host colour-management reference;
it does not provide a freshly measured white-calibration scan or establish the
scanner command protocol. It remains proprietary research material.

The next trace should start at the named initialize/scan/white-base functions,
follow dispatcher and USB callbacks, then document complete control/bulk request
sequences with buffer lengths, response handling, and timeouts. The presence of
names or a constant in a DLL is insufficient evidence to transmit it.

## Macintosh 2.6

The outer package is MacBinary II containing a StuffIt 5 self-extractor named
`b111q_ukx.sea` (the embedded name has three `1` characters). Its data fork is
2,292,192 bytes, resource fork 103,349 bytes, type `APPL`, creator `aust`.
Both forks were retained separately as well as in the unchanged original.

`unar -k visible` recovered the `English/Installer` and `English/PPC` trees
with AppleDouble resource-fork companions. The inner `PPC/IS Scan file` does
not begin with a normal PEF header and `file` identifies it only as data. Its
resource map contains two `stmp` records and one `cmID` record. `CommonFile`
contains more records of the same kind. These observations suggest an additional
installer-specific container; its algorithm is not yet identified. A `PPC`
directory name alone does not verify the architecture of the hidden payload.

The actual scanner application's DLOG/DITL/MENU resources have **not** yet been
recovered. The local resource inventory describes installer/container records,
not a completed classic-UI reconstruction.

## Behavioural baseline and unresolved hardware inputs

The original Mac manual lists DTP colour, Photo, DTP grayscale, Text, FAX, OCR,
and Custom modes. It permits 90, 180, 200, 300, and 360 dpi in custom settings
(printed pages 70-74). Some final image processing can be host-side, so these
UI modes must not be assumed to map one-to-one onto sensor commands.

White-level calibration is required on first use and can be requested again
as conditions change; the manual describes loading the supplied calibration
sheet and waiting for its ejection (pages 18-20 and 83). The user reports that
this sheet and the scanning holder are unavailable. Both native print charts have
now been acquired successfully without a holder in the user-requested experiment.

Current status: native mode entry, identification and status are verified on the
installed IS-12. Its replies match the reconstructed `s` command framing and
Canon's BJC-85-specific head checks. The standard USB identity/status remained
unchanged across the cartridge swap; the scanner protocol supplies the additional
information. See [the wire reconstruction](is12-wire.md) and its linked byte log.
Native image capture and a plain-paper white-reference measurement are now
verified. See [the acquisition record](is12-acquisition.md) for the results and
remaining limits. No legacy executable was run. Ghidra and its JDK/decompiler
were built/run natively on ARM64 for static analysis of the original DLLs.
