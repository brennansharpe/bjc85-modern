#!/usr/bin/env python3
"""Check repository content without printing matched private values.

By default inspect tracked working files; --history also inspects every blob,
commit and annotated tag reachable from branches, tags and remote-tracking refs.
--all-refs includes local editor/recovery refs. --staged checks the index.
Optional --private-values is a LOCAL, UNTRACKED JSON array of known identifiers.
Screenshot pixels still require a separate visual/OCR review.
"""
import argparse
import hashlib
import os
import stat
import base64
from collections import Counter
import ipaddress
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import privacy_formats as formats

ROOT = Path(__file__).resolve().parents[1]
UUID = re.compile(r"(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b")
SYNTHETIC_UUID = re.compile(r"(?i)^00000000-0000-4000-8000-[0-9a-f]{12}$")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
SAFE_EMAIL = re.compile(r"(?i)@(?:users\.noreply\.github\.com|example\.(?:com|org|net)|[^@]+\.invalid)$")
HOME = re.compile(r"/(?:Users|home)/([A-Za-z0-9._-]+)")
SAFE_USER = {"REDACTED", "REDACTED-USER", "USER", "YOUR_USER", "USERNAME", "example"}
SERIAL = re.compile(r'''(?ix)["'](?:serial(?:number)?|serial_number|hardware_uuid|machine_uuid|device_uuid)["']\s*[:=]\s*["']([^"'\n]+)["']''')
PROSE_SERIAL = re.compile(r"(?i)\bserial(?:[ _-]*(?:number|no\.?))?[ \t]*(?:is|was|[:=#])?[ \t]*[`\"']?([A-Z0-9][A-Z0-9_-]{5,})")
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
    # Bound Git listings independently of per-blob/container budgets. A large
    # error stream must not deadlock traversal or expose private path names.
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(["git", "-C", str(ROOT), *args], stdout=subprocess.PIPE, stderr=errors)
        data = process.stdout.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            process.kill(); process.wait()
            raise ValueError("git-output-inspection-limit")
        if process.wait() != 0:
            raise ValueError("git-inspection-failed")
        return data


def inspect_text(text):
    found = set()
    text = text.replace("\\/", "/")
    for name, pattern in PATTERNS.items():
        if pattern.search(text):
            found.add(name)
    if any(m.group(1) not in SAFE_USER for m in HOME.finditer(text)):
        found.add("personal-home-path")
    if any(m.group() != "noreply@github.com" and not SAFE_EMAIL.search(m.group()) for m in EMAIL.finditer(text)):
        found.add("email-address")
    if any(not SYNTHETIC_UUID.fullmatch(m.group()) for m in UUID.finditer(text)):
        found.add("non-synthetic-uuid")
    if any(not SAFE_SERIAL.fullmatch(m.group(1)) for m in SERIAL.finditer(text)):
        found.add("device-serial")
    for match in PROSE_SERIAL.finditer(text):
        value = match.group(1)
        if any(c.isdigit() for c in value) and not SAFE_SERIAL.fullmatch(value):
            found.add("device-serial-prose")
    # Only the exact JDK version token is exempt, never its surrounding line.
    for line in text.splitlines():
        line = re.sub(r"(?:jdk-|Temurin JDK )\d+(?:\.\d+){3}(?:\+\d+)?", "JDK_VERSION", line)
        for value in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", line):
            try:
                ip = ipaddress.ip_address(value)
            except ValueError:
                continue
            if not (ip.is_loopback or ip.is_unspecified or ip.is_multicast
                    or str(ip).startswith(("192.0.2.", "198.51.100.", "203.0.113."))):
                found.add("network-address")
    return found


def text_views(data):
    # Search after NULs and other binary delimiters, then both UTF-16 byte orders
    # and alignments. Image entropy is never passed to this function.
    yield data.decode("utf-8", errors="replace")
    for encoding in ("utf-16le", "utf-16be"):
        for offset in (0, 1):
            raw = data[offset:]
            raw = raw[:len(raw) - len(raw) % 2]
            if raw:
                yield raw.decode(encoding, errors="replace")


def inspect(data, known=(), reviewed_binary=False, depth=0, budget=None):
    found = set()
    if budget is None: budget = {"bytes": formats.MAX_EXPANDED, "members": formats.MAX_MEMBERS}
    if len(data) > formats.MAX_BYTES:
        return {"file-inspection-limit"}
    if any(value in data for value in known):
        found.add("known-private-value")
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        issues, metadata = formats.png(data)
        for payload in metadata:
            for text in text_views(payload): found |= inspect_text(text)
            if any(value in payload for value in known): found.add("known-private-value")
        return found | issues
    if data.startswith(b"\xff\xd8"):
        issues, metadata = formats.jpeg(data)
        for payload in metadata:
            for text in text_views(payload): found |= inspect_text(text)
            if any(value in payload for value in known): found.add("known-private-value")
        return found | issues
    issues = formats.archive(data, lambda child, level: inspect(child, known, False, level, budget), depth, budget)
    if issues is not None:
        return found | issues
    for text in text_views(data): found |= inspect_text(text)
    try:
        decoded = data.decode("utf-8")
        ordinary_text = all(c.isprintable() or c in "\t\n\r\f" for c in decoded)
    except UnicodeDecodeError:
        ordinary_text = False
    utf16 = False
    bom = data.startswith((b"\xff\xfe", b"\xfe\xff"))
    if bom or (len(data) > 8 and max(data[::2].count(0), data[1::2].count(0)) > len(data) * 0.30):
        for encoding in ("utf-16le", "utf-16be"):
            try:
                text = data.decode(encoding).lstrip("\ufeff")
            except UnicodeDecodeError:
                continue
            printable = all(c.isprintable() or c in "\t\n\r\f" for c in text)
            if printable and (bom or sum(ord(c) < 128 for c in text) > len(text) * 0.95): utf16 = True
        if bom and not utf16: found.add("malformed-utf16")
    if not ordinary_text and not utf16 and not reviewed_binary:
        found.add("unsupported-binary-inspection")
    return found


def load_private_config(path, required=False):
    if path is None:
        if required: raise ValueError("missing-local-private-config")
        return (), "not-configured"
    try:
        path = path.expanduser().absolute()
        info = path.lstat()
        parent = path.parent.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("insecure-local-private-config")
        if parent.st_uid != os.getuid() or parent.st_mode & 0o077:
            raise ValueError("insecure-local-private-config-directory")
        if ROOT.resolve() == path.resolve() or ROOT.resolve() in path.resolve().parents:
            raise ValueError("private-config-must-be-outside-repository")
        if info.st_size > 1024 * 1024: raise ValueError("private-config-too-large")
        document = json.loads(path.read_text())
        values = document if isinstance(document, list) else document.get("known_values")
        if not isinstance(values, list) or len(values) > 4096 or any(not isinstance(v, str) or not 4 <= len(v) <= 1024 for v in values):
            raise ValueError("invalid-local-private-config")
        return known_variants(values), "loaded"
    except (OSError, json.JSONDecodeError, AttributeError):
        raise ValueError("unreadable-local-private-config") from None


def reviewed_binaries():
    path = ROOT / "scripts/privacy-reviewed.json"
    if not path.is_file(): return {}
    data = json.loads(path.read_text())
    return {item["sha256"]: item for item in data.get("binary_fixtures", [])
            if re.fullmatch(r"[0-9a-f]{64}", item.get("sha256", "")) and item.get("reason")}


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
    parser.add_argument("--private-values", "--private-config", dest="private_config", type=Path)
    parser.add_argument("--publication", action="store_true", help="Require restricted local known-value configuration")
    args = parser.parse_args()
    config = args.private_config or os.environ.get("BJC85_PRIVACY_CONFIG")
    if not config:
        result = subprocess.run(["git", "-C", str(ROOT), "config", "--local", "--get", "bjc85.privacyConfig"], capture_output=True, text=True)
        config = result.stdout.strip() or None
    try:
        known, config_status = load_private_config(Path(config) if config else None, args.publication)
        reviews = reviewed_binaries()
    except ValueError as error:
        print(json.dumps({"findings": [], "inspection_errors": [str(error)], "publication_audit": False}))
        return 2
    hits = []
    checked = Counter()
    seen = set()

    def check(data, path, scope, oid=None):
        checked[scope] += 1
        reviewed = hashlib.sha256(data).hexdigest() in reviews
        categories = inspect(data, known, reviewed_binary=reviewed)
        if reviewed: checked["reviewed-protocol-binary"] += 1
        path_categories = inspect(os.fsencode(path), known)
        if path_categories:
            categories |= path_categories | {"private-filename"}
            path = "(filename withheld)"
        if categories:
            # Object IDs are deliberately omitted: a report should not link
            # readers back to an old object containing the private value.
            hits.append({"scope": scope, "path": path, "categories": sorted(categories)})

    def object_data(oid):
        if int(git("cat-file", "-s", oid)) > formats.MAX_BYTES:
            raise ValueError("git-object-inspection-limit")
        return git("cat-file", "-p", oid)

    def check_path(raw, scope):
        # No decoded/quoted Git paths and no object-id deduplication here.
        categories = inspect(raw, known)
        checked[scope] += 1
        if categories:
            hits.append({"scope": scope, "path": "(filename withheld)",
                         "categories": sorted(categories | {"private-filename"})})

    for raw in git("ls-files", "-z").split(b"\0"):
        name = os.fsdecode(raw)
        if not name:
            continue
        if args.staged:
            oid = git("rev-parse", ":" + name).decode().strip()
            check(object_data(oid), name, "index")
        elif (ROOT/name).is_file():
            if (ROOT/name).stat().st_size > formats.MAX_BYTES: raise ValueError("file-inspection-limit")
            check((ROOT/name).read_bytes(), name, "worktree")
    revisions = []
    if args.history:
        revisions += ["--branches", "--tags", "--remotes"]
    if args.all_refs:
        revisions += ["--all"]
    if args.history or args.all_refs:
        patterns = [] if args.all_refs else ["refs/heads", "refs/tags", "refs/remotes"]
        for raw in git("for-each-ref", "--format=%(refname)%00", *patterns).split(b"\0\n"):
            if raw: check_path(raw, "history-ref")
    if args.pre_push:
        for line in sys.stdin:
            fields = line.split()
            if len(fields) != 4:
                parser.error("Malformed pre-push ref update")
            local_oid = fields[1]
            if inspect_text(fields[2]) or any(value in fields[2].encode() for value in known):
                hits.append({"scope": "outgoing-ref", "path": "(ref name withheld)", "categories": ["private-ref-name"]})
            if not fields[2].startswith(("refs/heads/", "refs/tags/")):
                hits.append({"scope": "outgoing-ref", "path": "(ref name withheld)", "categories": ["non-publication-ref"]})
            if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", local_oid):
                parser.error("Invalid pre-push object ID")
            if local_oid.strip("0"):
                revisions.append(local_oid)
    if args.staged:
        # write-tree fails on an unmerged index, which must never pass inspection.
        revisions.append(git("write-tree").decode().strip())
    if revisions:
        trees = set()
        entries = 0
        def walk_tree(oid, prefix=b"", depth=0):
            nonlocal entries
            if depth > 128: raise ValueError("tree-depth-limit")
            for entry in git("ls-tree", "-z", oid).split(b"\0"):
                if not entry: continue
                header, name = entry.split(b"\t", 1)
                mode, kind, child = header.split(b" ")
                entries += 1
                if entries > 1_000_000: raise ValueError("tree-entry-limit")
                path = prefix + name
                check_path(path, "history-path")
                if kind == b"tree": walk_tree(child.decode(), path+b"/", depth+1)
                elif kind == b"commit": raise ValueError("unsupported-gitlink-inspection")

        # Names are checked by tree traversal, not rev-list's arbitrary blob name.
        # --no-object-names keeps arbitrary path bytes out of this line protocol.
        for line in git("rev-list", "--objects", "--no-object-names", *revisions).decode().splitlines():
            oid, _, name = line.partition(" ")
            if oid in seen:
                continue
            seen.add(oid)
            kind = git("cat-file", "-t", oid).decode().strip()
            if kind == "tree": trees.add(oid)
            if kind in ("blob", "commit", "tag"):
                check(object_data(oid), name or "(metadata)", "history-"+kind, oid)
        # Visit each tree as a root as well: prefixes are never memoized away.
        # This includes trees directly targeted by annotated tags/outgoing refs.
        for oid in trees: walk_tree(oid)
    print(json.dumps({"checked": dict(checked), "findings": hits,
                      "private_matching": config_status, "publication_audit": bool(args.publication),
                      "inspection_limits": {"file_bytes": formats.MAX_BYTES, "expanded_bytes": formats.MAX_EXPANDED, "archive_members": formats.MAX_MEMBERS, "archive_depth": formats.MAX_DEPTH},
                      "limits": "Pattern and metadata checks; screenshot pixels require separate review. Public GitHub identity and synthetic placeholders are allowed."}, indent=2))
    return 1 if hits else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        allowed = {"git-output-inspection-limit", "git-inspection-failed", "tree-depth-limit", "tree-entry-limit", "git-object-inspection-limit", "unsupported-gitlink-inspection", "file-inspection-limit"}
        reason = str(error) if isinstance(error, ValueError) and str(error) in allowed else "inspection-failed-or-limit-exceeded"
        print(json.dumps({"findings": [], "inspection_errors": [reason], "publication_audit": False}))
        sys.exit(2)
