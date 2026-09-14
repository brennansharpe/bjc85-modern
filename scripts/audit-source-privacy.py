"""Compatibility entry point for the repository privacy check.

Includes reachable history by default. Reports categories and paths without
printing matched values. See docs/REPOSITORY-PRIVACY.md for scope and limits.
"""
from pathlib import Path
import runpy
import sys

if "--history" not in sys.argv:
    sys.argv.insert(1, "--history")
runpy.run_path(str(Path(__file__).with_name("check-repository-privacy.py")), run_name="__main__")
