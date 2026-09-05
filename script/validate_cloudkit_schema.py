#!/usr/bin/env python3
"""Validate an exported production schema against the client's active contract."""
import argparse
from pathlib import Path
import re
import sys

REQUIRED = {
    "SharedPreferences": {"payload": ("BYTES", False)},
    "SharedPhotoMapping": {"payload": ("BYTES", False), "___recordID": ("REFERENCE", True)},
    "SharedPhotoSelection": {"payload": ("BYTES", False), "mappingID": ("STRING", True)},
}


def validate(schema: str, flags: str) -> None:
    if not re.match(r"\s*DEFINE\s+SCHEMA\b", schema):
        raise ValueError("Expected a CloudKit schema export beginning with DEFINE SCHEMA")
    matches = list(re.finditer(r"RECORD\s+TYPE\s+(\w+)\s*\((.*?)\)\s*;", schema, re.S))
    records = {match[1]: match[2] for match in matches}
    if len(records) != len(matches):
        raise ValueError("Duplicate record type in schema")
    remaining = re.sub(r"^\s*DEFINE\s+SCHEMA\b", "", schema)
    remaining = re.sub(r"RECORD\s+TYPE\s+\w+\s*\(.*?\)\s*;", "", remaining, flags=re.S)
    if remaining.strip():
        raise ValueError("Unrecognized or incomplete schema declaration")
    feature = re.findall(r"static\s+let\s+multiDeviceCoordinationEnabled\s*=\s*(true|false)\b", flags)
    if feature != ["false"]:
        raise ValueError("Multi-Mac coordination must remain disabled until separately validated")
    for name, fields in REQUIRED.items():
        if name not in records:
            raise ValueError(f"Missing record type: {name}")
        body = records[name]
        for field, (kind, queryable) in fields.items():
            match = re.search(rf'(?:^|,)\s*"?{re.escape(field)}"?\s+{kind}\b([^,]*)', body)
            if not match:
                raise ValueError(f"Missing or incorrect field: {name}.{field} ({kind})")
            if queryable and not re.search(r"\bQUERYABLE\b", match[1]):
                raise ValueError(f"Missing QUERYABLE index: {name}.{field}")
        for permission, role in [("WRITE", "_creator"), ("CREATE", "_icloud"), ("READ", "_world")]:
            if not re.search(rf'GRANT\s+{permission}\s+TO\s+"{role}"', body):
                raise ValueError(f"Missing {permission} grant for {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path, help="Fresh schema export from the production CloudKit Console or cktool")
    parser.add_argument("--flags", type=Path, default=Path(__file__).resolve().parents[1] / "Sources/SkylightBridge/Support/FeatureFlags.swift")
    args = parser.parse_args()
    try:
        validate(args.schema.read_text(), args.flags.read_text())
    except (OSError, ValueError) as error:
        print(f"CloudKit schema validation failed: {error}", file=sys.stderr)
        return 1
    print("CloudKit schema satisfies all active record, field, index, and permission requirements.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
