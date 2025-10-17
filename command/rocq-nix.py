#!/usr/bin/env python3

import os
import sys

from pathlib import Path

flake_root = Path(__file__).resolve().parent

os.execvp(
    "nix",
    [
        "nix",
        "--extra-experimental-features",
        "nix-command flakes",
        "run",
        "--impure",
        "--expr",
        "{ path }: with builtins; (getFlake path).packages.${currentSystem}",
        "--argstr",
        "path",
        flake_root,
        "rocq-nix",
        "--",
        f"--flake-root={flake_root}",
        *sys.argv[1:],
    ],
)
