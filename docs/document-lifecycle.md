# Document ownership and restoration

Implemented against review baseline `software-milestone-2026-09-14` on 2026-09-14. This describes the
new app; historical raw captures and recovery records are preserved separately.

## Ownership

`ScanDocumentStore` owns `Documents/<UUID>/master.png` and `document.json` under
the private Application Support runtime. Acquisition date, source, dimensions,
DPI, mode and reference identity are immutable. Rotation, normalized crop,
output mode, threshold and adjustments are revisioned edits. Export receipts
record destination, revision and date. A receipt for an older revision does not
mark a newer edit exported. Copy references a document ID, rather than owning
and deleting the only scan file.

The master is a lossless PNG. Image imports accept PNG, TIFF and JPEG; importing
JPEG cannot restore information already lost in that JPEG. A one-page PDF is
explicitly rasterized at 360 dpi and labelled as an imported PDF. Multipage PDF
import is rejected. These imported documents need no scanner connection.

Three lifetimes are independent:

| Resource | Owner and release rule |
|---|---|
| Master and edits | Document store; retained through export, printing, workspace changes and restart |
| Expendable capture files | Privacy retention; named files only, after a safely completed image has a durable document-import receipt |
| Recovery evidence | Native/helper/service journals and recovery guards; never removed by document export, diagnostic deletion or Copy reset |

Queued/executing workers hold a strong document pin. Discard and expiry refuse
pinned documents. Immutable snapshots carry document ID, revision and settings.
Preview cancellation releases its pin only when its queued/running work exits.
It cannot cancel a separate committed export. A stale preview completion cannot
replace a newer document or revision. Print staging and outstanding job receipts
survive restart; restoration never resubmits them.

## Commands and crash recovery

| Action | Result |
|---|---|
| Export / Command-S | Exports the chosen revision; retains master, edits and document ownership |
| Edit after export | Increments revision and marks it not exported; Undo/Redo is available during this session |
| File → Close / New Document | Saves and closes the active document into Retained Documents; never feeds paper |
| Open / successful New Scan | Retains the previous document before presenting the replacement |
| Failed or canceled scan/export | Keeps the previous document; preserves ambiguous/incomplete captures |
| Discard | Explicit sheet deletes that private document only; Copy references and active worker pins block deletion |
| Copy Reset | Releases Copy ownership while retaining its editable document; blocked during jobs, unknown outcomes and recovery |
| Window close / Quit | Active document stays restorable; pending metadata writes drain before Quit; active import/export/service/acquisition must finish or be canceled first |
| Relaunch | Restores active document/edits, retained Copy and exact outstanding queue reference, without reconnecting or resuming physical work |

Edits are asynchronously persisted in worker order. Save failures are shown and
block normal Quit instead of claiming persistence. A sudden crash can lose a
not-yet-written edit, but does not overwrite the master. Undo history is session
only; the latest persisted edits restore. Corrupt document metadata fails closed
and preserves files for inspection; there is no automatic destructive repair.

On startup, safe `image_complete` legacy app captures without an import receipt
are migrated to document masters. The normal import path is idempotent. A crash
between master import and its receipt can leave a duplicate retained document;
neither source is discarded. Incomplete or uncertain captures are not imported
as successful scans. URL-only legacy Copy PDFs migrate to an explicitly
rasterized document, preserving the original PDF and requiring fresh cartridge
confirmation. Recovery markers are never cleared by these migrations.

## Export and cleanup contract

User exports must be outside the entire private runtime. This deliberately
rejects an internal `processed.png`, even if it looks like a convenient save
location. Validation resolves existing ancestors with `realpath`, rejects final
symbolic links, compares device/inode identity for hard-link aliases, and checks
managed files. It repeats validation after rendering. Cleanup checks protected
identities and never recursively removes a directory containing a document.

PNG, TIFF and PDF are completely encoded before Foundation's atomic file write
replaces the destination. The result is checked for readability and byte count. Cancellation or
failure before replacement removes only the temporary output and preserves the
previous good destination. Once the atomic replacement commits, cancellation
does not retroactively undo a successful export. Success requires a readable
destination after the commit. Export never invokes capture cleanup.

Rendering always applies orientation, whole-page spatial filtering with clamped
edges, brightness/contrast/inversion, grayscale or threshold, rounded crop, then
encoding. The completed preview displays the whole-page result of this same
pipeline with its crop selection; exporting trims those same processed pixels.
Copy and Print use the same immutable full-resolution snapshot. Live acquisition
preview is labelled as provisional and may omit final host adjustments.

## Privacy and bounds

The runtime is `~/Library/Application Support/local.bjc85.utility/`; private
directories use mode 0700 and document files/receipts use 0600. No document upload
is implemented. Diagnostic retention defaults Off. Successfully imported raw
captures may then be removed without waiting for export. Diagnostic deletion
preserves unimported legacy captures, Copy/master data and unresolved recovery.
eSCL delivery cleanup and its 24-hour undelivered-success expiry remain separate.

Closed documents whose current revision was exported can expire after seven
days, checked at startup and diagnostic cleanup. Active, unexported, Copy-owned
and worker-pinned documents never expire automatically. Imports stop at 100
documents or 2 GiB of compressed masters; users can export/discard old documents
to make room. This quota does not include unresolved recovery evidence, explicit
diagnostic retention, print staging, legacy research or external exports. Those
are intentionally not erased to satisfy a quota. No promise of an overall disk
quota is made. See Settings for the retention choice and File → Retained
Documents to reopen saved sessions.

Tests: `tests/document_pipeline_test.swift`, `tests/processing_worker_test.swift`,
`tests/privacy_retention_test.swift`; results are in
[the acceptance ledger](release-acceptance.md).
