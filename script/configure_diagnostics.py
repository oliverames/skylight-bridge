#!/usr/bin/env python3
"""Write the Sentry DSN from 1Password into a built app's Info.plist without displaying it.

The Sentry DSN is Sentry's public ingestion key. It is kept out of Git anyway, so
forks, CI and ordinary development builds run with crash reporting off. The op://
reference is resolved, validated and written to the SkylightSentryDSN key of the
given Info.plist. --verify-app compares a built app's Info.plist with the same
reference. No Sentry request is made here.

    script/configure_diagnostics.py --plist "Skylight Bridge.app/Contents/Info.plist"
    script/configure_diagnostics.py --verify-app "Skylight Bridge.app"
"""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import urlsplit

DEFAULT_REFERENCE = "op://Development/Skylight Bridge Sentry DSN/credential"
PLIST_KEY = "SkylightSentryDSN"


def validate_dsn(value):
    """Accept only a public HTTPS sentry.io ingestion DSN, without a secret key or query."""
    try:
        url = urlsplit(value)
        valid = (
            url.scheme == "https"
            and url.hostname is not None
            and url.hostname.endswith(".sentry.io")
            and re.fullmatch(r"[a-z0-9.-]+", url.hostname)
            and re.fullmatch(r"[A-Za-z0-9]{16,128}", url.username or "")
            and url.password is None
            and url.port is None
            and re.fullmatch(r"/[0-9]+", url.path)
            and not url.query and not url.fragment
            and not any(c.isspace() for c in value)
        )
    except ValueError:
        valid = False
    if not valid:
        raise ValueError("not a public HTTPS Sentry DSN")
    return value


def resolve(reference):
    result = subprocess.run(["op", "read", reference], capture_output=True, text=True, check=False)
    if result.returncode:
        # 1Password output can echo values; never show it.
        raise ValueError("1Password could not resolve the reference")
    return validate_dsn(result.stdout.strip())


def write_plist(path, value):
    with path.open("rb") as stream:
        info = plistlib.load(stream)
    info[PLIST_KEY] = value
    with path.open("wb") as stream:
        plistlib.dump(info, stream)


def verify_app(app, value):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get(PLIST_KEY, "") != value:
        raise ValueError("built app value differs")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dsn-reference", default=DEFAULT_REFERENCE,
                        help="op:// reference to the Sentry DSN; never a literal value")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--plist", type=Path, help="Info.plist to write the DSN into")
    target.add_argument("--verify-app", type=Path, help="check a built .app instead of writing")
    args = parser.parse_args()
    if not args.dsn_reference.startswith("op://"):
        parser.error("the reference must be an op:// reference")
    try:
        value = resolve(args.dsn_reference)
        if args.verify_app:
            verify_app(args.verify_app, value)
            print("PASS: the built app's Sentry DSN matches 1Password. No values displayed.")
        else:
            write_plist(args.plist, value)
            print(f"PASS: wrote {PLIST_KEY} to {args.plist.name}. No values displayed.")
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        print(f"FAIL: Sentry DSN: {error}. No values displayed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
