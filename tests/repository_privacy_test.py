"""Regression checks for value redaction, image parsing, and history coverage."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-repository-privacy.py"
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
        chunk = lambda kind, data: len(data).to_bytes(4, "big") + kind + data + bytes(4)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IDAT", payload) + chunk(b"IEND", b"")
        self.assertFalse(privacy.inspect(png))
        self.assertIn("image-metadata", privacy.inspect(png + chunk(b"tEXt", payload)))
        self.assertFalse(privacy.inspect(b"\xff\xd8\xff\xda" + payload))
        self.assertIn("image-metadata", privacy.inspect(b"\xff\xd8\xff\xe1\x00\x05abc\xff\xda"))
        self.assertIn("invalid-jpeg", privacy.inspect(b"\xff\xd8\xff"))

    def test_deleted_secret_still_found_in_history(self):
        with tempfile.TemporaryDirectory(prefix="privacy-check-") as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/check-repository-privacy.py")
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
            self.assertTrue(any(f["scope"] == "history-blob" and f["path"] == "evidence.txt" for f in report["findings"]))
            self.assertNotIn("fixture-owner", history.stdout)

    def test_explicit_push_of_local_recovery_ref_is_checked(self):
        with tempfile.TemporaryDirectory(prefix="privacy-ref-check-") as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/check-repository-privacy.py")
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
