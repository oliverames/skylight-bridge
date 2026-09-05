import unittest
from pathlib import Path
from validate_cloudkit_schema import validate

SCHEMA = (Path(__file__).resolve().parents[1] / "docs/cloudkit-production-2026-09-05.ckdb").read_text()
FLAGS = "static let multiDeviceCoordinationEnabled = false"


class SchemaTests(unittest.TestCase):
    def test_live_export(self):
        validate(SCHEMA, FLAGS)

    def test_missing_index(self):
        with self.assertRaisesRegex(ValueError, "QUERYABLE"):
            validate(SCHEMA.replace("mappingID       STRING QUERYABLE", "mappingID       STRING"), FLAGS)

    def test_incorrect_field(self):
        with self.assertRaisesRegex(ValueError, "incorrect field"):
            validate(SCHEMA.replace("payload         BYTES", "payload         STRING"), FLAGS)

    def test_truncated_schema(self):
        with self.assertRaises(ValueError):
            validate(SCHEMA[:-10], FLAGS)

    def test_coordination_enabled(self):
        with self.assertRaisesRegex(ValueError, "disabled"):
            validate(SCHEMA, FLAGS.replace("false", "true"))

    def test_extra_fields_are_compatible(self):
        validate(SCHEMA.replace("payload         BYTES,", "payload         BYTES, futureField STRING,"), FLAGS)

    def test_missing_grant(self):
        with self.assertRaisesRegex(ValueError, "grant"):
            validate(SCHEMA.replace('GRANT WRITE TO "_creator",', ''), FLAGS)


if __name__ == "__main__":
    unittest.main()
