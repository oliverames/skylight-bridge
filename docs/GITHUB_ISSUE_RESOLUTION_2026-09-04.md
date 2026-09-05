# GitHub issue resolution, September 4, 2026

Author: Oliver Ames

## Task list

- [x] Investigate issue 4 through fresh authentication and improve confirmed diagnostic defects. The missing-code failure remains unconfirmed locally.
- [x] Investigate the HTTP 422 in issue 2 and preserve the request method in errors. The reporter's underlying rejection remains unconfirmed.
- [x] Document subscription requirements for issue 3 and verify the shipped CloudKit mitigation for issue 1.
- [x] Complete release verification, publish 1.6.6, and finish replies to all four issues. Remaining reporter confirmations are tracked in their open issues.

## Scope and evidence

The user authorized proceeding with all four reviewed GitHub issues. Work starts from main commit 1315545876c18e5bdfd2f138ac2b00fb77841343, following release 1.6.5. Existing production data and the CloudKit schema are not changed to reproduce failures. GitHub comments will distinguish confirmed fixes from requests for reporter confirmation. Findings and verification are recorded below as work progresses.

## Findings and actions, September 5, 2026

| Issue | Verified finding | Action and remaining evidence |
| --- | --- | --- |
| [1: SharedSyncState production schema](https://github.com/oliverames/skylight-bridge/issues/1) | Release 1.5.13 disabled multi-device heartbeat and shared sync-state calls. Local two-way sync does not depend on those record types. One commenter confirmed disabling Preview mode restored syncing. | Posted the shipped mitigation and Preview mode guidance. Keep open for confirmation from the other reporters. No schema deployment is claimed or performed. |
| [2: Chore sync failure](https://github.com/oliverames/skylight-bridge/issues/2) | The screenshot shows HTTP 422, despite the title saying 522. Reads and creates share the `/chores` path, and errors omitted the request method. | Preserve GET/POST and existing validation details. Regression coverage distinguishes both methods without including request values. A live inventory read timed out, so no live read or create fix is claimed. Request the updated Activity error after 1.6.6. |
| [3: Subscription required](https://github.com/oliverames/skylight-bridge/issues/3) | Skylight documents basic lists and chores without Plus, and photos and recipes as Plus features. | README now links the official requirements and distinguishes feature entitlement from unverified private API coverage on non-Plus accounts. Commit `aedbe79` closed the issue, and the answer was posted on September 5. |
| [4: First login failure](https://github.com/oliverames/skylight-bridge/issues/4) | Several distinct authorization response failures shared one generic message. On September 5, commenter nickhx confirmed the latest release works again. | Preserve HTTP status and a fixed failure reason without exposing response bodies or callbacks. Both fresh OAuth tests reached `loginRejected` with the saved credentials, so they do not reproduce or clear the missing-code report. Keep open for the original reporter and remaining commenter. |

The authorization tests cover HTTP 200, 403, and 503, a redirect without a destination, and an untrusted callback. They verify that no token exchange occurs after any rejected response. Existing strict HTTPS callback validation and login-rejection behavior remain unchanged. Read-only secondary reviews found no blockers in either diagnostic change.

## Verification before release

The full suite passes: 258 tests in 26 suites, including five authorization-response cases and two request-method cases. The initial run stopped because an existing frame-hydration fixture used the real sync-state store. A one-second process sample showed `SyncStateStore.load` waiting in `SecItemCopyMatching`. The fixture now injects temporary storage and a test integrity key, and the complete suite finished in 3.315 seconds. Test scaffolding changed without changing production state or Keychain policy.

The fresh-login check used credentials privately from Keychain and retained no secrets or raw response output. Its result was a credential rejection, not the reported missing authorization code. The optional chore inventory read timed out and is not counted as successful verification.

Version 1.6.6 (build 31) delivers diagnostic improvements. It does not claim that the remaining reporters' failures are resolved.

## Published release and follow-up

[Release 1.6.6](https://github.com/oliverames/skylight-bridge/releases/tag/v1.6.6) was built from clean, pushed commit `cfe639255fc92ee323817fd38a3dbefdd950e44f`. The optimized compiler check passed with warnings treated as errors, and [GitHub CI passed for the release commit](https://github.com/oliverames/skylight-bridge/actions/runs/33966548987).

Apple accepted notarization for the app archive (`d6074eed-3f23-470c-9268-acfa9309c238`) and DMG (`a6643e3f-fc23-4318-bbc5-49ba78ba8d4b`). The universal app and DMG passed signing, stapling, and Gatekeeper verification. The public DMG and checksum match the local files byte for byte. The DMG is 6,856,419 bytes and its SHA-256 is `25ae02c2ede6d1ef93b7377897e69974a94587954860bfda25b2a3b45e7f6f45`.

The signed Sparkle feed was pushed to gh-pages commit `9bf73ba`. A fresh download of the public feed matches the repository copy, advertises 1.6.6 build 31, and passes Sparkle's complete-feed signature verification. The downloaded public DMG also passes enclosure signature verification. The bundled updater configuration requires both checks. Existing Keychain signing profiles were used, and no private signing key was exported.

The notarized app launched as 1.6.6 (31), restored its saved account, and displayed actual thumbnails in the selected-photo editor. The editor was closed without changing its mapping. Saved-session restoration does not replace the unsuccessful fresh-login check described above. A separate attempt to read the access token for a read-only chore probe also timed out at Keychain access.

All four issues received evidence-based replies: [CloudKit mitigation](https://github.com/oliverames/skylight-bridge/issues/1#issuecomment-5551823680), [chore diagnostics](https://github.com/oliverames/skylight-bridge/issues/2#issuecomment-5551905201), [subscription answer](https://github.com/oliverames/skylight-bridge/issues/3#issuecomment-5551810023), and [login follow-up](https://github.com/oliverames/skylight-bridge/issues/4#issuecomment-5551905252). Issue 3 is closed. Issues 1, 2, and 4 remain open for the requested reporter evidence. No production CloudKit schema or user mappings were changed to investigate these reports.
