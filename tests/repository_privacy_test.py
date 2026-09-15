"""Regression checks for value redaction, image parsing, and history coverage."""
import importlib.util
import sys
import io
import gzip
import zipfile
import zlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-repository-privacy.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("privacy_check", SCRIPT)
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyCheckTest(unittest.TestCase):
    def test_identifiers_and_placeholders(self):
        home = "/Users/" + "fixture-owner/work"
        self.assertIn("personal-home-path", privacy.inspect(home.encode()))
        self.assertIn("personal-home-path", privacy.inspect(home.replace("/", "\\/").encode()))
        self.assertIn("non-synthetic-uuid", privacy.inspect(str(uuid.uuid4()).encode()))
        self.assertIn("email-address", privacy.inspect(("local-user" + "@internal.test").encode()))
        self.assertIn("device-serial", privacy.inspect(json.dumps(dict(serial="PRIVATE" + "12345")).encode()))
        self.assertFalse(privacy.inspect(b'/Users/REDACTED/work user@example.com "serial": "TEST-BJC85-0001" 00000000-0000-4000-8000-000000000001 127.0.0.1'))

    def test_exact_github_service_identity(self):
        for value in ("noreply@github.com", "fixture@users.noreply.github.com", "42+fixture@users.noreply.github.com"):
            self.assertFalse(privacy.inspect(value.encode()))
        for value in ("owner"+"@personal.test", "xnoreply"+"@github.com", "noreply"+"@github.com.evil.test", "other"+"@github.com", "NOREPLY"+"@github.com"):
            self.assertIn("email-address", privacy.inspect(value.encode()))
        mixed = ("author Owner <owner"+"@personal.test>\ncommitter GitHub <noreply@github.com>").encode()
        self.assertIn("email-address", privacy.inspect(mixed))

    def test_historical_names_and_reused_trees(self):
        with tempfile.TemporaryDirectory(prefix="privacy-paths-") as tmp:
            root=Path(tmp); (root/"scripts").mkdir()
            for name in ("check-repository-privacy.py", "privacy_formats.py"):
                shutil.copy2(SCRIPT.with_name(name), root/"scripts"/name)
            env=dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.com", GIT_COMMITTER_EMAIL="fixture@example.com")
            def git(*args):
                return subprocess.check_output(["git","-C",tmp,*args],env=env,stderr=subprocess.PIPE).decode().strip()
            git("init","-q")
            private="fixture"+"@personal.test"
            (root/private).write_text("same")
            (root/(private+" directory\t雪")).mkdir()
            (root/(private+" directory\t雪")/"safe").write_text("same")
            (root/"safe directory").mkdir(); (root/"safe directory/safe").write_text("same")
            git("add","."); git("commit","-qm","Original names")
            git("mv",private,"safe.txt")
            git("rm","-r",private+" directory\t雪")
            git("commit","-qm","Rename and delete")
            oid=git("rev-parse","HEAD")
            git("tag","-a","safe-tag","-m","Safe tag")
            for args, update in ((["--history"],None), (["--pre-push"],f"refs/heads/new {oid} refs/heads/new {'0'*40}\n"), (["--pre-push"],f"refs/tags/new {git('rev-parse','safe-tag')} refs/tags/new {'0'*40}\n")):
                result=subprocess.run([sys.executable,str(root/"scripts"/SCRIPT.name),*args],input=update,text=True,capture_output=True)
                self.assertEqual(result.returncode,1,result.stdout+result.stderr)
                self.assertIn("history-path",result.stdout); self.assertIn("private-filename",result.stdout)
                self.assertNotIn(private,result.stdout+result.stderr)
            (root/private).write_text("same"); git("add",private)
            result=subprocess.run([sys.executable,str(root/"scripts"/SCRIPT.name),"--staged"],text=True,capture_output=True)
            self.assertEqual(result.returncode,1); self.assertNotIn(private,result.stdout)

    def test_credentials_and_print_account(self):
        self.assertIn("credential-token", privacy.inspect(("ghp_" + "a" * 36).encode()))
        self.assertIn("private-key", privacy.inspect(("-----BEGIN " + "PRIVATE KEY-----").encode()))
        self.assertIn("print-account-name", privacy.inspect(b"requesting-user-name (nameWithoutLanguage) = " + b"fixture-owner"))
        self.assertFalse(privacy.inspect(b"requesting-user-name (nameWithoutLanguage) = REDACTED"))

    def test_known_binary_encodings(self):
        value = "device-" + "private-id"
        variants = privacy.known_variants([value])
        for raw in [value.encode("utf-16le"), value.encode().hex().upper().encode(), value.encode()]:
            self.assertIn("known-private-value", privacy.inspect(b"\x00" + raw, variants))

    def test_image_metadata_and_compressed_bytes(self):
        payload = ("local-user" + "@internal.test").encode()
        chunk = lambda kind, data: len(data).to_bytes(4, "big") + kind + data + (zlib.crc32(kind + data) & 0xffffffff).to_bytes(4, "big")
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", bytes(13)) + chunk(b"IDAT", payload) + chunk(b"IEND", b"")
        self.assertFalse(privacy.inspect(png))
        self.assertIn("image-trailing-data", privacy.inspect(png + chunk(b"tEXt", payload)))
        self.assertFalse(privacy.inspect(b"\xff\xd8\xff\xda\x00\x02" + payload + b"\xff\xd9"))
        self.assertIn("image-metadata", privacy.inspect(b"\xff\xd8\xff\xe1\x00\x05abc\xff\xda"))
        self.assertIn("truncated-jpeg", privacy.inspect(b"\xff\xd8\xff"))

    def test_demonstrated_binary_and_prose_misses(self):
        serial = "PRINTER" + "83572941"
        for text in ["Device serial " + serial, "Printer serial: `" + serial + "`", "Serial number is " + serial]:
            self.assertIn("device-serial-prose", privacy.inspect(text.encode()))
        token = ("ghp_" + "Ab3x" * 9).encode()
        self.assertIn("credential-token", privacy.inspect(b"prefix\0" + token))
        header = "-----BEGIN " + "PRIVATE KEY-----"
        for encoding in ("utf-16le", "utf-16be"):
            for prefix in (b"", b"x"):
                self.assertIn("private-key", privacy.inspect(prefix + header.encode(encoding)))
        self.assertIn("unsupported-binary-inspection", privacy.inspect(bytes(range(32))))

    def test_archives_and_limits(self):
        token = ("ghp_" + "Ab3x" * 9).encode()
        self.assertIn("credential-token", privacy.inspect(gzip.compress(token)))
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("evidence.txt", token)
        self.assertIn("credential-token", privacy.inspect(out.getvalue()))
        self.assertIn("archive-inspection-failed", privacy.inspect(b"PK\x03\x04broken"))
        self.assertIn("archive-inspection-failed", privacy.inspect(b"\x1f\x8bbroken"))
        self.assertIn("archive-depth-limit", privacy.inspect(gzip.compress(gzip.compress(gzip.compress(token)))))
        from unittest.mock import patch
        with patch.object(privacy.formats, "MAX_BYTES", 128):
            bomb = gzip.compress(b"z" * 4096)
            self.assertIn("archive-inspection-limit", privacy.inspect(bomb))

    def test_metadata_and_malformed_containers(self):
        token = ("ghp_" + "Ab3x" * 9).encode()
        def chunk(kind, data):
            return len(data).to_bytes(4,"big") + kind + data + (zlib.crc32(kind+data)&0xffffffff).to_bytes(4,"big")
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", bytes(13))
        png += chunk(b"zTXt", b"note\0\0" + zlib.compress(token))
        png += chunk(b"IDAT", b"compressed pixels") + chunk(b"IEND", b"")
        self.assertIn("credential-token", privacy.inspect(png))
        self.assertIn("image-metadata", privacy.inspect(png))
        self.assertIn("truncated-png", privacy.inspect(png[:-3]))
        self.assertIn("invalid-png-crc", privacy.inspect(png[:-1] + bytes([png[-1] ^ 1])))
        jpeg = b"\xff\xd8\xff\xda\x00\x02pixels\xff\xd9"
        self.assertIn("image-trailing-data", privacy.inspect(jpeg + token))
        self.assertIn("credential-token", privacy.inspect(jpeg + token))
        self.assertIn("malformed-utf16", privacy.inspect(b"\xff\xfex"))

    def test_hook_installer_preserves_existing_setup(self):
        with tempfile.TemporaryDirectory(prefix="privacy-hooks-") as tmp:
            root=Path(tmp); (root/"scripts").mkdir(); (root/".githooks").mkdir()
            installer=SCRIPT.with_name("install-privacy-hook.py")
            shutil.copy2(installer, root/"scripts"/installer.name)
            hook=root/".githooks/pre-push"; hook.write_text("#!/bin/sh\nexit 0\n"); hook.chmod(0o755)
            subprocess.run(["git","-C",tmp,"init","-q"],check=True)
            def install():
                return subprocess.run([sys.executable,str(root/"scripts"/installer.name)],capture_output=True,text=True)
            old=root/".git/hooks/pre-commit"; old.write_text("preserve me")
            self.assertNotEqual(install().returncode,0)
            self.assertEqual(old.read_text(),"preserve me")
            old.unlink()
            subprocess.run(["git","-C",tmp,"config","--local","core.hooksPath","custom-hooks"],check=True)
            self.assertNotEqual(install().returncode,0)
            subprocess.run(["git","-C",tmp,"config","--local","--unset","core.hooksPath"],check=True)
            self.assertEqual(install().returncode,0)
            self.assertEqual(install().returncode,0)

    def test_archive_metadata(self):
        token = ("ghp_" + "Ab3x" * 9).encode()
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as z:
            z.writestr("safe.txt", "safe")
            z.comment = token
        self.assertIn("credential-token", privacy.inspect(out.getvalue()))
        out = io.BytesIO()
        with gzip.GzipFile(filename=token.decode(), mode="wb", fileobj=out) as z:
            z.write(b"safe")
        self.assertIn("credential-token", privacy.inspect(out.getvalue()))

    def test_outgoing_new_branch_and_annotated_tag(self):
        with tempfile.TemporaryDirectory(prefix="privacy-outgoing-") as tmp:
            root = Path(tmp); (root / "scripts").mkdir()
            for name in ("check-repository-privacy.py", "privacy_formats.py"):
                shutil.copy2(SCRIPT.with_name(name), root / "scripts" / name)
            env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                       GIT_AUTHOR_EMAIL="fixture@example.com", GIT_COMMITTER_EMAIL="fixture@example.com")
            def git(*args):
                return subprocess.check_output(["git", "-C", tmp, *args], env=env, stderr=subprocess.PIPE).decode().strip()
            git("init", "-q"); git("add", "."); git("commit", "-qm", "Safe root")
            safe = git("rev-parse", "HEAD")
            git("checkout", "-qb", "side")
            value = "PRIVATE" + "83572941"
            (root / "evidence.md").write_text("Printer serial: `" + value + "`")
            git("add", "."); git("commit", "-qm", "Side evidence")
            side = git("rev-parse", "HEAD")
            git("checkout", "--detach", safe)
            git("tag", "-a", "annotated", "-m", "Printer serial: " + value)
            tag = git("rev-parse", "annotated")
            for ref, oid in (("refs/heads/new", side), ("refs/tags/annotated", tag)):
                update = ref + " " + oid + " " + ref + " " + "0" * 40 + "\n"
                result = subprocess.run([sys.executable, str(root / "scripts/check-repository-privacy.py"), "--pre-push"],
                                        input=update, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("device-serial-prose", result.stdout)
                self.assertNotIn(value, result.stdout + result.stderr)
            missing = subprocess.run([sys.executable, str(root / "scripts/check-repository-privacy.py"), "--publication"],
                                     capture_output=True, text=True, env=dict(env, BJC85_PRIVACY_CONFIG=""))
            self.assertEqual(missing.returncode, 2)
            self.assertFalse(json.loads(missing.stdout)["publication_audit"])

    def test_private_configuration_permissions_and_missing_state(self):
        with tempfile.TemporaryDirectory(prefix="privacy-config-") as tmp:
            directory = Path(tmp); directory.chmod(0o700)
            config = directory / "values.json"
            value = "PRIVATE" + "83572941"
            config.write_text(json.dumps({"known_values": [value]})); config.chmod(0o600)
            known, state = privacy.load_private_config(config, True)
            self.assertEqual(state, "loaded")
            self.assertIn("known-private-value", privacy.inspect(value.encode(), known))
            config.chmod(0o644)
            with self.assertRaisesRegex(ValueError, "insecure-local-private-config"):
                privacy.load_private_config(config, True)
            with self.assertRaisesRegex(ValueError, "missing-local-private-config"):
                privacy.load_private_config(None, True)
            self.assertEqual(privacy.load_private_config(None, False)[1], "not-configured")

    def test_deleted_secret_still_found_in_history(self):
        with tempfile.TemporaryDirectory(prefix="privacy-check-") as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/check-repository-privacy.py")
            shutil.copy2(SCRIPT.with_name("privacy_formats.py"), root / "scripts/privacy_formats.py")
            env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                       GIT_AUTHOR_EMAIL="fixture@example.com", GIT_COMMITTER_EMAIL="fixture@example.com")
            def git(*args):
                subprocess.run(["git", "-C", tmp, *args], env=env, check=True, capture_output=True)
            git("init", "-q")
            (root / "evidence.txt").write_text("/Users/" + "fixture-owner/work")
            git("add", ".")
            git("commit", "-qm", "Fixture with private evidence")
            (root / "evidence.txt").write_text("/Users/REDACTED/work")
            git("add", ".")
            git("commit", "-qm", "Sanitize current fixture")
            clean = subprocess.run(["python3", str(root / "scripts/check-repository-privacy.py")], capture_output=True, text=True)
            history = subprocess.run(["python3", str(root / "scripts/check-repository-privacy.py"), "--history"], capture_output=True, text=True)
            self.assertEqual(clean.returncode, 0, clean.stderr)
            self.assertEqual(history.returncode, 1, history.stderr)
            report = json.loads(history.stdout)
            self.assertTrue(any(f["scope"] == "history-blob"  for f in report["findings"]))
            self.assertNotIn("fixture-owner", history.stdout)

    def test_explicit_push_of_local_recovery_ref_is_checked(self):
        with tempfile.TemporaryDirectory(prefix="privacy-ref-check-") as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/check-repository-privacy.py")
            shutil.copy2(SCRIPT.with_name("privacy_formats.py"), root / "scripts/privacy_formats.py")
            subprocess.run(["git", "-C", tmp, "init", "-q"], check=True)
            private_data = "/Users/" + "fixture-owner/private"
            oid = subprocess.check_output(["git", "-C", tmp, "hash-object", "-w", "--stdin"], input=private_data.encode()).decode().strip()
            subprocess.run(["git", "-C", tmp, "update-ref", "refs/local-review/backup", oid], check=True)
            clean = subprocess.run(["python3", str(root / "scripts/check-repository-privacy.py"), "--history"], capture_output=True, text=True)
            self.assertEqual(clean.returncode, 0, clean.stderr)
            update = "refs/local-review/backup " + oid + " refs/local-review/backup " + "0" * 40 + "\n"
            pushed = subprocess.run(["python3", str(root / "scripts/check-repository-privacy.py"), "--pre-push"], input=update, capture_output=True, text=True)
            self.assertEqual(pushed.returncode, 1, pushed.stderr)
            self.assertIn("personal-home-path", pushed.stdout)
            self.assertNotIn("fixture-owner", pushed.stdout)


if __name__ == "__main__":
    unittest.main()
