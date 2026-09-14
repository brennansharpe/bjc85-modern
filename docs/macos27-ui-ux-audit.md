# macOS 27 UI/UX audit — 2026-09-14

Implementation is present in the native app. After the user unlocked the Mac,
the running fixture app was inspected and real after screenshots were captured.
Keyboard, native export panels, restoration, appearance and adaptive-layout
checks completed with the limits below. Full VoiceOver and a conclusive native
Inspector audit remain open. A build and constructed-view assertions do not establish HIG compliance.
No Apple certification, Canon endorsement or full Canon feature parity is claimed.

## Actual platform and baseline

| Item | Observed value |
|---|---|
| Review baseline / initial HEAD | `software-milestone-2026-09-14`; checkout initially clean; history not reset |
| Prior engine baseline | `native-hardware-baseline-2026-09-14` / `native-hardware-baseline-2026-09-14` |
| Mac | ARM64 MacBookPro18,3; 16 GiB RAM |
| OS | macOS 27.0 (`26A428`) |
| Xcode | 27.0 (`27A5237l`), `/Applications/Xcode-beta.app` |
| Installed SDK | macOS 27.0, `MacOSX.platform/Developer/SDKs/MacOSX.sdk` |
| Deployment | ARM64 macOS 14.0, unchanged |
| Compiler settings | Swift language mode 5, `-O`; C17; strict concurrency diagnostic audit separately run |
| Signing | Ad-hoc local build; no notary/signing credential changes or uploads |

Read the available source-review export Markdown, README, guide, feature map,
acceptance/release records, notices and regression tools. The supplied review
findings were checked against the current source. Later user changes would have
been preserved; none existed at the starting checkout. Existing protocol
fixtures, readiness, cancellation and recovery tests were retained.

## Apple guidance consulted

All links accessed on **2026-09-14**. Documentation shells that required
JavaScript were read through Apple's corresponding Markdown/JSON content.
WWDC25 was treated as background; macOS 27 resources, WWDC26 and macOS 27 release
notes were also read.

| Primary Apple reference | Guidance checked and implementation response |
|---|---|
| [Design resources](https://developer.apple.com/design/resources/) | Current macOS resources checked; no proprietary template artwork or fabricated Apple UI was added |
| [What's new in macOS](https://developer.apple.com/macos/whats-new/) | Current platform changes checked; AppKit remains the native foundation |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/) | Content priority, familiar controls/menus, resizable windows and efficient keyboard interaction |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | System materials for navigation/controls; opaque stable scanned page, no decorative glass stack |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Adaptable content/navigation/inspector structure, safe areas and progressive disclosure |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Labels/values, keyboard alternatives to crop dragging, semantic colors and status text; running keyboard and AX checks performed, VoiceOver limits recorded below |
| [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) | Application privacy preferences in standard Settings; document/acquisition controls beside their task |
| [Modernize your AppKit app, WWDC26](https://developer.apple.com/videos/play/wwdc2026/289/) | macOS 27 AppKit updates, keyboard interaction, system appearance, graceful termination and restoration |
| [Build an AppKit app with the new design, WWDC25](https://developer.apple.com/videos/play/wwdc2025/310/) | Background on native toolbar/split-view materials, content separation and avoiding custom chrome |
| [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) | Prefer system adoption rather than custom simulated glass; availability-gated safe-area behavior |
| [macOS release notes](https://developer.apple.com/documentation/macos-release-notes), [macOS 27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) | Read AppKit changes, including default menu-symbol visibility, open/save panel keyboard fixes and tab semantics; this app uses a sidebar, so no new segmented-tab API was needed |

The installed AppKit declarations for `NSSplitViewItem`, `NSToolbar`, `NSWindow`,
`NSView` and `NSControl` were inspected. The sidebar and inspector constructors
are public and support the existing minimum. `automaticallyAdjustsSafeAreaInsets`
is explicitly guarded with `#available(macOS 26.0, *)`. Native AppKit supplies
control metrics/materials on the running OS; no invented macOS 27 APIs are used.
During the unlocked pass, the installed `NSView.h` confirmed that `clipsToBounds`
is public since macOS 10.9 and defaults to false on macOS 14+. The canvas now
sets it explicitly. `NSWindow` key-view-loop APIs were also checked before use.

## Implemented project choices

These are design decisions for this utility, not dimensions or layouts mandated
by Apple. The default requested content size is 1140 × 780 points; the configured
minimum was raised to 760 × 560 after inspecting pane widths. AppKit can impose
a larger effective minimum or constrain a requested large window to its screen.
The minimum fixture uses the running window's effective `minSize`. Capture
pixel dimensions in the evidence manifest are not window-point measurements.

* Native split view: Scan, Print, Copy, Device sidebar; dominant persistent page
  canvas; collapsible task inspector. Sidebar and inspector have View commands.
* Shared top device/status/progress and specific cancel actions in every
  workspace. Measured preview rows use determinate progress; other work uses
  activity indicators and concrete stage text, without invented percentages.
* Standard toolbar and App/File/Edit/View/Device/Window/Help menus: Open, Export,
  retained documents, Print, Undo/Redo, Fit, 100%, zoom, rotation and crop.
  New/Close never feeds paper. Command-comma opens separate Settings.
* Host processing, reference qualification and operator-confirmed cartridge
  state are labelled. Unsupported 200/300 dpi and proprietary processing remain
  gated; maintenance offers only backed actions and honest limitations.
* Copy exposes stages, retained document editing, inline print validation,
  confirmed cartridge preparation and explicit print/reprint/retry actions.
* Canvas draws opaque page pixels, supports Fit/100% (backing-scale aware), pan,
  rotation, crop dragging and keyboard/numeric physical dimensions. Status has
  text as well as semantic styling; no invented ink/battery/paper telemetry.
* System typography, semantic control colors and native focus are used; no
  custom traffic lights, Canon logo or Classic chrome. Window subtitle identifies
  the independent project. Window position is restored with an offscreen check.

Relevant implementation: `app/UI/WorkspaceLayout.swift`, `UtilityControls.swift`,
`UtilitySettings.swift`, `ScanWorkspaceView.swift`, `PrintSettingsView.swift`,
`app/UtilityWindowController.swift`, and the document/scan/print action files.

## Real UI evidence and remaining conditions

Five **before** screenshots were captured from the running baseline application
using synthetic content, isolated runtime storage and no hardware operations:

| Workspace | Captured baseline |
|---|---|
| Scan | [before-scan.png](verification/macos27-hardening/ui/before-scan.png) |
| Print | [before-print.png](verification/macos27-hardening/ui/before-print.png) |
| Copy | [before-copy.png](verification/macos27-hardening/ui/before-copy.png) |
| Device | [before-device.png](verification/macos27-hardening/ui/before-device.png) |
| Settings | [before-settings.png](verification/macos27-hardening/ui/before-settings.png) |

The initial lock deferred this part of verification. The user subsequently
unlocked the Mac and explicitly requested completion. All after images below
are captures of the running native app with synthetic content; capture
metadata was removed for privacy without changing decoded pixels;
the capture tool may scale its returned raster. No wireframe/generated image
stands in for a screenshot. Fixture states do not claim hardware readiness.

| After evidence | Observed result |
|---|---|
| [Scan](verification/macos27-hardening/ui/after-scan.png), [Print](verification/macos27-hardening/ui/after-print.png), [Copy](verification/macos27-hardening/ui/after-copy.png), [Device](verification/macos27-hardening/ui/after-device.png), [Settings](verification/macos27-hardening/ui/after-settings.png) | Actual native workspaces; same document persists; physical actions disabled in fixture mode |
| [Multiple exports and restoration](verification/macos27-hardening/ui/after-multiple-exports.png), [unsafe destination](verification/macos27-hardening/ui/after-unsafe-export.png) | Native PNG/TIFF/PDF exports, later edit and relaunch retain the same document; managed `processed.png` export is rejected |
| [Invalid Copy quantity](verification/macos27-hardening/ui/after-invalid-copies.png), [edited Copy](verification/macos27-hardening/ui/after-copy-edited.png) | Correcting 0 to 2 clears the error, retains the image and leaves the explicit next action; fixture printing remains disabled |
| [Recovery](verification/macos27-hardening/ui/after-recovery.png), [busy](verification/macos27-hardening/ui/after-busy.png) | Shared status remains visible; busy is a last-check observation, not disconnection or a reservation |
| [Minimum with long text](verification/macos27-hardening/ui/after-minimum-dark.png), [large](verification/macos27-hardening/ui/after-large.png), [tiled](verification/macos27-hardening/ui/after-tiled.png), [collapsed panes](verification/macos27-hardening/ui/after-chrome-collapsed.png) | Native half-screen tiling, effective minimum and requested default/large sizes inspected; controls wrap/scroll; no stable overlap found |
| [Keyboard scroll](verification/macos27-hardening/ui/after-keyboard-scroll.png), [100%](verification/macos27-hardening/ui/after-100-percent.png) | Focus scrolls to offscreen controls, zoom is clipped, arrows pan at 100%; numeric crop, Undo/Redo and sheet keyboard behavior observed |
| [Dark](verification/macos27-hardening/ui/after-dark.png), [empty Dark canvas](verification/macos27-hardening/ui/after-dark-empty.png), [contrast](verification/macos27-hardening/ui/after-dark-small-contrast.png), [accent/tint](verification/macos27-hardening/ui/after-accent-tinted.png) | Appearance adapts while page pixels remain stable; document-interior screenshot pixels match exactly across accent/tint changes |
| [External display](verification/macos27-hardening/ui/after-external-display.png) | Native Window menu moved the app from built-in Retina to S24R35x and back; document and layout retained |

The pass fixed an inspector safe-area overlap, duplicate disclosure labels,
unclipped 100% drawing, stale canvas focus/crop presentation, unreadable empty
Dark canvas text, Settings Command-W routing, offscreen keyboard focus, and
stale status after reopening. Copy next actions moved above its longer settings;
fixture-only physical buttons and menus agree on availability. Controller tests
also exposed preparing text overwriting immediate preflight errors; the terminal
message now wins. See [the full check record](verification/macos27-hardening/ui-checks.md).

Direct AX inspection verified workspace selection, control names/values,
disabled actions, crop units, zoom/pan help and keyboard focus. Xcode Accessibility
Inspector was opened, the current fixture process selected and Run Audit invoked
with all six options enabled. It listed no findings but also supplied no explicit
completion/result or inspectable screenshot; its pointer selector did not resolve
the targeted canvas through automation. This is **inconclusive**, not a clean
accessibility audit. The [AX record](verification/macos27-hardening/ui/accessibility-inspector-audit.txt)
preserves that limitation. The Inspector screenshot is excluded for privacy
because it contains a local computer name. VoiceOver was enabled temporarily, but the system app
did not expose feedback and repeated explicit launches timed out. Full spoken
navigation/announcement quality remains unverified. VoiceOver was restored off.

Remaining conditions: conclusive Inspector/VoiceOver acceptance; live acquisition,
print/cancel/cartridge sheets and progress announcements; physical display removal
and offscreen restoration after an actual topology change; additional scaling
settings and macOS 14–26; real translations (the long-text fixture is English).
Display switching is not a display-disconnection test. No global resolution,
color profile or production service setting was changed. Temporary keyboard,
contrast/transparency/motion, accent and material settings were restored.

Reproducible fixture launch (no production services/queues or USB):

```sh
python3 tests/make_synthetic_fixture.py build-hardening-tests/full-resolution.png
"dist/BJC-85 Utility.app/Contents/MacOS/BJC85Scanner" --fixture build-hardening-tests/full-resolution.png
```

Use `--fixture-state copy-ready|invalid-copies|recovery|busy|print|device|settings`
(choose one value), `--fixture-dark`, `--fixture-small`, `--fixture-minimum`,
`--fixture-default`, `--fixture-large`, or
`--fixture-long-labels`. `BJC85_FIXTURE_DIRECTORY` can identify an isolated
temporary runtime for close/relaunch checks. The fixture label remains visible
and native adapters independently reject physical actions.

## Measured processing

On the Mac above, `sh scripts/benchmark-processing.sh` processed a nonblank
2880 × 3888 RGB fixture containing asymmetric colored corners, fine lines and
gradients. One measured optimized run: sharpen plus TIFF export **0.728 s**;
decode plus despeckle **0.668 s**; 37 main-run-loop heartbeat ticks with maximum
gap **23.179 ms**. The whole command measured 1.97 s wall time, maximum resident
set **295,321,600 bytes**, peak footprint **240,567,136 bytes**. See
[performance.txt](verification/macos27-hardening/performance.txt).

The test asserts processing is off the main thread, keeps its source pin, and
exports an immutable revision despite a later edit/obsolete preview cancellation.
The heartbeat is a command-line run-loop measurement, not a claim that the full
graphical app, VoiceOver or window dragging was measured. No export downsampling
was introduced. Runtime execution on macOS 14–26 remains a separate gate.
