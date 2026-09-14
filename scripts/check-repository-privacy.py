#!/usr/bin/env python3
"""Check repository content without printing matched private values.

By default inspect tracked working files; --history also inspects every blob,
commit and annotated tag reachable from branches, tags and remote-tracking refs.
--all-refs includes local editor/recovery refs. --staged checks the index.
Optional --private-values is a LOCAL, UNTRACKED JSON array of known identifiers.
Screenshot pixels still require a separate visual/OCR review.
"""
import argparse
import base64
from collections import Counter
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UUID = re.compile(r"(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b")
SYNTHETIC_UUID = re.compile(r"(?i)^00000000-0000-4000-8000-[0-9a-f]{12}$")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
SAFE_EMAIL = re.compile(r"(?i)@(?:users\.noreply\.github\.com|example\.(?:com|org|net)|[^@]+\.invalid)$")
HOME = re.compile(r"/(?:Users|home)/([A-Za-z0-9._-]+)")
SAFE_USER = {"REDACTED", "REDACTED-USER", "USER", "YOUR_USER", "USERNAME", "example"}
SERIAL = re.compile(r'''(?ix)["'](?:serial(?:number)?|serial_number|hardware_uuid|machine_uuid|device_uuid)["']\s*[:=]\s*["']([^"'\n]+)["']''')
SAFE_SERIAL = re.compile(r"(?i)^(?:TEST(?:[-_].*)?|FAKE(?:[-_].*)?|OTHER|UNKNOWN|REDACTED|NONE|N/A|IS12-NATIVE[-A-Z]*|%s)$")
PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"),
    "credential-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{12,}|sk-[A-Za-z0-9_-]{24,}|AIza[0-9A-Za-z_-]{30,})"),
    "embedded-url-credential": re.compile(r"https?://[^\s/:]+:[^\s/@]+@"),
    "mac-address": re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"),
    "private-temporary-path": re.compile(r"/(?:private/)?var/folders/[A-Za-z0-9_-]+/"),
    "local-hostname": re.compile(r"(?i)\b[A-Za-z0-9-]+\.local\b"),
    "print-account-name": re.compile(r"(?im)^\s*(?:requesting-user-name|job-originating-user-name)\s*\([^\n)]*\)\s*=\s*(?!REDACTED\b|TEST\b|anonymous\b)\S+"),
    "authorization-header": re.compile(r"(?i)\bAuthorization\s*:\s*(?:Bearer|Basic)\s+[A-Za-z0-9+/=_-]{12,}"),
}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def jpeg_metadata(data):
    """Return metadata marker types before the JPEG image stream."""
    markers = set()
    i = 2
    while i < len(data):
        if data[i] != 255:
            return {"invalid-jpeg"}
        while i < len(data) and data[i] == 255:
            i += 1
        if i >= len(data):
            return {"invalid-jpeg"}
        marker = data[i]
        i += 1
        if marker in (0xDA, 0xD9):
            break
        if i + 2 > len(data):
            return {"invalid-jpeg"}
        length = int.from_bytes(data[i:i+2], "big")
        if length < 2 or i + length > len(data):
            return {"invalid-jpeg"}
        if 0xE1 <= marker <= 0xEF or marker == 0xFE:
            markers.add("image-metadata")
        i += length
    return markers


def inspect(data, known=()):
    found = set()
    if any(value in data for value in known):
        found.add("known-private-value")
    if data.startswith(b"\xff\xd8"):
        return found | jpeg_metadata(data)
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        i = 8
        while i + 12 <= len(data):
            length = int.from_bytes(data[i:i+4], "big")
            kind = data[i+4:i+8]
            if kind in (b"tEXt", b"zTXt", b"iTXt", b"eXIf"):
                found.add("image-metadata")
            i += 12 + length
        return found
    if b"\0" in data:
        # Protocol fixtures need exact known-value checks; compressed image
        # bytes must not be mistaken for an email or a credential.
        return found
    try:
        text = data.decode("utf-8").replace("\\/", "/")
    except UnicodeDecodeError:
        return found | {"unreviewed-binary"}
    for name, pattern in PATTERNS.items():
        if pattern.search(text):
            found.add(name)
    if any(m.group(1) not in SAFE_USER for m in HOME.finditer(text)):
        found.add("personal-home-path")
    if any(not SAFE_EMAIL.search(m.group()) for m in EMAIL.finditer(text)):
        found.add("email-address")
    if any(not SYNTHETIC_UUID.fullmatch(m.group()) for m in UUID.finditer(text)):
        found.add("non-synthetic-uuid")
    if any(not SAFE_SERIAL.fullmatch(m.group(1)) for m in SERIAL.finditer(text)):
        found.add("device-serial")
    # Java release versions resemble IPv4 addresses; only explicit dependency
    # lines receive this exception. Every other non-loopback address is reviewed.
    for line in text.splitlines():
        if "jdk-" in line or "Temurin JDK" in line:
            continue
        for value in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", line):
            try:
                ip = ipaddress.ip_address(value)
            except ValueError:
                continue
            if not (ip.is_loopback or ip.is_unspecified or ip.is_multicast
                    or str(ip).startswith(("192.0.2.", "198.51.100.", "203.0.113."))):
                found.add("network-address")
    return found


def known_variants(values):
    variants = set()
    for value in values:
        if not value:
            continue
        raw = value.encode()
        variants.update([raw, value.encode("utf-16le"), value.encode("utf-16be"),
                         base64.b64encode(raw), raw.hex().encode(),
                         raw.hex().upper().encode(),
                         value.replace("/", "\\/").encode(),
                         " ".join(f"{b:02x}" for b in raw).encode(),
                         " ".join(f"{b:02X}" for b in raw).encode()])
    return variants


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--all-refs", action="store_true", help="Also inspect local editor/recovery refs that are not normally pushed")
    parser.add_argument("--pre-push", action="store_true", help="Read Git pre-push ref updates from stdin and inspect every proposed object")
    parser.add_argument("--staged", action="store_true")
    parser.add_argument("--private-values", type=Path)
    args = parser.parse_args()
    known = known_variants(json.loads(args.private_values.read_text())) if args.private_values else ()
    hits = []
    checked = Counter()
    seen = set()

    def check(data, path, scope, oid=None):
        checked[scope] += 1
        categories = inspect(data, known)
        path_categories = inspect(path.encode(), known)
        if path_categories:
            categories |= path_categories | {"private-filename"}
            path = "(filename withheld)"
        if categories:
            # Object IDs are deliberately omitted: a report should not link
            # readers back to an old object containing the private value.
            hits.append({"scope": scope, "path": path, "categories": sorted(categories)})

    for name in git("ls-files", "-z").decode().split("\0"):
        if not name:
            continue
        if args.staged:
            check(git("show", ":" + name), name, "index")
        elif (ROOT/name).is_file():
            check((ROOT/name).read_bytes(), name, "worktree")
    revisions = []
    if args.history:
        revisions += ["--branches", "--tags", "--remotes"]
    if args.all_refs:
        revisions += ["--all"]
    if args.pre_push:
        for line in sys.stdin:
            fields = line.split()
            if len(fields) != 4:
                parser.error("Malformed pre-push ref update")
            local_oid = fields[1]
            if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", local_oid):
                parser.error("Invalid pre-push object ID")
            if local_oid.strip("0"):
                revisions.append(local_oid)
    if revisions:
        for line in git("rev-list", "--objects", *revisions).decode().splitlines():
            oid, _, name = line.partition(" ")
            if oid in seen:
                continue
            seen.add(oid)
            kind = git("cat-file", "-t", oid).decode().strip()
            if kind in ("blob", "commit", "tag"):
                check(git("cat-file", kind, oid), name or "(metadata)", "history-"+kind, oid)
    print(json.dumps({"checked": dict(checked), "findings": hits,
                      "limits": "Pattern and metadata checks; screenshot pixels require separate review. Public GitHub identity and synthetic placeholders are allowed."}, indent=2))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
