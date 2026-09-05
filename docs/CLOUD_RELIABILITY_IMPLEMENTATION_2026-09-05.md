# Cloud reliability implementation, September 5, 2026

Author: Oliver Ames

## Task list

- [x] Verify current Mac and iPhone sources, release workflows, and CloudKit capabilities.
- [x] Fix shared preference convergence, durable edit identity, account isolation, and incomplete cloud fetches.
- [x] Integrate automatic recovery, durable publication, and accurate status on Mac and iPhone.
- [x] Complete the transport evaluation and production schema release checks.
- [x] Run fault-injection regressions, full suites, builds, independent review, and rendered UI verification.
- [x] Publish the shared package and client updates, verify Sparkle and release artifacts, and record final evidence.

## Scope and decisions

Oliver authorized all items from the September 5 cloud reliability review, with none deferred. Changes cover this Mac app and the current `skylight-bridge-ios` repository, which owns the shared package. Dependency checkouts remain generated inputs. Source changes and commits are single-threaded. Live production records are not test fixtures.

The existing multi-Mac feature remains disabled, as recommended in the review. The task includes validating that boundary and evaluating transport options, rather than enabling an unsafe second writer.

## Evidence

- Initial Mac tree: clean `main` at `0b6ecb2`.
- Current iPhone remote: private `oliverames/skylight-bridge-ios`, `main` at `df01933a037063fd0d79e5f937a05803c0df1c40`.
- Mac dependency before changes: shared package 0.1.8 at `448ee088fdf06247439246ee6ec33dafccb7b607`.
- Current shared source matches the pinned production code. Remote tag 0.1.8 moved to the later test-only commit, so this work will publish a new immutable tag.
- CKSyncEngine evaluation: the existing private default zone lacks change-fetching support. Retain compatible default-zone records and add scheduled reconciliation, account checks, and server-aware retry delays. A custom-zone migration is unnecessary for these fixes.
- Oliver authorized Apple Developer access. CloudKit Console exported the live production schema at 2026-09-05 16:20:20 UTC. The verified export is `cloudkit-production-2026-09-05.ckdb`, SHA256 `c66d7067c3bcab0a987e67a241a7ec615c1216942a04041e3b9e08399de1462b`. All active record types, payload fields, and query indexes exist. No production schema mutation was necessary.
- App Store Connect returned no visible iPhone app for the configured bundle identifier. Shared package and source publication can proceed; TestFlight distribution requires an app record.

## Implementation and verification

- Both clients persist outgoing changes before network requests and retain the original edit timestamps through restarts. Preference merges converge regardless of merge order, including legacy documents without per-field writer metadata.
- Cloud transports bind saved state to a verified iCloud account. They reject another account before publication and recheck identity after responses. A returning original account resumes its retained changes.
- One worker per client coalesces requests and retries after connectivity, wake, foreground, or a scheduled delay. Server cooldowns persist across restarts and cannot be shortened by unrelated failures.
- Incomplete fetches retain healthy records and cached selections. Explicit edits continue independently where safe. Absence from an incomplete response does not remove a photo or recreate a removed photo.
- An acknowledged save can legitimately lose to a newer remote edit. Both clients drain that older operation while preserving newer foreground work. Retirement acknowledgements also compare operation timestamps.
- The Mac suite passed 263 tests in 27 suites before the final independent-review regressions. Shared and mobile suites passed 20 and 4 tests respectively before the final retry regressions.
- `script/validate_cloudkit_schema.py` checks all active record types, field types, query indexes, permissions, and the disabled multi-Mac boundary. Seven negative/compatibility tests pass. Release packaging now requires an explicitly supplied fresh production export.

## Transport decision

Keep the existing default-zone CloudKit records and use scheduled reconciliation with durable retries. Apple's database subscription documentation excludes changes in the default zone, and the SDK documents that this zone lacks change-fetch support. A CKSyncEngine migration would require a new custom zone and record migration, which does not improve these fixes enough to justify changing the shared storage contract. This evaluation is complete. Multi-Mac coordination stays disabled and the release gate enforces that decision.

Sources: [CKDatabaseSubscription](https://developer.apple.com/documentation/CloudKit/CKDatabaseSubscription), [CKSyncEngine](https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5), [CloudKit schema workflow](https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow).

- Final independent review found no remaining actionable defects in the corrected retry, retirement, and schema paths. The final suites passed 264 Mac tests, 22 shared tests, and four mobile integration tests. Both optimized builds passed with warnings treated as errors.
- The signed Mac development bundle completed a real production iCloud refresh and rendered “Up to date with iCloud” on September 5, 2026 at approximately 17:03 UTC. No synthetic cloud records were created. The new Overview screen was captured in `cloud-reliability-overview.png` in the session visualization folder.
- Shared package 0.1.9 was published at immutable commit `6dd0727`. The Mac dependency now resolves the published release rather than an editable checkout.
- App Store Connect app `6809008416` was created with the configured bundle ID and limited access. Automatic approval review rejected Full Access, so the safer limited-access setting was used. The signed iPhone archive succeeded. TestFlight export and upload verification are recorded below.

## Release evidence, verified September 5, 2026

- Mac 1.7.0 (build 32) is published at the GitHub release `v1.7.0`, created 2026-09-05 17:10:14 UTC. The downloaded disk image matches the published checksum `e5710b73c2decaff2e7b4f5a3ba297c58ac92114a54d665442f3ff4363135a88`, is 7,056,611 bytes as advertised in the appcast enclosure, and `spctl` reports it accepted as Notarized Developer ID.
- The live Sparkle feed on `gh-pages` (commit `2dd3fc8`) serves 1.7.0, build 32. The `main` copy of `appcast.xml` was left uncommitted by the release run and is committed alongside this record, matching the 1.6.4 through 1.6.6 convention.
- Mac CI passed on the release commit `503b19b`.
- The iPhone repository's CI failed on `6dd0727` and `5ad8304` because the macOS 26 runner's SDK lacks `PHCloudIdentifier.archivalStringValue`. Commit `00d95ed` guards the spelling by compiler version, and CI passed on it at 2026-09-05 17:12 UTC. The exported iPhone archive was produced after that source change and includes it.
- App Store Connect holds iPhone build 0.1.9 (1) for app `6809008416`, uploaded 2026-09-05 17:17 UTC, processing state `VALID`, encryption exemption declared, internal build state `READY_FOR_BETA_TESTING`. The release run left no TestFlight group, so an internal group named "Internal Testers" with access to all builds was created at 2026-09-05 19:48 UTC, and Oliver was added as its internal tester. No external group or beta review submission exists.
- The shared package pin in `Package.resolved` resolves 0.1.9 at `6dd0727`, which matches the remote tag.
