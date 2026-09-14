# Canon Macintosh feature and resource map

The feature specification is Canon's IS-12 Macintosh manual, printed pages
60–94, plus the supplied handover. Presets are directly checked against printed
pages 70–72. Original Canon binaries and artwork are never runtime inputs.

The bounded resource parser recovered 11 forks, 582 resources and 174 UI items
from the preserved Classic extraction. These include **installer** UI. The
opaque `PPC/IS Scan file` and `Installer/CommonFile` payloads have not been
decoded into the installed application's resource fork. Therefore genuine IS
Scan application resource IDs, names, item numbers and rectangles remain TBD.
Installer IDs must not be relabelled as scanner UI IDs.

Rectangles below use `(left,top,right,bottom)` in original QuickDraw units.
“Baseline” hardware evidence predates this UI change. “Pending” means no new
physical qualification; it never means a blank sheet proved image quality.

| Classic file | Type / ID | Resource name | Item / type | Original label | Original rectangle | Manual / reference | Modern feature / view | Swift source | Implemented? | Hardware tested? | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| English/Installer/Installer.rsrc | DITL / 128 | unnamed | 1 / button | Install | (349,234,439,254) | Resource index SHA a6e0d0… | Native installer | package-pkg.sh | Yes | N/A; install pending | Installer only; no artwork reused |
| English/Installer/Installer.rsrc | DITL / 130 | unnamed | 1 / button | Cancel | (316,174,406,194) | Same resource index | Native installation cancellation | System Installer | System | N/A | Does not establish scan cancellation semantics |
| English/Installer/Installer.rsrc | DITL / 400 | unnamed | 3 / edit text | Untitled folder | (12,32,292,48) | Same resource index | Native export panels with document retention | DocumentActions.swift | Yes | N/A | No copied legacy dialog |
| IS Scan application (container unresolved) | TBD / TBD | TBD | TBD / preset | DTP Colour | TBD | Manual 70 | Colour 180, grayscale preview | Models/CanonPreset.swift | Yes, qualified subset | 180 colour baseline | Original colour matching unavailable |
| Same | TBD / TBD | TBD | TBD / preset | Photo | TBD | Manual 70 | Colour 360, colour preview | Models/CanonPreset.swift | Yes, qualified subset | 360 blank only | Original colour matching unavailable |
| Same | TBD / TBD | TBD | TBD / preset | DTP Grayscale/B&W | TBD | Manual 70 | Grayscale 180 | Models/CanonPreset.swift | Represented | Pending 180 gray | Label kept as historical concept |
| Same | TBD / TBD | TBD | TBD / preset | Text | TBD | Manual 71 | B&W 180, adjustable threshold | Models/CanonPreset.swift | Partial | Pending | Canon edge emphasis unavailable; disclosed |
| Same | TBD / TBD | TBD | TBD / preset | FAX | TBD | Manual 71 | Text Enhanced, 200 dpi | Models/CanonPreset.swift | Disabled | No | Both processing and resolution unqualified |
| Same | TBD / TBD | TBD | TBD / preset | OCR | TBD | Manual 71 | Text Enhanced, 360 dpi | Models/CanonPreset.swift | Disabled | No | Not an OCR text-recognition engine |
| Same | TBD / TBD | TBD | TBD / settings | Custom | TBD | Manual 70–75 | Mode, DPI, threshold | Models/ScanSettings.swift; BJC85Scanner.swift | Yes / gates | Baseline subset | 200/300 and Text Enhanced disabled |
| Same | TBD / TBD | TBD | TBD / preview | Prescan / selection | TBD | Manual Macintosh scanning workflow | Full-page 90 dpi prescan, crop and reload guidance | UI/ScanWorkspaceView.swift | Yes; offline geometry and mouse/key checks | New reload workflow pending | Host crop uses displayed orientation and rounded source edges |
| Same | TBD / TBD | TBD | TBD / effects | Brightness / contrast / image effects | TBD | Manual Macintosh image adjustment section | Explicit deterministic host effects | ScanProcessing.swift | Yes; pixel tests | Pending content | Modern algorithms; no claim of identical Canon kernels |
| Same | TBD / TBD | TBD | TBD / calibration | White-Level Calibration | TBD | Manual 18–20, 83; native calibration trace | Date, reference kind, validation, guided measurement | UI/CalibrationView.swift | Yes; reference tests | Baseline paper measurement | Ordinary paper is experimental; reference is not factory colourimetry |
| Copy Utility 2.60 (not acquired) | TBD / TBD | TBD | TBD / workflow | Copy / Reprint / Reset | TBD | Supplied handover, Copy Utility research | Scan, retain editable master, confirmed swap, explicit print/reprint | CopyWorkflow.swift; PrintActions.swift; UI/CopyWorkflowView.swift | Implemented; injected controller tests | Pending entire cycle | Correct settings and retry without rescanning; Reset preserves document; no automatic swap |
| BJC-85 3.4 driver (not acquired) | TBD / TBD | TBD | TBD / print options | Paper / copies / grayscale / quality | TBD | Handover; native PAPPL/Gutenprint mapping | Letter/A4, mono/colour, 3 quality levels, 360 dpi | Models/PrintSettings.swift; UI/PrintSettingsView.swift | Yes; mapping/dry run | Letter colour baseline; rest pending | Plain/Auto fixed; enabled controls map to actual IPP options |
| BJC-85 driver / utility | TBD / TBD | TBD | TBD / advanced | Cartridge, feed, halftone, gamma, balance, density, profiles, presets | TBD | Handover printer inventory | Research notice | BJC85Scanner.swift | Unavailable | No | No enabled ignored controls; no Photo Optimizer claim |
| BJC-85 driver / utility | TBD / TBD | TBD | TBD / maintenance | Cleaning / nozzle check | TBD | Baseline built-in nozzle test; handover | Guidance, calibration, status | UI/MaintenanceView.swift | Guidance only | Built-in baseline; native commands pending | No invented cleaning/deep-clean/alignment/ink-level commands |

Full local decoded records, including MENU/STR/STR# and item flags, are in
`research/extracted/classic-resource-index/`; metadata hashes are tracked in
`research/manifests/resource-index.json`. Reproduce with
`scripts/index-classic-resources.py`; it never executes a decompressor from a
Canon binary. Missing packages and source URLs are recorded explicitly in
`research/manifests/provenance.json`.

## Current native organization

The macOS 27 pass preserves the qualified preset/workflow terminology above in
a native Scan/Print/Copy/Device sidebar, persistent canvas and collapsible
inspector. Settings is a separate Command-comma window. This is a modern project
choice, not a claim about undocumented Classic rectangles or resources.
`UtilityWindowController`, `DocumentActions`, `ScanActions` and `PrintActions`
now own the application responsibilities formerly in `BJC85Scanner.swift`;
that file contains only launch/window wiring.

New project features include retained documents and immutable acquisition facts,
Undo/Redo, multiformat export without source deletion, explicit retryable Copy
actions, shared status and exact queue job results. These are not claims of Canon
algorithm equivalence. Real before/after screenshots and completed fixture UI checks
are recorded in [the macOS 27 audit](macos27-ui-ux-audit.md).
