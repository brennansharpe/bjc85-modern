# BJC-85 Utility user guide

An independent native Mac utility for the Canon BJC-85 / IS-12. No Canon
endorsement is implied. Real fixture screenshots, keyboard and adaptive-layout
checks are recorded in the UI audit. Physical, full VoiceOver and notarized-release
qualification remain open. Building the app does not
replace the installed prototype or change services.

## Your document

The page stays visible while you move between Scan, Print, Copy and Device.
Use the toolbar or View menu to collapse the sidebar/inspector, Fit Page, view
100%, zoom or rotate. At 100%, one image pixel maps to one display pixel; use
scrolling/arrow keys to pan when the page is larger than the canvas.

File → Open Image accepts PNG, TIFF, JPEG and one-page PDF without a scanner
connection. PDF import is labelled as 360 dpi rasterization. The utility retains
a lossless master and saves edits separately. Importing JPEG cannot recover
information already lost in the original file.

Command-S opens Export. Choose PNG, TIFF or PDF and an external destination.
Export preserves the editable document: export another format, change crop or
adjustments, or print the same page. Exports preserve acquisition DPI and PDF
physical size. Saving inside the utility's private runtime, including through a
symlink or hard-link alias, is rejected to protect managed files. A failed or
canceled export keeps the source and the previous good output.

The document footer shows its revision, export state and selection dimensions.
Edits after export need another export. Undo/Redo restores edits without changing
the master. File → Close or New Document retains the document in File → Retained
Documents; neither action feeds paper. Discard requires explicit confirmation
and cannot delete a Copy-owned or currently processed document. Closing the
window or quitting leaves the active document restorable on next launch.
Command-W in Settings closes Settings while keeping the document open.
Restoration never resumes physical jobs. See [document lifecycle](document-lifecycle.md)
for storage limits, migration and crash behavior.

## Scan

Device → Connect Scanner prepares the utility's named services and checks the
IS-12. It refuses busy/uncertain device transitions and checks the owned queue.
A wrong head or warming response is not ready. Normal startup never connects,
calibrates, scans or feeds paper. An older installed scanner service without the
new idle handshake may refuse switching until deliberately upgraded while idle.

Import White Reference accepts an existing native `reference.bin` into private
storage. Connect validates checksum, printer identity, head class and raw
temperature. The printer's USB serial does not identify an individual IS-12
cartridge; changing scanner cartridges requires a fresh reference.
White-Level Calibration guides an experimental ordinary white-sheet measurement.
It does not claim the optical standard or color accuracy of Canon's reference
sheet. The helper rechecks validity before correction download/feed.

Choose a preset, output mode and supported resolution. Photo uses color at
360 dpi; DTP Colour uses 180 dpi with grayscale prescan. Text offers host B&W
thresholding and discloses the unavailable Canon edge processing. FAX/OCR,
Text Enhanced and unverified 200/300 dpi remain unavailable without substitution.
Output mode/adjustments also apply to the current document; resolution is for
the next acquisition and does not rewrite an existing scan's DPI.

Prescan acquires one full page at 90 dpi and ejects it. Before final Scan, reload
the same original in the same orientation. The confirmation sheet explains this
second pass. Fixed acquired area is 8 × 10.8 inches; a selected region is host
cropping, never a claim of hardware-limited acquisition. Drag a selection, use
arrows/Shift-arrows in Fit mode, or View → Crop Dimensions for numeric inches.
Corners resize the crop. Clear Selection restores the page. Rotation rotates
the page and selected coordinates together.

Brightness, contrast, inversion, sharpen, soften, despeckle and thresholding are
explicit host processing. Orientation and full-page filters precede cropping,
so completed preview, exports, Copy and Print use the same edge pixels. Final
processing runs on a background worker at full resolution. Live acquisition
preview is provisional and labelled “final host adjustments pending.” The
previous document stays retained during the new scan.

## Print and Copy

The Print workspace offers Letter/A4, copies 1–999, color/monochrome and
draft/normal/high quality at 360 dpi. Plain paper and automatic feed are fixed.
Unsupported settings show an inline error. These are per-document settings;
other applications retain their normal Command-P dialogs and native queue.
Advanced cartridge/media/halftone/profile/balance options are not enabled.

Copy progresses through acquire, review/edit retained document, confirm print
cartridge, then **Print retained copy**. Correct invalid settings and the Print
action becomes available again when the device is ready. After queue completion,
**Reprint retained copy** uses the same document and current settings without
another scan. Copy Reset releases its session but keeps the editable document
in Retained Documents; it is blocked during active/unknown/recovery states.

The BJC-85 cannot print with the IS-12 installed. Prepare Printing explains the
BC-11e cartridge change. Opening the sheet changes no state. Cancel with no
physical change preserves prior readiness; choose “Changed cartridge / unsure”
if a change occurred and revalidate before continuing. Confirmation prepares
services, then leaves a deliberate Print action. It does not submit automatically.
Canceling or rejecting preflight retains the image for a later attempt.

Specific destination/job ID, queue outcome and reasons appear in Print. Recheck
Job Status or Open Queue Details provides follow-up. Completed, canceled,
aborted/rejected and unknown are distinct. Unknown/missing history blocks
resubmission; restart reconciles without replay. Queue completion means the
queue reports completion, not that ink is visible. Inspect the page. The known
black-ink delivery fault is a separate hardware issue.

Image Capture uses the same native engine through local eSCL/AirScan. One loaded
sheet is acquired per job. Device transitions refuse another client's active
job instead of stopping it. Do not switch device use while a job is active.

## Cancellation, recovery and privacy

The top of every workspace shows device state, operation and cancellation.
An observed busy lease is labelled as the last availability check, without
changing scanner readiness or claiming the device disconnected. It is not a
reservation; native admission and USB locks remain authoritative.
Measured preview rows show progress; warming, processing and service work show
activity without invented completion percentages. Command-period cancels the
current acquisition or tracked pending print job. Cancel Export is separate.

The helper prevents new motion after cancellation and accepts only a complete
safe stopping response. Ambiguous writes, disconnects or unknown physical
outcomes leave persistent Recovery Required. Restart, Copy Reset and queue
completion cannot clear it. Preserve the capture, inspect the physical printer
and make an explicit recovery decision; there is no force-continue button.

Settings (Command-comma) contains Retain Diagnostic Captures, default Off.
Safely completed raw/image/log captures can be removed once the document master
has been retained. Delete Completed Diagnostics preserves document masters,
unexported edits, active workers, retained Copy and recovery evidence. Legacy
captures without an import receipt remain protected. Existing research/test
evidence is untouched. eSCL deletes delivered content; undelivered successful
documents expire after 24 hours. Native print spool is removed after safe transfer.

Retained masters require explicit confirmed disposal, even after export. Unexported,
active or Copy-owned documents remain until released/discarded. New imports
stop at 100 documents or 2 GiB of compressed masters; this limit excludes recovery
evidence and explicitly retained diagnostics. Private storage is under
`~/Library/Application Support/local.bjc85.utility/`. Show Private Files opens
it. No document upload is implemented. Discovery uses a private stable random
installation identity, without broadcasting the test printer's serial.

Useful shortcuts: Command-O Open, Command-S Export, Command-P Print document,
Command-N New, Command-W Close current window/document, Command-Z/Shift-Command-Z Undo/Redo,
Command-0 Fit, Command-1 100%, Command-plus/minus Zoom, Command-R Rotate,
Command-period Cancel physical operation, Command-comma Settings, Command-? Help.
Enable macOS Settings → Keyboard → Keyboard Navigation to Tab through all
controls. Offscreen inspector controls scroll into view as they receive focus.
The canvas announces zoom and crop dimensions; arrow keys move the selection
in Fit mode and pan at 100%. Real keyboard, window-size and appearance checks
are recorded in [the UI audit](macos27-ui-ux-audit.md). Full VoiceOver acceptance
remains open because its system process could not be inspected during verification.

Physical acceptance requires a separate explicit authorization; see
[the opt-in plan](physical-acceptance-plan.md). This implementation did not scan,
feed paper, calibrate, clean, change cartridges or submit a real print job.
For installation, relocation and signing gates, see [RELEASE.md](RELEASE.md).

### Recovering storage failures

Retained Documents lists healthy pages even when another entry is damaged. Files
from damaged entries and deferred captures remain preserved and count toward
storage limits. Export and deliberately discard healthy pages to make room, then
choose File → Retry Recovery. This restores completed documents without starting
a scan or print. File → Retry Saving retries unsaved work after storage repair;
Quit also drains queued writes. Restoration warnings alone do not block Quit.
