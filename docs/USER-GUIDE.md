# Using the revived BJC-85 and IS-12

## Scan a document

1. Install the IS-12 and power on the printer.
2. Open **BJC-85 Scanner** from your personal Applications folder. Its shortcut
   points to `build/BJC-85 Scanner.app` in this project.
3. Choose **Connect scanner**. This pauses printing and enables scanning on this Mac.
4. Load your document, select colour, grayscale, or black and white and the
   resolution, then choose **Scan page**. Each operation feeds one sheet.
   The preview fills in as each scanned band arrives. Gray areas have not been
   scanned yet; with bottom-first rotation enabled, the page fills from the bottom.
5. Check **Sheet was fed bottom first** to rotate the result if needed.
6. Choose **Save image…** for PNG, TIFF, or PDF. All preserve the physical page
   size; PNG and TIFF preserve the native pixel values.

A plain-white-paper reference is already saved. If the app reports that the
reference is invalid, load a clean blank white sheet and choose **Calibrate
white sheet**, then reload the document. This corrects shading but does not
establish Canon-reference colour accuracy.

You can also open **Image Capture** from the Device menu or macOS Applications
and choose **Canon BJC-85 IS-12 Native**. The local scanner service is installed
and tested through Apple's ImageCaptureCore API. Its graphical app still needs
an unlocked-session check. Image Capture may crop to its selected paper size;
the dedicated scanner app retains the full 8 × 10.8 inch region. Apple's observed
requests use JPEG for transfer; choose our native app when lossless output matters.

## Print, including a saved scan

1. Finish scanning and replace the IS-12 with the BC-11e.
2. In BJC-85 Scanner, choose **Device → Switch to printing…** and confirm the
   BC-11e is installed. The app stops scanner discovery and resumes printing.
3. Open the document or saved scan and print to **Canon BJC-85 Native**.

Use plain Letter or A4 paper. Letter colour output was physically confirmed.
The black ink channel did not print even in the printer's built-in nozzle test;
black text may remain absent until its ink-delivery problem is resolved.

To return to scanning, install the IS-12 again and choose **Connect scanner**.

## Current checks and files

Printed test charts scanned successfully at 90 and 180 dpi. Blank sheets also
validated 360 dpi colour, grayscale, and full-page black-and-white output.
Black-and-white uses a native threshold of the complete grayscale scan; the
original grayscale samples are retained. Direct device one-bit acquisition was
also successful at 90 dpi, but ended short in its 360 dpi experiment.
Blank sheets establish acquisition and file handling, not detail or tonal accuracy.
The project has not yet established every original Canon driver feature.

Saved chart examples are in `scans/2026-09-13/`. The native app retains captures
under `.state/scanner-app/`; Image Capture's service retains them under
`.state/escl-jobs/`. **Show files** opens the app's most recent capture.
These files contain your scanned content. Partial data is retained after cancellation.
The live preview uses a lightweight 90 dpi view; the completed image and saved
files use the selected scan resolution. Cancelling leaves the partial preview
visible, but it cannot be saved as a completed scan.

The current installation uses only native ARM64 code and Apple's system
frameworks. Keep this project in its present location: the app's service scripts
and saved settings reference it. [README](../README.md) has build, service,
recovery, and protocol details.
