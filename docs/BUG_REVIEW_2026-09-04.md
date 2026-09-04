# Bug review and release, September 4, 2026

Author: Oliver Ames

## Task list

- [x] Review current code, release process, and baseline tests.
- [x] Reproduce and fix confirmed defects, with regression coverage.
- [ ] In progress: run the complete test suite and verify the release build.
- [ ] Commit, push, publish the release, and verify the public update feed.

## Baseline

- Repository: `oliverames/skylight-bridge`, branch `main`.
- Starting commit: `a35417ded239afe30c6c31f41ab692cf619001cb`.
- On September 4, 2026, GitHub main matched the clean local checkout and the latest release was 1.6.3.
- Scope: application services, models, persistence, UI and app lifecycle, tests, and release scripts.
- Reviewers inspect code independently and do not edit. The main session verifies findings and owns all changes.
- The first test invocation hit filesystem sandbox restrictions on the compiler cache. The rerun with normal toolchain access passed.

## Confirmed findings

Fifteen findings survived source review and an independent skeptic pass. Fixes are implemented. All 256 tests in 26 suites pass, and release verification is in progress.

| # | Severity | Failure | Fix and regression evidence |
| --- | --- | --- | --- |
| 1 | P1 | Form encoding changed literal plus signs to spaces in credentials and tokens. | Shared form encoder escapes plus signs. Login and refresh request tests use actual form decoding. Both failed before the patch. |
| 2 | P2 | An expired refresh grant bypassed automatic credential login. | Recognize OAuth 401/403 and JSON `400 invalid_grant`, with negative tests for unrelated errors. |
| 3 | P1 | A nil EventKit result became an empty snapshot and could authorize deletion. | All three fetch paths now throw on nil. Tests distinguish missing results from successful empty arrays. A live EventKit fault was not induced. |
| 4 | P2 | Oversized remote recipe text silently disappeared before writing an Apple note. | Propagate parser errors. Tests cover the size limit and preservation of the existing note. |
| 5 | P1 | An old pending photo edit could undo a later pause. | Pause uses the same mapping transaction as other edits. The restart test retains disabled intent. |
| 6 | P2 | Pending photo removals and edits disappeared after restart. | Persist the retry journal atomically with configuration, and persist acknowledgments. Portable snapshots exclude duplicate photo names and selections. |
| 7 | P2 | Removing the last selected photo disabled Save. | Existing mappings permit an empty selection. New mappings still require a selection. |
| 8 | P2 | Sign Out disappeared when the account could not connect. | The Account page exposes Sign Out independently from loaded frames. |
| 9 | P2 | Failed Notes edits or unlinking appeared successful. | Transactional save restores the previous selection. The editor stays open and displays the error. Failure tests verify memory and disk. |
| 10 | P1 | Title-only reminder adoption ignored completion conflicts or chose the wrong side. | Adoption has no agreed baseline until the direction/conflict policy reconciles it. Tests exercise both policies and all directions over repeated runs. |
| 11 | P1 | Importing or adopting completed chores reopened them. | Completion is acknowledged only after Apple applies it. Tests cover creation and adoption over three runs. |
| 12 | P1 | A recurring chore reopened on the next sync or after a content edit. | Persist evidence for the advanced occurrence, preserve dates and completion during content updates, and expire evidence on a new day or rewind. Repeated tests cover edits from both sides. |
| 13 | P2 | A failed meal replacement deletion lost the original meal identity. | Persist pending cleanup alongside the replacement and drain it before unchanged-slot checks. The regression reloads saved state before retry. |
| 14 | P2 | Cleanup retries stalled when the target was already gone. | Use the existing typed absence policy for ordinary photo, recipe, meal, and Apple chore cleanup. Preserve photo ownership until remote cleanup finishes. |
| 15 | P1 | Two chore members could share a list and crash on duplicate reminder IDs. | Assign separate lists, reserve existing ownership before title matching, and reject ambiguous existing mappings with a recoverable error. A same-name setup regression protects ownership. |

## Review coverage and exclusions

The review covered all application services, models, stores, views, entrypoint, tests, and release scripts. Reviewers checked concrete call paths and existing safeguards before accepting findings. Three suspected issues were rejected because the current code already protects Notes attachments, validates upload redirects, and avoids the previously fixed Cloud operation lock cycle.

The review did not change the iOS companion, production CloudKit schema, feature flags, account data, or global automation. Hidden Meals behavior remains hidden. Remote creation after a crash before the first durable checkpoint still needs server idempotency support. Multi-device coordination remains disabled pending schema deployment. Background import cadence is a product follow-up, not a confirmed defect in this round.

## Verification and release

User-requested addition during visual verification: selected-photo rows now show 48-point PhotoKit thumbnails. Requests use display-scale resolution, load as rows appear, and cancel on disappearance. Missing previews retain the selected asset and show an unavailable indicator. Selection and removal behavior is unchanged.

- Baseline: 242 tests in 25 suites passed on September 4, 2026.
- Authentication reproduction: the strengthened tests failed with seven assertions before the fix.
- Intermediate verification: 246 tests in 26 suites passed before the expanded repeated-sync cases.
- Five live-account tests remain explicitly opt-in. Automated verification uses isolated state and injected service responses.
- Final suite: 256 tests in 26 suites passed. The appcast helper tests, shell syntax, plist/XML validation, and whitespace checks passed.
- A separate build with warnings treated as errors passed.
- After the thumbnail addition, all 256 tests in 26 suites passed again. A build with warnings treated as errors also passed.
- The app was built and launched with `script/build_and_run.sh --verify`. Visual checks confirmed version 1.6.4 (29), Account controls, and real thumbnails in the existing photo selection, including after scrolling. No mapping was saved or removed during these checks.
- Universal release build, notarization, and public download/feed verification are pending.
