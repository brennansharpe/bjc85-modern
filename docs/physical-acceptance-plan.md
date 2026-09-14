# Opt-in physical acceptance plan

**Not executed by this hardening task.** Each physical session requires explicit
owner authorization and an operator at the printer. This plan is not permission
to move paper, alter services/queues, calibrate, clean, change cartridges or print.
Existing historical results remain evidence for their original build only.

Before starting, record the exact app/helper hashes, installed service paths,
OS/build, cartridge confirmation, content target, paper condition and private
capture location. Check other clients' queues and acquisitions. Never clear a
recovery marker, interrupt another client's job or replay an uncertain transfer
to make a test pass. Resolve outstanding recovery with physical inspection and
an explicit evidence-preserving decision first.

| Authorized test | Record and acceptance condition |
|---|---|
| Content-bearing acquisition | Asymmetric color/fine-line/gradient target at 90/180/360 dpi and supported color/gray/B&W modes; inspect pixels, orientation, shading and dimensions, not just transport success |
| Calibration | Guided ordinary-paper preparation, measured reference, subsequent validation and corrected content; disclose lack of factory reference-sheet equivalence |
| Prescan/reload | Observe ejection, reload same original/orientation, host crop and final full-resolution acquisition; verify selected content and physical size |
| Retain/edit/export | Export PNG then TIFF/PDF, edit/Undo, print preparation, relaunch and reopen; verify every output and master retained |
| Copy | Acquire, edit retained image, cancel an unchanged swap sheet, retry, perform deliberate IS-12 → BC-11e swap, correct invalid copies, print, reprint without scan, release session without deleting document |
| Ordinary Command-P | Newly installed local queue from another app; supported media/color/quality/copies, exact job identity and physical page inspection; preserve other clients' jobs |
| Image Capture | Newly installed loopback eSCL discovery/acquisition, content-bearing output, service transition refusal during its active acquisition |
| Cancellation | Before feed and during authorized acquisition/transfer; correlate journal/byte counts, stopping response, physical paper state and safe retry versus persistent recovery |
| Disconnect/reconnect | Deliberate disconnect at documented safe/active phases; no replay, marker persistence, correct reconnection/revalidation after operator recovery |
| Sleep/wake | Idle and explicitly authorized active cases; no duplicate submission/feed, preserved document and job reference, truthful unknown/recovery state |
| Printing outcome faults | Cancel before/after transfer starts; raster/service rejection; inspect authoritative job reasons separately from physical safety and visible ink |

The known black-ink fault remains a hardware qualification issue. Do not infer
black nozzle health from CUPS completion, or driver failure solely from missing
ink. Native cleaning/nozzle/deep-clean/alignment commands remain unavailable
until backed by protocol evidence and offline tests; do not add speculative
commands for this plan.

Record **passed**, **failed**, or **not run**, with timestamp, exact build,
redacted public derivative/provenance and private original evidence. No blank
sheet or screenshot alone establishes image quality. A failed/ambiguous result
stops dependent physical tests. Signing/notarization, clean install/uninstall,
macOS 14–27 runtime and graphical/accessibility acceptance are separate gates.
