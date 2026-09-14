# BJC-85 Utility user guide

This local feature milestone has not completed physical or notarized-release
qualification. The currently installed prototype is separate from the new
`dist/BJC-85 Utility.app`; building this milestone did not replace it.

## Scan workspace

Connect scanner prepares the utility's named services and checks the IS-12.
It pauses the BJC85_Native print queue and refuses to switch while known jobs
are pending. A successful USB exchange with the wrong head is not “ready.”
Normal app startup does not connect, calibrate, scan or feed paper.

Import existing white reference accepts a previously saved native reference.bin
and copies it to the utility's private storage. Connect validates its checksum,
printer serial, head class and raw temperature. Invalid/missing references
require calibration. The USB serial identifies the printer, not an individual
IS-12 cartridge; changing scanner cartridges requires a fresh reference.

White-Level Calibration shows the saved date and last connection's validation.
This implementation measures an experimental ordinary white sheet. It does not
claim the optical standard or colour accuracy of Canon's reference sheet. The
native helper rechecks reference validity before any correction download/feed.

Choose a preset, image type and DPI. Photo requests colour at 360 dpi. DTP Colour
requests 180 dpi with grayscale prescan. Text offers native adjustable B&W
thresholding with an explicit note that original Canon edge processing is
unavailable. FAX/OCR remain represented but unavailable. 200/300 dpi and Text
Enhanced are disabled, with no silent substitution.

Prescan acquires one full page at 90 dpi. Drag a selection on the preview, move
it with arrows (Shift for larger movement), or use View → Crop dimensions.
Dimensions use the current locale. Clear Selection restores the page. Corners
resize a selection. Zoom is available from View or Command-plus/minus.
Rotation changes both the displayed page and selected source coordinates.

A prescan ejects the original. Before final Scan, the app prompts for the same
original to be reloaded in the same orientation. Final acquisition uses the
selected qualified resolution; export crops the resulting full-resolution image.
The fixed acquired area is 8 × 10.8 inches. Crop does not change the proven
physical scanner command sequence.

Brightness, contrast, threshold, sharpen, soften, despeckle and invert are
explicit host operations. Their preview/export uses deterministic native code;
they are not a recreation of every Canon processing algorithm. Raw corrected
pixels are preserved until export cleanup. PNG/TIFF/PDF export retains scan DPI.

## Printing and copying

Command-P in other apps uses the normal Canon BJC-85 Native queue when printing
has been prepared. The utility's Print tab offers Letter/A4, copies (1–999),
colour/monochrome and draft/normal/high quality at 360 dpi. Plain paper and
automatic feed are fixed. These settings map to existing IPP/Gutenprint options;
additional cartridge/media/halftone/profile/colour-balance options are not enabled.

The Copy tab has its own print settings and scan brightness. Copy acquires one
original and retains a PDF privately. Continue after cartridge swap presents
explicit BC-11e guidance; only confirmation prepares printing. Reprint uses the
same retained image, with the current copy print settings. Reset removes the
retained copy session when idle. Copy brightness is set before acquisition.
A recovery state blocks reset/new operations while preserving the image.
The saved copy session survives app restart; printing never resumes automatically,
and the print-cartridge transition must be confirmed again.

The BJC-85 cannot print with the IS-12 installed. Software does not physically
identify every print cartridge; the BC-11e transition requires the operator's
confirmation and an idle queue. The entire new scan/swap/print/reprint workflow
still requires physical acceptance. Existing black ink delivery is faulty;
monochrome output and nozzle quality depend on that hardware condition.

Image Capture uses the same native scanner engine via local AirScan/eSCL, one
loaded sheet per job. Scanner discovery is stopped during the confirmed printing
transition. Do not switch device use during an active job.

## Cancellation, recovery and privacy

Command-period or Cancel requests a bounded stop of the current operation.
The helper prevents new motion after cancellation, sends the known stop command
only when the transaction is intact, and requires a complete safe response.
An ambiguous USB write or unknown helper outcome leaves Recovery required.
Restarting the app/service does not clear it or replay the page. Keep the
capture, inspect the physical printer when available, and make an explicit
recovery decision before archiving a marker. There is no “force continue” button.

Settings (Command-comma) includes Retain diagnostic captures, default Off.
Successful app raw/image/log captures are removed after export. Copy keeps only
its retained image after successful capture, until Reset. eSCL deletes content
after delivery. Undelivered successful eSCL documents expire after 24 hours,
checked hourly and on service restart. The IPP service deletes raw print spool
after safe completion.
Unexported scans remain available for Save; incomplete/ambiguous captures remain
for recovery. Show files opens the relevant private capture directory.
Delete Diagnostic Data removes completed app captures after confirmation; it
preserves calibration references, external exports and active copy/recovery data.
It does not erase the earlier project's research or physical-test evidence.

State is in `~/Library/Application Support/local.bjc85.utility/`, with private
directory/file permissions. Service logs contain metadata; raw helper logs live
inside capture storage and follow its cleanup. No document upload is implemented.

Shortcuts: Command-S Save, Command-P Print retained scan, Command-period Cancel,
Command-comma Settings, Command-? Help, Command-plus/minus Zoom, arrows/Shift-arrows
crop movement. Full VoiceOver qualification is still pending.

## Physical work — only after the user says they are ready

The printer currently has the IS-12 installed and blank sheets in the tray.
Do not scan those sheets as content-bearing acceptance. No physical action is
scheduled or automatically triggered by this milestone.

When the user resumes physical work, begin with status/reference checks, then
planned content-bearing targets at 90/180/360 dpi and supported image modes.
Exercise prescan/reload/crop, calibration, safe cancellation and Image Capture.
Only then perform the confirmed BC-11e swap for normal Command-P and Copy/Reprint,
and investigate the existing black ink problem. Native maintenance commands
must first have verified protocol evidence and offline fixtures. The app's
maintenance panel currently provides guidance, status and calibration access.

For relocation, signing and clean uninstall, see [RELEASE.md](RELEASE.md).
