# Bug review and release, September 4, 2026

Author: Oliver Ames

## Task list

- [x] Review current code, release process, and baseline tests.
- [x] Reproduce and fix confirmed defects, with regression coverage.
- [x] Run the complete test suite and verify the release build.
- [x] Publish the release and verify the public download and update feed.

## Baseline

- Repository: `oliverames/skylight-bridge`, branch `main`.
- Starting commit: `a35417ded239afe30c6c31f41ab692cf619001cb`.
- On September 4, 2026, GitHub main matched the clean local checkout and the latest release was 1.6.3.
- Scope: application services, models, persistence, UI and app lifecycle, tests, and release scripts.
- Reviewers inspect code independently and do not edit. The main session verifies findings and owns all changes.
- The first test invocation hit filesystem sandbox restrictions on the compiler cache. The rerun with normal toolchain access passed.

## Confirmed findings

Sixteen findings survived source review and independent review, including the startup defect exposed by the notarized release. All fixes are released in version 1.6.5 (build 30). All 256 tests in 26 suites pass. The public installer and signed update feed are verified.

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
| 16 | P1 | The release app could start a different store from the one its window used, leaving the window disconnected. | Replace uninstalled SwiftUI State access with one explicit process-lifetime store shared by startup and all scenes. The pre-fix release reproduced the fault in the unified log. After the fix, the optimized compiler check and full suite pass, two fresh release launches reconnect automatically, and the new process emits no uninstalled-State warning. |

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
- Visual checks also confirmed the Recipes screen and selection editor. The editors were canceled without saving.
- Universal release build completed from clean, pushed commit `5e3a04da927d10985e8c6e8e6e2a2b9cf174d300`. The executable contains both arm64 and x86_64. [GitHub CI for that commit passed](https://github.com/oliverames/skylight-bridge/actions/runs/33918202820).
- Apple accepted notarization for the app (`6206be52-82df-4a15-acd1-c1233a83c323`) and DMG (`89f2c1df-db44-47f6-a11d-be72c913fe71`). Both were stapled and validated. The app, DMG, and app mounted from the DMG passed Gatekeeper as Notarized Developer ID, signed by Oliver Ames, team `PV3W52NDZ3`.
- DMG SHA-256: `32081e9a5c846074026532f3894ae4f4904b8903909a7b8024bddd9a6eb2c194`.
- [Version 1.6.4 was published](https://github.com/oliverames/skylight-bridge/releases/tag/v1.6.4). The downloaded DMG is 6,859,492 bytes and matches the local and published SHA-256. The live appcast matches the local copy. Both its signature and the downloaded DMG's enclosure signature verify successfully, with version 1.6.4 and build 29.
- Final launch of the notarized build exposed a preexisting startup defect. The window retained an unstarted store, while startup used the value of an uninstalled SwiftUI State. The release stayed disconnected, and the unified log recorded SwiftUI's warning that this creates a new instance each time. The pattern predates this review. Version 1.6.5 fixes this defect and supersedes 1.6.4.


## Final release: 1.6.5 (build 30)

- Release commit: `3e56c5a2ab305858a67e06ed36d43d0b2c6f7e58`, built from a clean pushed tree.
- All 256 tests in 26 suites passed after the startup correction. An optimized build with warnings treated as errors passed.
- Two fresh launches of the notarized app restored the saved account automatically. The unified log for the second process contained no uninstalled-State warning. The photo editor in 1.6.5 displayed actual thumbnails.
- The universal app and DMG passed notarization, stapling, and Gatekeeper. Apple submission IDs: app `7c4d7ef4-00b0-44a9-994e-358e56b7f2e0`, DMG `dcde4eb2-6ae2-4ef2-9d1e-06e4b7a6145c`.
- [Published version 1.6.5](https://github.com/oliverames/skylight-bridge/releases/tag/v1.6.5) is GitHub's latest release. The downloaded DMG is 6,857,444 bytes. Its SHA-256 matches both the local artifact and published checksum: `56c0c72069131ac59fb961bc2a37622bcca2dff79987a00119e57cd8149d8ea2`.
- The live appcast matches the repository copy and advertises 1.6.5 build 30. Its signature and the downloaded DMG's enclosure signature verify successfully. The feed commit is `d17adf4` on `gh-pages`.
- Existing Keychain signing credentials were used. No private key file was exported.
- GitHub CI for the final release commit remains [queued](https://github.com/oliverames/skylight-bridge/actions/runs/33919155480) as observed on September 4, 2026. Local tests and release verification completed successfully.

## Follow-up requiring a mapping choice

The live Activity screen reports an Apple Reminders list that no longer exists, with matching errors from the previous week. The existing mapping needs a replacement list or removal. This is separate from the app fixes, and no mapping was changed during verification.
