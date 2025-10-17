import argparse
import json
import os
import sys

from enum import Enum
from pathlib import Path


command_root = Path(__file__).resolve().parent.parent
config_json_path = command_root / "etc" / "config.json"


def error(*msgs: str) -> None:
    for msg in msgs:
        print(msg, file=sys.stderr)
    sys.exit(1)


def cmd_setup(args):
    """Setup development environment with optional integrations."""
    print("Setting up Rocq development environment...")
    if args.rocq:
        print(f"  - Setting up Rocq version: {args.rocq}")
    if args.mise:
        print("  - Configuring mise")
    if args.envrc:
        print("  - Creating .envrc file")
    if args.vsrocq is not None:
        print(f"  - Setting up VSRocq version: {args.vsrocq}")
    if args.emacs:
        print("  - Configuring Emacs integration")


def run_command(*cmd):
    print(f"Command={cmd}")


def cmd_run(args):
    run_command(args.command, *args.args)


def cmd_shell(args):
    if args.shell is None:
        error("Error: rocq-nix shell: SHELL environment variable is not set")
    run_command(args.shell)


def cmd_versions(args):
    pass


# versions:
#   rocq:
#     default: "9.1.0"
#     supported:
#       "9.0.1":
#         vsrocq:
#           - "2.3.1"
#           - "2.3.2"
#           - "2.3.3"
#           - "2.3.4"
#       "9.1.0"
#         vsrocq:
#           - "2.3.1"
#           - "2.3.2"
#           - "2.3.3"
#           - "2.3.4"
# sources:
#   iris:
#     git:
#       url: ...
#       rev: ...


def get_flake_config(config_path: Path):
    if config_path.exists():
        try:
            with open(config_path) as file:
                return json.load(file)
        except Exception as e:
            error(
                f"Error: rocq-nix: Failed to load config from {config_path}",
                f"                 Exception: {e}",
            )
    else:
        error(f"Error: rocq-nix: Config file does not exist at {config_path}")


# setup:
#   rocq:
#     version: "9.1.0"
#   mise: {}
#   envrc: {}
#   emacs: {}
#   vsrocq:
#     version: "3.2.4"
# env:
#   COQPATH: "..."
#   ROCQPATH: "..."
#   ...
# path:
#   - "..."
#   - "..."


def get_state_maybe(flake_root: Path):
    state_path = flake_root / ".rocq-nix" / "state.json"
    if state_path.exists():
        try:
            with open(state_path) as file:
                return json.load(file)
        except Exception as e:
            error(
                f"Error: rocq-nix: Failed to load state from {state_path}",
                f"                 Exception: {e}",
            )
    else:
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="rocq-nix", description="Work with Rocq Prover projects using Nix"
    )
    parser.add_argument(
        "--flake-root", metavar="PATH", required=True, help=argparse.SUPPRESS
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    versions = subparsers.add_parser(
        "versions",
        help="Show available versions of Rocq and VSRocq",
        description="Show available versions of Rocq and VSRocq",
    )
    versions.set_defaults(subcommand=cmd_versions)

    setup = subparsers.add_parser(
        "setup",
        help="Setup Rocq Prover development environment",
        description="Setup Rocq Prover development environment",
    )
    setup.add_argument("--rocq", metavar="VERSION", help="Select a Rocq Prover version")
    setup.add_argument(
        "--vsrocq",
        metavar="VERSION",
        help="Create VSCode settings for a selected VSRocq version",
    )
    setup.add_argument(
        "--emacs",
        action="store_true",
        help="Create an Emacs Proof General configuration",
    )
    setup.add_argument(
        "--envrc", action="store_true", help="Create a direnv .envrc file"
    )
    setup.add_argument(
        "--mise", action="store_true", help="Create a mise.jdx.dev configuration"
    )
    setup.add_argument(
        "--checkout", action="store_true", help="Clone out-of-tree source repositories"
    )
    setup.add_argument(
        "--sync", action="store_true", help="Synchronise sources and environment files"
    )
    setup.add_argument(
        "--force",
        action="store_true",
        help="Overwrite changes to sources and environment files",
    )
    setup.set_defaults(subcommand=cmd_setup)

    run = subparsers.add_parser(
        "run",
        help="Run a command in the Rocq Nix environment",
        description="Run a command in the Rocq Nix environment",
    )
    run.add_argument("command", help="Command to run")
    run.add_argument("args", nargs="*", help="Command arguments")
    run.set_defaults(subcommand=cmd_run)

    shell = subparsers.add_parser(
        "shell",
        help="Enter a subshell with the Rocq Nix environment",
        description="Enter a subshell with the Rocq Nix environment",
    )
    shell.add_argument(
        "--shell",
        metavar="COMMAND",
        default=os.environ.get("SHELL"),
        help="Shell command (defaults to SHELL environment variable)",
    )
    shell.set_defaults(subcommand=cmd_shell)

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    print(args)
    print(config_json_path)
    args.subcommand(args)
