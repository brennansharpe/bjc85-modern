# Unlocked fixture UI verification — 2026-09-14

The user unlocked the Mac and requested the previously deferred graphical
checks. This record covers the running AppKit application on macOS 27.0
26A428 / Xcode 27.0 27A5237l / SDK 27, ARM64, Swift 5, deployment target 14.0.
All content is synthetic. Fixture adapters independently block live USB,
production services and installed print queues. No physical acceptance is claimed.

## Actual checks

| Check | Observation |
|---|---|
| Open without scanner | Command-O, native Open panel, Command-Shift-G and Return imported the nonblank 2880 × 3888, 360 dpi fixture |
| Numeric crop and keyboard | Entered left 0.50, top 0.75, width 6, height 8 inches using Tab and Return; focus returned to the canvas. Shift-arrow moved ten source pixels; Undo restored it |
| Edits and view | Command-R, Command-Z/Shift-Command-Z, Command-1 and Command-0 worked; arrows pan at actual pixels. Master remains unchanged |
| Native exports | Command-S exported PNG, TIFF and PDF from revision 7 of one document. An additional rotation became revision 8 and was correctly marked not exported. Escape canceled another Save sheet without adding an export |
| Independent output check | Actual native-panel PNG/TIFF files decode to identical 2160 × 2880 pixels at 360 dpi; PDF media box is 432 × 576 points (6 × 8 inches). Results in `ui-export-check.json` |
| Managed destination | Save panel targeted private `runtime/processed.png`. A clear top-level error rejected it; no file was created, master/revision/three receipts remained intact |
| Close, New and restart | Command-N retained the document. File → Retained Documents and Return restored it. Quit/relaunch restored the same ID, acquisition metadata, master, revision 8 and three revision-7 receipts without resuming jobs |
| Settings | Command-comma opens standard Settings. Command-W closes Settings and preserves the current document. Initial keyboard focus and native checkbox/button traversal are visible |
| Copy | Invalid copies 0 shows an inline error. Changing to 2 clears it, preserving the document. Edit Retained Image, rotation and returning to Copy preserve the same image and settings. Print Retained Copy stays explicit but disabled by fixture safety |
| Actions/status | Physical buttons and corresponding menu/toolbar actions are disabled in fixtures. Recovery remains visible above every workspace. A busy lease reports a last-check observation without changing readiness to disconnected |
| Native keyboard traversal | With macOS Keyboard Navigation enabled, Tab/Shift-Tab reaches sidebar, canvas, disclosure controls, popups, numeric fields, sliders and buttons. Arrow keys select workspaces; disabled physical controls are skipped |
| Small inspector | Repeated Tab moves to controls below the fold and scrolls them into view with visible focus; constructed-view regression checks the same geometry boundary |
| Window layouts | Requested default 1140 × 780, large 1440 × 920, small 760 × 570, and effective native minimum tested. AppKit may constrain these to the screen or effective minimum. Native Window → Move & Resize → Left tested practical tiling. Both sidebar and inspector collapse/reopen successfully |
| Text/appearance | Expanded English fixture text wraps and scrolls. Main-window Dark Mode, empty Dark canvas, Increase Contrast, Reduce Transparency, Differentiate Without Colour and Reduce Motion checked. No stable overlap or unreadable active control was observed |
| Accent/material | Purple accent and Liquid Glass tint amount 1 adapt system controls; restored Blue and amount 0 update the running app. The document-interior raster is byte-identical across these captures (ROI recorded in JSON) |
| Displays | Built-in Retina at its existing 1512 × 982 default setting and connected S24R35x used. Native Window menu moved the app to the external display and back while retaining the page. No resolution, arrangement, color profile or physical display connection changed |

The initial PNG test filename has two `.png` suffixes because the test typed an
extension into the panel's selected base-name portion. It is a valid PNG; later
native panel checks explicitly set the whole filename. No output was renamed
or altered for the comparison.

## Fixes made from the graphical checks

* `WorkspaceLayout.swift`: safe-area canvas edges keep the fitted page out of
  overlay inspectors; native disclosure buttons no longer duplicate headings.
  `UtilityWindow` scrolls newly focused controls into view, including field editors.
* `ScanWorkspaceView.swift`: explicit clipping prevents zoomed pixels painting
  over chrome; focus invalidation removes stale focus rings; accessible values
  distinguish zoom/pan/crop and empty state; empty opaque paper uses readable
  text in Dark Mode and does not draw an obsolete crop.
* `UtilityControls.swift` / `UtilityWindowController.swift`: Command-W targets
  the current Settings window; button/menu capability projection agrees; native
  key-view loop updates with workspace changes; minimum width reviewed; busy
  lease text is distinguished from the coordinator's retained readiness.
* `CopyWorkflowView.swift`: next actions and retained-image editing precede long
  settings text; removed an orphaned Copy brightness label.
* `DocumentActions.swift`: reopening updates status and restores canvas focus;
  closing moves focus to the empty canvas.
* `ScanActions.swift`: preparing/stopping messages are set before callbacks can
  report terminal results, so immediate refusal is not overwritten. Controller
  tests assert both error text and retained scanner readiness.

## Accessibility scope and limits

Direct AX reads of the running app checked names, values, selection, actions,
disabled controls, numeric units and focus. Xcode Accessibility Inspector was
targeted to current fixture processes; Run Audit was invoked with Element
Description, Hit Region, Contrast, Element Detection, Parent/Child and Action
enabled. Its results list remained empty, without an explicit completion record
or screenshot. Pointer targeting also failed to resolve the canvas through the
automation surface. This is **inconclusive**, not evidence of a clean audit.
The native Inspector panel and its AX tree were captured as such.

VoiceOver was initially off. It was temporarily enabled in System Settings,
but its system application did not expose feedback and explicit system-path
launches timed out. Spoken navigation, announcements and assistive pacing are
therefore **unverified**. The preference was restored off. VoiceOver Utility
was only inspected; its preferences were not changed.

Other remaining cases: real acquisition/print/cancel/cartridge sheets and their
announcements; actual display removal/offscreen restoration; further display
scaling; real translations; macOS 14–26; qualitative evaluation by a regular
VoiceOver user. The synthetic busy/recovery states do not exercise physical
jobs, and the fixture's disabled Print action is not a successful print test.

## Restoration and evidence

Original settings were restored: Auto appearance, Blue accent, Liquid Glass
tint amount 0, Keyboard Navigation off, Increase Contrast off, Reduce
Transparency off, Reduce Motion off, Differentiate Without Colour off and
VoiceOver off. Wallpaper tint remained on. Inspector test overrides returned to
their initial settings, and its pointer targeting was turned off. Test utilities
were closed. Production queues, services, runtime evidence and hardware were untouched.

`ui/manifest.json` inventories the retained screenshots after JPEG metadata
removal. Decoded image pixels are unchanged. The Inspector screenshot containing
a local computer name is excluded from the repository and its history. Capture
tools may scale returned rasters; their dimensions are not inferred physical
display or window-point sizes. Original captures are retained only in a private
local backup.

After these fixes, `unlocked-release-build.txt` records the native build,
10/10 CTest and bundle audit; `unlocked-swift.txt` records seven passing suites;
`unlocked-hardening-tests.txt` records four passing controller/document/service
executables; `unlocked-concurrency-audit.txt` records the clean Swift 5 complete
concurrency/warnings-as-errors check. Historical sanitizer/replay/service and
processing measurements are separate, unchanged records.
The full hardening rerun logged a redundant cast warning in its test source;
that cast was removed and the affected controller executable was rebuilt and
passed with warnings-as-errors (`unlocked-workflow-controller.txt`).

The earlier 2880 × 3888 benchmark remains **0.728 s** sharpen/TIFF, **0.668 s**
despeckle, **295,321,600 bytes** maximum RSS and **23.179 ms** maximum command-line
main-loop gap. The GUI stayed operable during the inspected edit/export work,
but no instrumented graphical event-latency or VoiceOver benchmark was run.
