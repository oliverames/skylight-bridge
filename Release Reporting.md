# Skylight Bridge Release Reporting

## Linear release reporting

[Linear Releases](https://linear.app/ames-consulting/pipeline/skylight-bridge/releases)
records verified customer delivery for this app. Linear does not build, sign,
notarize, upload, or publish the app. Local builds, source-only GitHub releases,
and successful uploads do not complete a Linear release.
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

Include the relevant `AME-123` identifier in the commits that deliver an issue.
The release scanner uses commit references in the scanned history to associate
issues with a release. GitHub-to-project routing does not establish release
membership, and an existing-delivery baseline can legitimately have zero issues.

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

## Keep delivery evidence

Record the built source's full SHA, version/build, artifact hashes, served feed
URLs and channel, verification result, and returned Linear release ID. Preserve
the original release notes and publication date. Before completing a report-only
retry, recheck receiving delivery and then read the Linear version, source SHA,
completed stage, and notes. Repeating the same version must retain one release.
If a tag follows the build, use the build receipt rather than assuming current
HEAD or the tag identifies the archived source.

## Historical baseline

Version 1.7.3 was published on 2026-09-11 and recorded in Linear on
2026-10-07 from source `88295bf08d06c82759e8861415be09a8f720d1e1`. The October 7
completion date records the backfill, not a new app publication. Its existing
artifacts and feed were checked, and a reporting-only retry preserved the same
release, note, and completion time. No historical issue backfill was requested.

The production feed still offered 1.7.3 build 35 when verified on October 7, 2026.
This pipeline covers the macOS app. The iOS companion and paused developer-account
migration are separate work. Recording this baseline does not resume migration.
