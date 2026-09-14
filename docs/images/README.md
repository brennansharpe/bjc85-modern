# GitHub presentation images

Six **illustrative UI mockups**, drawn as editable SVGs and exported at 2× to
2880 × 2160 PNGs. These are presentation artwork, not captured screenshots or
evidence of successful hardware operations.

The soft grey window, thin outlines, blue selection, and pastel sample page
follow the project's original [scan wireframe](../mockups/scan-workspace.svg),
also supplied as `download.svg`. The layout and labels reflect the current
AppKit implementation as reviewed on 14 September 2026.

| Image | Subject | Source and visual reference |
| --- | --- | --- |
| [Scan](01-scan-workspace.svg) | Acquisition inspector, document crop, revision and exports | `WorkspaceLayout.swift`, `UtilityControls.swift`, `ScanWorkspaceView.swift`; `after-scan.png` |
| [Print](02-print-workspace.svg) | Paper, copies, colour, quality and queue actions | `PrintSettingsView.swift`, `UtilityControls.swift`; `after-print.png` |
| [Copy](03-copy-workflow.svg) | Retained document, cartridge transition and explicit print action | `CopyWorkflowView.swift`, `UtilityWindowController.swift`; `after-copy.png` |
| [Device](04-device-workspace.svg) | Connection, reference and recovery controls | `UtilityControls.swift`; `after-device.png` |
| [Dark Mode](05-dark-workspace.svg) | Scan layout in a dark palette | `ScanWorkspaceView.swift`, `FixturePresentation.swift`; `after-dark.png` |
| [Settings](06-privacy-settings.svg) | Separate Privacy & storage window | `UtilitySettings.swift`; `after-settings.png` |

Referenced Swift files are under `app/` and `app/UI/`. Actual fixture captures
are in [the UI evidence directory](../verification/macos27-hardening/ui/).

## Presentation choices

- The three panes, toolbar actions, inspector control order and Settings window
  follow the current application, replacing the original mockup's tab strip.
- The drawing simplifies native materials and spaces controls for readability.
  It is not a pixel-perfect reproduction of any macOS release.
- The document is original synthetic artwork. No personal scans, system
  screenshots, Canon artwork or remote images are embedded.
- The visible fixture label and disabled physical actions match fixture mode.
  The Copy readiness state is simulated; it does not claim a completed print.
- Scan shows a 6 × 8 inch crop of an 8 × 10.8 inch sample. The lower inspector
  continues below the fold, including further adjustments and Calibration.
- The Dark Mode illustration uses the same white sample document as Light Mode.
- PNGs are exact rasterizations of the SVGs. `gallery.png` is a contact sheet.

## Regenerate

SVG generation uses Python 3's standard library. PNG generation uses Node.js
and `sharp` 0.35.4; these are presentation tools, not app dependencies.

```sh
python3 scripts/presentation/generate_mockups.py
npm install --prefix /tmp/bjc85-presentation sharp@0.35.4
NODE_PATH=/tmp/bjc85-presentation/node_modules node scripts/presentation/render_mockups.cjs
```

`manifest.json` records filenames, sizes, descriptions and the source review
date. Review source changes before regenerating; labels are intentionally
written out in the generator so they can be checked and edited.
