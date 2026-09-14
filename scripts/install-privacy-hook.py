#!/usr/bin/env python3
"""Install the repository hook without overwriting an existing hook setup."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)

existing = git("config", "--get", "core.hooksPath")
if existing.returncode == 0 and existing.stdout.strip() != ".githooks":
    sys.exit("Existing core.hooksPath preserved. Integrate .githooks/pre-push manually; installation stopped.")
if existing.returncode not in (0, 1):
    sys.exit("Unable to inspect hook configuration; installation stopped.")
if existing.returncode == 1:
    hooks = Path(git("rev-parse", "--git-path", "hooks").stdout.strip())
    if not hooks.is_absolute(): hooks = root / hooks
    if hooks.exists() and any(p.is_file() and not p.name.endswith(".sample") for p in hooks.iterdir()):
        sys.exit("Existing hooks preserved. Integrate .githooks/pre-push manually; installation stopped.")
hook = root / ".githooks/pre-push"
if not hook.is_file() or not os.access(hook, os.X_OK):
    sys.exit("Tracked pre-push hook is missing or not executable.")
result = git("config", "--local", "core.hooksPath", ".githooks")
if result.returncode: sys.exit("Unable to install repository-local hook configuration.")
print("Repository-local pre-push hook installed. Push requires restricted local private-value configuration.")
