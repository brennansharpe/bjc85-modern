#!/usr/bin/env python3
"""Draw the GitHub UI illustrations as self-contained, editable SVGs.

These are presentation drawings, not captured app screenshots. Layout and copy
come from app/UI, app/UtilityWindowController.swift, and the 2026-09-14 fixture
captures. The original docs/mockups/scan-workspace.svg supplies the visual style.
Only Python's standard library is required. Run from any working directory.
"""
from html import escape
from pathlib import Path
import json
import textwrap

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/images"
W, H = 1440, 1080
LIGHT = dict(bg="#eef1f5", window="#fafafa", chrome="#e4e7eb", sidebar="#ebedf0",
             inspector="#f2f3f5", canvas="#e3e7ed", text="#242832", muted="#626975",
             border="#bdc5cf", rule="#d5dae1", control="#ffffff", disabled="#eaedf1",
             disabled_text="#8a929e", accent="#356da9", selected="#d8e4f1", track="#bbc3ce")
DARK = dict(bg="#171c23", window="#252b33", chrome="#303741", sidebar="#2b323b",
            inspector="#2d343e", canvas="#1e242c", text="#e7ecf3", muted="#aab4c2",
            border="#505c6b", rule="#424d5b", control="#3a4451", disabled="#313945",
            disabled_text="#8994a3", accent="#80b3ea", selected="#3b536e", track="#637185")


class Drawing:
    def __init__(self, title, description, dark=False):
        self.p = DARK if dark else LIGHT
        self.parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-labelledby="title desc">',
                      f'<title id="title">{escape(title)}</title><desc id="desc">{escape(description)}</desc>',
                      '<style>text{font-family:Helvetica,Arial,sans-serif} .icon{fill:none;stroke-linecap:round;stroke-linejoin:round}</style>']

    def raw(self, value):
        self.parts.append(value)

    def rect(self, x, y, w, h, fill, stroke="none", r=0, sw=1):
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    def text(self, x, y, value, size=16, fill=None, weight=400, anchor="start"):
        self.raw(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill or self.p["text"]}" font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>')

    def lines(self, x, y, value, width=41, size=14, gap=19, fill=None):
        for paragraph in value.split("\n"):
            for line in textwrap.wrap(paragraph, width=width) or [""]:
                self.text(x, y, line, size, fill or self.p["muted"])
                y += gap
        return y

    def line(self, x1, y1, x2, y2, stroke=None, sw=1):
        self.raw(f'<path d="M{x1} {y1}H{x2}" fill="none" stroke="{stroke or self.p["rule"]}" stroke-width="{sw}"/>' if y1 == y2 else
                 f'<path d="M{x1} {y1}L{x2} {y2}" fill="none" stroke="{stroke or self.p["rule"]}" stroke-width="{sw}"/>')

    def icon(self, x, y, name, size=24, colour=None):
        paths = {
            "scanner": '<path d="M4 8l15-4M4 11h16l2 6v3H2v-3zM3 16h18M6 18h1"/>',
            "printer": '<path d="M6 9V3h12v6M6 17H3V9h18v8h-3M6 14h12v7H6zM17 11h1"/>',
            "copy": '<path d="M8 7H3v14h12v-4M8 3h8l5 5v9H8zM16 3v5h5"/>',
            "device": '<rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 12h14M12 17v4M7 21h10M9 14h6"/>',
            "sidebar": '<rect x="2" y="4" width="20" height="16" rx="3"/><path d="M9 4v16M5 8h1M5 12h1"/>',
            "inspector": '<rect x="2" y="4" width="20" height="16" rx="3"/><path d="M15 4v16M18 8h1M18 12h1"/>',
            "folder": '<path d="M2 7V4h7l3 3h10v13H2zM2 9h20"/>',
            "fit": '<path d="M9 9L3 3M3 8V3h5M15 15l6 6M16 21h5v-5"/>',
            "actual": '<circle cx="10" cy="10" r="7"/><path d="M15 15l6 6M9 7l2-1v8M9 14h4"/>',
            "rotate": '<path d="M7 7a7 7 0 0112 3M19 5v5h-5"/><rect x="4" y="11" width="10" height="10" rx="2"/>',
            "export": '<path d="M8 9H4v12h16V9h-4M12 15V2M8 6l4-4 4 4"/>',
        }
        self.raw(f'<g class="icon" transform="translate({x} {y}) scale({size/24})" stroke="{colour or self.p["accent"]}" stroke-width="1.6">{paths[name]}</g>')

    def button(self, x, y, label, w=306, disabled=False, h=31):
        p = self.p
        self.rect(x, y, w, h, p["disabled"] if disabled else p["control"], p["rule"] if disabled else p["border"], 6)
        self.text(x+w/2, y+21, label, 14, p["disabled_text"] if disabled else p["text"], anchor="middle")

    def select(self, x, y, value, w=306):
        self.rect(x, y, w, 32, self.p["control"], self.p["border"], 6)
        self.text(x+12, y+22, value, 15)
        self.raw(f'<path d="M{x+w-22} {y+13}l4-4 4 4m-8 6l4 4 4-4" fill="none" stroke="{self.p["muted"]}" stroke-width="1.5"/>')

    def check(self, x, y, label, checked=False):
        self.rect(x, y, 16, 16, self.p["accent"] if checked else self.p["control"], self.p["accent"] if checked else self.p["border"], 3)
        if checked:
            self.raw(f'<path d="M{x+3} {y+8}l3 3 7-7" fill="none" stroke="white" stroke-width="2"/>')
        self.text(x+24, y+13, label, 14)

    def section(self, y, label, expanded=True):
        if expanded:
            path = f'M1080 {y-8}l4 4 4-4'
        else:
            path = f'M1082 {y-10}l4 4-4 4'
        self.raw(f'<path d="{path}" fill="none" stroke="{self.p["muted"]}" stroke-width="1.5"/>')
        self.text(1097, y, label, 16, weight=600)

    def slider(self, y, label):
        self.text(1080, y, label, 14, self.p["muted"])
        self.line(1082, y+17, 1374, y+17, self.p["track"], 4)
        self.line(1082, y+17, 1228, y+17, self.p["accent"], 4)
        self.raw(f'<circle cx="1228" cy="{y+17}" r="8" fill="{self.p["control"]}" stroke="{self.p["border"]}"/>')

    def save(self, name):
        (OUT / f"{name}.svg").write_text("\n".join(self.parts + ["</svg>"]) + "\n")


def chrome(d, selected="Scan", cropped=False, exports=0, copy_ready=False):
    p = d.p
    d.rect(0, 0, W, H, p["bg"])
    d.rect(28, 28, 1384, 988, p["window"], p["border"], 14)
    d.raw('<clipPath id="windowClip"><rect x="28" y="28" width="1384" height="988" rx="14"/></clipPath><g clip-path="url(#windowClip)">')
    d.rect(28, 28, 172, 988, p["sidebar"])
    d.rect(200, 28, 1212, 72, p["chrome"])
    d.rect(1054, 100, 358, 916, p["inspector"])
    d.line(200, 100, 1412, 100)
    d.line(200, 100, 200, 1016)
    d.line(1054, 100, 1054, 1016)
    for x in [53, 77, 101]:
        d.raw(f'<circle cx="{x}" cy="60" r="6" fill="{p["border"]}"/>')
    d.text(223, 58, "BJC-85 Utility — Fixture", 19, weight=600)
    d.text(223, 80, "Independent BJC-85 / IS-12 project", 12, p["muted"])
    for x, w, names in [(870, 78, ["sidebar", "folder"]), (960, 116, ["fit", "actual", "rotate"]), (1088, 116, ["export", "printer", "inspector"])]:
        d.rect(x, 43, w, 38, p["window"], p["border"], 8)
        for i, name in enumerate(names):
            d.icon(x+9+i*38, 51, name, 22, p["disabled_text"] if name == "printer" else p["text"])
    for i, (name, icon) in enumerate(zip(["Scan", "Print", "Copy", "Device"], ["scanner", "printer", "copy", "device"])):
        y = 126+i*47
        if name == selected:
            d.rect(40, y-11, 148, 38, p["selected"], r=7)
        d.icon(53, y-3, icon, 22)
        d.text(88, y+14, name, 17, weight=600 if name == selected else 400)
    d.text(223, 134, "Fixture · Printer ready" if copy_ready else "Fixture · Not connected", 16, weight=600)
    d.text(223, 158, "Fixture · Synthetic document retained · No physical jobs", 14, p["muted"])
    d.rect(219, 181, 816, 771, p["canvas"], r=7)
    sample_page(d, cropped)
    revision = 4 if cropped else 0
    d.text(223, 982, f"Imported image · revision {revision} · not exported", 18, weight=600)
    d.text(223, 1005, f'Selection {"6.00 × 8.00" if cropped else "8.00 × 10.80"} in · 360 dpi · {exports} exports', 13, p["muted"])
    d.raw('</g>')


def sample_page(d, cropped=False):
    # An original sample document, in the reference illustration's muted palette.
    x, y, w, h = 363, 206, 528, 712.8
    d.rect(x+4, y+5, w, h, "#cbd2db", r=0)
    d.rect(x, y, w, h, "white", "#cbd2db")
    d.text(x+42, y+63, "PAPER / COLOUR / FORM", 12, "#768394", 600)
    d.text(x+42, y+111, "A study in colour", 32, "#242832", 600)
    d.text(x+42, y+140, "A sample page for a new chapter.", 15, "#626975")
    for i, width in enumerate([437, 414, 429]):
        d.rect(x+42, y+173+i*19, width, 6, "#d9dfe7", r=2)
    for bx, width, colour in [(42, 140, "#c5dce5"), (194, 140, "#d9c8de"), (346, 140, "#e8dfb5")]:
        d.rect(x+bx, y+262, width, 220, colour)
    d.text(x+42, y+517, "01  /  SKY", 11, "#626975")
    d.text(x+194, y+517, "02  /  LILAC", 11, "#626975")
    d.text(x+346, y+517, "03  /  OCHRE", 11, "#626975")
    for i, width in enumerate([433, 397, 421]):
        d.rect(x+42, y+549+i*19, width, 6, "#d9dfe7", r=2)
    d.line(x+42, y+638, x+w-42, y+638, "#d9dfe7")
    d.text(x+42, y+670, "Illustrative document", 12, "#768394")
    d.text(x+w-42, y+670, "01", 12, "#768394", anchor="end")
    if cropped:
        cx, cy, cw, ch = x+33, y+49.5, 396, 528
        d.raw(f'<path d="M{x} {y}H{x+w}V{y+h}H{x}Z M{cx} {cy}V{cy+ch}H{cx+cw}V{cy}Z" fill="#293342" fill-opacity=".2" fill-rule="evenodd"/>')
        d.rect(cx, cy, cw, ch, "none", "white", sw=5)
        d.rect(cx, cy, cw, ch, "none", d.p["accent"], sw=2)
        for px, py in [(cx, cy), (cx+cw, cy), (cx, cy+ch), (cx+cw, cy+ch)]:
            d.rect(px-4, py-4, 8, 8, d.p["accent"])


def scan_inspector(d):
    x=1080
    d.section(132, "Acquire")
    d.text(x, 159, "Preset", 13, d.p["muted"])
    d.select(x, 170, "Photo")
    d.lines(x, 224, "Original preset: colour matching on. Canon colour matching is unavailable; this scan uses the saved white reference.", width=44, size=13, gap=17)
    d.text(x, 287, "Output mode", 13, d.p["muted"])
    d.select(x, 298, "Colour")
    d.text(x, 355, "Resolution for next scan", 13, d.p["muted"])
    d.select(x, 366, "360 dpi", 146)
    d.check(x, 414, "Sheet fed bottom first", True)
    d.button(x, 446, "Scan loaded page…", disabled=True)
    d.button(x, 486, "Prescan loaded page…", disabled=True)
    d.lines(x, 540, "Prescan ejects the sheet. Reload the same original before a final scan. Live acquisition preview omits final host adjustments.", width=45, size=13, gap=17)
    d.line(x, 605, 1386, 605)
    d.section(632, "Crop & orientation")
    for i, text in enumerate(["Crop dimensions…", "Clear selection", "Rotate clockwise"]):
        d.button(x, 648+i*40, text)
    d.lines(x, 782, "Selection is host cropping after full-page acquisition. The lossless master stays unchanged.", width=46, size=13, gap=17)
    d.line(x, 828, 1386, 828)
    d.section(855, "Adjustments")
    d.slider(880, "Brightness")
    d.slider(926, "Contrast")
    d.slider(972, "B&W threshold")
    d.rect(1400, 114, 4, 645, d.p["track"], r=2)
    # Remaining adjustments and collapsed Calibration continue below the fold,
    # exactly as the app's scrolling inspector does at this window height.


PRINT_NOTE = "BC-11e · plain paper · automatic feed · 360 dpi\nLetter colour is physically verified. A4, multiple copies and monochrome still need physical acceptance. The current black ink channel needs attention."


def print_fields(d, y, copies="1"):
    x=1080
    d.text(x, y, "Paper size", 13, d.p["muted"])
    d.select(x, y+12, "Letter", 172)
    d.text(x, y+70, "Copies (1–999)", 13, d.p["muted"])
    d.rect(x, y+82, 112, 32, d.p["control"], d.p["border"], 6)
    d.text(x+12, y+104, copies, 15)
    d.check(x, y+135, "Colour printing", True)
    d.text(x, y+184, "Print quality", 13, d.p["muted"])
    d.select(x, y+197, "Normal", 172)
    return d.lines(x, y+262, PRINT_NOTE, width=43, size=13, gap=18)


def print_inspector(d):
    d.text(1080, 134, "Print document", 20, weight=600)
    bottom=print_fields(d, 170)
    d.button(1080, bottom+10, "Print document…", disabled=True)
    d.button(1080, bottom+54, "Prepare printing…", disabled=True)
    d.text(1080, bottom+124, "No print job submitted", 14, d.p["muted"])
    d.button(1080, bottom+144, "Recheck job status", disabled=True)
    d.button(1080, bottom+188, "Open queue details", disabled=True)
    d.lines(1080, bottom+258, "Settings apply to this document. Other apps keep their normal Command-P dialog. Queue completion does not verify ink on paper.", width=43, size=13)


def copy_inspector(d):
    d.text(1080, 134, "Copy", 20, weight=600)
    d.lines(1080, 170, "3. Ready to print retained copy\nReview settings, then choose Print retained copy.", width=42, size=14)
    for y, label, disabled in [(242, "Edit retained image", False), (286, "Copy loaded original", True), (330, "Continue after cartridge swap…", True), (374, "Print retained copy", True)]:
        d.button(1080, y, label, disabled=disabled)
    bottom=print_fields(d, 449, "2")
    d.button(1080, bottom+8, "Reset copy session")
    d.button(1080, bottom+52, "Recheck job status", disabled=True)
    d.button(1080, bottom+96, "Open queue details", disabled=True)


def device_inspector(d):
    d.text(1080, 134, "Device", 20, weight=600)
    for i, label in enumerate(["Connect scanner", "Prepare printing…", "Open Image Capture"]):
        d.button(1080, 157+i*44, label, disabled=True)
    d.lines(1080, 307, "Scanner readiness is detected by native status replies. A BC-11e print cartridge is operator-confirmed; no automatic cartridge or ink-level detection is claimed.", width=42, size=13)
    for y, label, disabled in [(425, "Import white reference…", True), (469, "Calibration guidance…", False), (513, "Show private files", False)]:
        d.button(1080, y, label, disabled=disabled)
    d.line(1080, 572, 1386, 572)
    d.text(1080, 606, "Recovery & maintenance", 19, weight=600)
    d.lines(1080, 638, "If recovery is required, preserve the capture and inspect the printer before any further physical work. Restarting never clears a recovery marker.", width=42, size=13)
    d.button(1080, 750, "Recheck device availability", disabled=True)
    d.lines(1080, 815, "Cleaning, deep cleaning, alignment and ink levels are unavailable until verified. The historical black-ink delivery fault is separate from driver outcomes.", width=42, size=13)
    d.lines(1080, 932, "Independent BJC-85 / IS-12 utility. No Canon endorsement, executables, or artwork.", width=43, size=13)


def settings(d):
    p=d.p
    d.rect(0, 0, W, H, p["bg"])
    # The app uses a separate, modest Settings window, not a fifth workspace.
    d.rect(314, 239, 812, 574, p["window"], p["border"], 13)
    d.raw('<clipPath id="settingsClip"><rect x="314" y="239" width="812" height="574" rx="13"/></clipPath><g clip-path="url(#settingsClip)">')
    d.rect(314, 239, 812, 60, p["chrome"])
    for x in [342, 366, 390]:
        d.raw(f'<circle cx="{x}" cy="269" r="6" fill="{p["border"]}"/>')
    d.text(720, 276, "Settings", 18, weight=600, anchor="middle")
    d.text(354, 355, "Privacy & storage", 25, weight=600)
    d.check(354, 389, "Retain diagnostic captures", False)
    d.lines(354, 449, "Completed captures are expendable after their document master is retained. Unexported documents, Copy images, active workers, and unresolved recovery evidence are protected.", width=80, size=17, gap=25)
    d.lines(354, 558, "Closed, exported documents may expire after 7 days. Unexported documents stay until you discard them. Storage is limited to 100 documents / 2 GB; new imports stop at the limit.", width=80, size=17, gap=25)
    d.button(354, 673, "Delete completed diagnostics…", w=360, h=36)
    d.button(354, 729, "Show private files", w=220, h=36)
    d.raw('</g>')


SHOTS = [
    ("01-scan-workspace", "Scan workspace", "Crop and adjust a retained document in the current three-pane AppKit workspace.", "Scan", False),
    ("02-print-workspace", "Print workspace", "Letter paper, copies, colour, quality and explicit print-job controls.", "Print", False),
    ("03-copy-workflow", "Copy workflow", "A synthetic retained copy at the ready-to-print stage; physical actions are disabled in fixture mode.", "Copy", False),
    ("04-device-workspace", "Device workspace", "Connection, calibration guidance and recovery information beside the retained document.", "Device", False),
    ("05-dark-workspace", "Dark Mode", "The same Scan workspace in a dark palette, keeping the document paper white.", "Scan", True),
    ("06-privacy-settings", "Privacy & storage", "The separate Settings window with diagnostic retention off and document-storage policy.", "Settings", False),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest=[]
    for i, (name, title, description, workspace, dark) in enumerate(SHOTS, 1):
        d=Drawing(f"BJC-85 Utility — {title} (illustrative UI mockup)", description+" Not a captured screenshot or a hardware-test result.", dark)
        if workspace == "Settings":
            settings(d)
        else:
            chrome(d, workspace, cropped=workspace == "Scan", exports=2 if workspace == "Scan" else 0, copy_ready=workspace == "Copy")
            {"Scan": scan_inspector, "Print": print_inspector, "Copy": copy_inspector, "Device": device_inspector}[workspace](d)
        d.text(29, 1050, f"{i:02d} / {title}", 14, weight=600)
        d.text(1411, 1050, "Illustrative UI mockup · Synthetic content · 14 Sep 2026", 13, d.p["muted"], anchor="end")
        d.save(name)
        manifest.append(dict(file=f"{name}.svg", png=f"{name}.png", title=title, description=description,
                             kind="illustrative-ui-mockup", svg_size=[W,H], png_size=[W*2,H*2], date="2026-09-14"))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(f"Wrote {len(SHOTS)} SVG mockups and their manifest to {OUT}")


if __name__ == "__main__":
    main()
