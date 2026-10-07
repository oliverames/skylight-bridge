# Skylight Bridge Release Reporting

## Linear release reporting

The scheduled Linear pipeline records verified customer delivery. Local builds,
source-only GitHub releases, and successful uploads do not complete a release.
The reporting command can be rerun independently after a network or Linear failure.
It repeats receiving checks and targets the same explicit version.

The helper downloads the official `linear/linear-release` CLI at `v0.18.0` and
checks the pinned SHA-256 before every execution. It reads the pipeline credential
from `op://Development/Linear Release - skylight-bridge/credential` at runtime. An existing
`LINEAR_ACCESS_KEY` environment variable overrides that lookup. Credentials never
appear in command arguments or output. The cache contains only the public executable.

`--dry-run` verifies delivery without reading the Linear credential or writing a
release. Add `--check-access` to also run the official CLI's read-only API check.
A normal run syncs issues, attaches the published GitHub release notes when available,
and completes the scheduled release only after delivery passes. `--notes-file`
can supply reviewed notes explicitly.

Attribution uses the release tag's exact source commit in a temporary metadata-only
clone. It does not switch the working checkout. Full local Git history is required, and
branch-reference inference is disabled to avoid unrelated local branch names. The first sync uses Linear's normal
baseline, which may inspect only the current commit. Use `--base-ref <previous-tag>`
for a deliberate initial history range. No historical backfill is implied.

`script/publish_appcast.sh` now verifies the actual GitHub DMG bytes and public
consumer feed before reporting. Its existing stable-only version rules remain.
A feed propagation or Linear failure must be retried with the reporting command,
not by repeating the publisher's newer-build gate.

```sh
python3 script/report_linear_release.py --version 1.7.3 \
  --artifacts /path/to/prepared/artifacts --dry-run --check-access
```

If the local DMG has a different filename, pass `--dmg /path/to/local.dmg` and
`--asset-name Skylight.Bridge-1.7.3.dmg`. Remove the dry-run options to report an
already delivered release. This path never launches the app or accesses Photos.

Official CLI reference: https://github.com/linear/linear-release/tree/v0.18.0
