## 2026-10-07 - GitHub Issue Review Closeout

**What changed**: Reviewed the one open issue against source at `caf8fc875f6d` and their complete issue history. No issue qualified for closure.

**Decisions made**: Close completed implementations even when device acceptance remains, and close testing-only tasks under Oliver's explicit instruction. Keep unresolved defects, missing implementation, release work, and owner decisions open.

**Left off at**: Resolved this session: issue assignment and state reconciliation. GitHub was independently re-read on October 7, 2026 at 10:20 AM EDT. All 8 repository issues include Oliver as an assignee, with 1 open. Source paths and cited lines were checked. No runtime tests, deployment, or application changes were performed. This is one part of the account-wide review.

**Open questions**: Still open: [#9](https://github.com/oliverames/skylight-bridge/issues/9). Other previously recorded operational follow-ups retain their dated status. No new issue was needed for this review.

---

## 2026-10-07 - README Refresh Closeout

**What changed**: Corrects Swift requirements, current release links, and companion-app status.

**Decisions made**: Keep setup and status claims tied to current source or explicitly dated evidence. This entry records the multi-repository README maintenance session.

**Left off at**: Resolved this session: README review and publication at `caf8fc8`. Relative links, examples and applicable counts were checked. Verification covered documentation. No fresh runtime acceptance is claimed.

**Open questions**: No new question from the README refresh. Prior account-transfer and runtime acceptance gates remain outside this pass. No Photos library, app data or live sign-in was accessed.

---

## Open items

- Export a fresh CloudKit production schema (needs a CloudKit Console sign-in) before the next schema-affecting release; the gate still uses `docs/cloudkit-production-2026-09-05.ckdb` (since 2026-09-11)
- Relink the "Personal" mapping to Reminders list `0ED8B4BF-E526-4CE6-8A76-5011587DF6C1` and remove the "Money" and "To Sell" mappings through the app UI, because the configuration is sealed (since 2026-09-04; unverified)
- Live OAuth tests and the live chore-read and fresh-login probes cannot run: no Skylight account credential exists in 1Password for `SKYLIGHT_EMAIL` and `SKYLIGHT_PASSWORD`, and the Keychain key prompts, so the probes cannot run headless (since 2026-09-05)
- Explicit new photo-album and reminder-list creation lacks remote idempotency after a checkpoint failure or a crash before the first durable checkpoint; needs server idempotency support (since 2026-08-27)
- The intermittent full-suite hang was never reproduced on demand; an unexplained hang on 1.6.3 or later would mean a second cause (since 2026-08-27; watch item)
- Live-probe whether freshly uploaded messages are readable via `GET /messages/{id}`; the upload-readiness poll switched to that call in `3d1d2d5` (since 2026-08-25; unverified)
- Decide what to do with `AppleNoteAttachmentSnapshot`, which is never constructed, so the Notes attachments surface is inert (since 2026-08-25)
- Visually verify the Sign Out, Remove Link, and permission-denial UI, plus the Save Fix Script (BlockedPromptFix) panel, which renders only on home-server (since 2026-08-17; unverified)
- Decide whether the hidden Meals workflow gets finished or removed; `FeatureFlags.mealSyncEnabled` is still false (since 2026-08-17)
- Decide whether to revoke the Apple Development certificate created on 2026-08-13 (identity SHA-1 `6FFCB2B37E85086E8150CE4C7AD0F6CA0023A99A`) (since 2026-08-13; unverified)
- Verify Notes sync succeeds on home-server after it updates to 1.5.12 or later (since 2026-08-13; unverified)
- Screen Sharing to home-server was blocked after the TCC reset and needed local System Settings or MDM approval (since 2026-07-30; unverified)
- Run the physical iPhone CloudKit add, offline-edit, and removal round trip with the companion app (since 2026-07-15; unverified)
- Decide whether to split the 23 quick-meal notes out of the 🥘 Food recipe mapping (Selected notes or a second folder) (since 2026-07-14; unverified)
- Shared Albums appear disabled in Photos on this Mac, so the picker shows none until they are enabled (since 2026-07-14; unverified)

## 2026-09-11 - Skylight sign-in restored and 1.7.3 released

Skylight's authorization endpoint now requires PKCE. The app requested an authorization code without a code challenge, so Skylight returned HTTP 400 instead of the redirect carrying the code. This is the failure reported in [#4](https://github.com/oliverames/skylight-bridge/issues/4) since early September. Steve Nolte diagnosed it and contributed [PR #7](https://github.com/oliverames/skylight-bridge/pull/7), which generates a verifier and S256 challenge per sign-in, sends the challenge on the authorize request, and sends the verifier at token exchange. It also replaces a Keychain credential item when an update returns `errSecInvalidOwnerEdit`, which affected first sign-in.

The contributed commit `31f0519` was applied unchanged. Follow-up commit `19a7583` corrects two defects in it: the PKCE random-generation failure threw `LocalFileIntegrityError.randomGenerationFailed`, which would have shown an unrelated file-integrity message during sign-in, so it now throws a dedicated `SkylightOAuthError.pkceGenerationFailed` with a sign-in message; and the Keychain branch compared against the raw value `-25244` rather than `errSecInvalidOwnerEdit`.

Independent corroboration of the cause: Skylight's current first-party web bundle `index-f9dfe465ae73809e4186af133113b8bb.js` builds its `skylight-mobile` authorization request with expo-auth-session, whose `usePKCE` defaults to true (`usePKCE=e.usePKCE??!0`), and Skylight never disables it. The app was the only client not sending PKCE. Unauthenticated probes of `/oauth/authorize` on September 11 returned HTTP 302 to sign-in both with and without a code challenge, so they do not distinguish the two; they do not exercise the authenticated step that fails. The reporter confirmed a successful live sign-in with this change on their own affected account. No live sign-in was run here, because no Skylight account credential exists in 1Password and the live OAuth tests need `SKYLIGHT_EMAIL` and `SKYLIGHT_PASSWORD`.

Released [1.7.3, build 35](https://github.com/oliverames/skylight-bridge/releases/tag/v1.7.3) from clean, pushed commit `88295bf08d06c82759e8861415be09a8f720d1e1`. All 272 tests in 27 suites pass, including the PKCE authorize and token-parameter assertions added by the PR. The optimized build passes with warnings treated as errors, and GitHub CI passed on the release commit. The universal app and disk image were notarized and stapled, and Gatekeeper reports Notarized Developer ID for both.

The CloudKit release gate ran against the existing `docs/cloudkit-production-2026-09-05.ckdb` export, which passes. That export is from September 5, not fresh. This release changes no CloudKit record types, fields, indexes, or permissions, so the gate's subject is unchanged; a fresh export still needs a CloudKit Console sign-in before the next schema-affecting release.

Distribution verified: the public download is 7,089,380 bytes and matches SHA-256 `0dd11037537a39ea5406d30e802098b94561f2d9a9b2265ca25728c54da2b5cb`. The live feed on gh-pages `ffc04d2` matches the repository copy byte for byte, advertises 1.7.3 build 35, and names that same length. The downloaded archive's EdDSA signature verifies, and the signing account's public key `dHpRax28kl47J+NOJLYyLwZ/Xtqg64gC1Zl/PRPzB3U=` matches the shipped app's `SUPublicEDKey`. The mounted app reports 1.7.3 build 35, carries both `x86_64` and `arm64`, and points at the production feed. No private key material was exported.

Issue [#2](https://github.com/oliverames/skylight-bridge/issues/2) is closed: its reporter confirmed the 1.7.2 chore corrections fixed the Up for Grabs HTTP 422. Issue #4 is closed by this release, with reporters asked to confirm. The installed app was not replaced.

---

## 2026-09-09 - Skylight Bridge 1.7.2 released

Published [1.7.2, build 34](https://github.com/oliverames/skylight-bridge/releases/tag/v1.7.2) from `a383e5e513c29395af263377408d527d9d61e0f7`. The release includes the chore contract corrections and inactive-heartbeat removal described below. Both Intel and Apple silicon binaries retain a macOS 26 minimum.

All 272 tests, schema and appcast helper checks, and release-commit CI pass. A fresh production schema export from CloudKit Console passed the release gate. Apple notarized and stapled the app and disk image. Gatekeeper accepts the disk image and its mounted app. The public download matches SHA-256 `cf0ff59a62c27948dc05546eee75966dede4fa07263c4d0ac799b6de84bcdb35`.

The signed feed is published on gh-pages at `978bdf6`. The fetched public feed matches the repository copy, advertises version 1.7.2/build 34, and identifies the 7,086,308-byte download. Both its embedded signature and the downloaded archive signature verify using the existing key, whose public key matches the app. Existing notarization credentials were used without exporting private key material. No new tokens were created or retrieved for storage in 1Password.

Remaining: #2 awaits reporter confirmation on this release. #4's login failure remains under investigation. The installed app was not replaced during publication.

---

## 2026-09-09 - GitHub issue review and chore API compatibility

Reviewed all open issues and comments. Closed #1 after the remaining reporters confirmed success. Corrected unassigned chore creation and inventory requests for #2 using Skylight's current web-client contract. Updated the unused multi-profile creation and search helpers tracked in #6. Removed the inactive Mac heartbeat and warning UI for #5 while retaining the disabled shared-sync-state boundary.

Verification: 272 tests in 27 suites, seven schema checks, appcast helper checks, and the optimized build with warnings treated as errors pass. These changes were subsequently published in 1.7.2 as recorded above.

Remaining work: #2 needs reporter confirmation. #4 remains open with matching HTTP 400 screenshots and needs a sanitized authenticated trace from an affected account. Test credentials are not configured. The existing Personal-list relink and Money/To Sell mapping cleanup from the prior entry remain outside this issue-review scope.

See [the dated review](docs/GITHUB_ISSUE_REVIEW_2026-09-09.md) for evidence and issue status.

---

## 2026-09-05 - Codex session review, 1.7.0 closeout, and 1.7.1 released

**What changed**: Reviewed Codex session `01a06e0e` against its rollout and live state. Its four releases (1.6.4 through 1.7.0), issue replies, and the iOS CI fix were confirmed real. Three leftovers were closed: the 1.7.0 `appcast.xml` that the release run left uncommitted on `main`, the implementation record that still read "in progress", and a TestFlight group so the uploaded iPhone build is installable. The activity log then showed every scheduled sync since 2026-08-17 aborting on `Apple Reminders list 97E590DC… was not found` (the recreated "Personal" list behind "Dad's To-dos"). Commit `18f0ee3` turns a missing Reminders list or Photos collection into a per-mapping warning that names the mapping, and the run continues. Released 1.7.1 build 33 (`a2a8b15`): notarized, Gatekeeper-accepted, GitHub release `v1.7.1` with checksum `7ebb1bf3…a260`, signed appcast on `gh-pages` `facb18b`. Posted the issue #4 follow-up asking the reporter to re-attach the screenshot GitHub dropped from their email reply.

**Decisions made**: Oliver keeps the iPhone companion as a private TestFlight build (internal group only, no external group or review). Missing source containers are per-mapping warnings, not run failures. The `Money` and `To Sell` mappings are to be removed and `Personal` relinked, both through the app UI because the configuration is sealed.

**Left off at**: All commits pushed, CI green on `02c1ed8`. Resolved this session: uncommitted 1.7.0 appcast, TestFlight group, README badge stuck at 1.6.6. Still open from the prior entry: distribution verification is now recorded in the implementation doc.

**Open questions**: NEW: relink "Personal" to list `0ED8B4BF-E526-4CE6-8A76-5011587DF6C1` and remove "Money" and "To Sell" in Settings; desktop control could not be granted in this scheduled run. Still open: issues #1, #2, #4 await reporter evidence. Still open: the live chore-read and fresh-login probes need the Keychain key, which prompts and cannot run headless.

**Verification**: 266 tests in 27 suites via `script/run_tests.sh`; `swift build -c release -Xswiftc -warnings-as-errors` clean; `spctl` reports Notarized Developer ID for the 1.7.1 DMG; downloaded `.sha256` diffs clean; the live appcast serves build 33 with enclosure length 7,080,676 matching the DMG and diffs clean against the repo copy.

---

## 2026-09-05 - Cloud reliability and 1.7.0 preparation

Completed all implementation items from the cloud reliability review across Mac and iPhone. Outgoing edits now persist before publication with their original timestamps. Both clients recover automatically, honor server retry delays across restarts, retain healthy partial results, and protect newer foreground edits. Account ownership prevents a different iCloud account from receiving the previous account's cached edits. The Overview screen reports last successful sharing, pending changes, and retry timing.

The shared package is published as immutable version 0.1.9 at `6dd0727`. All 264 Mac tests, 22 shared tests, and four mobile integration tests pass. Both optimized builds pass with warnings treated as errors. Independent review found no remaining defects in the final corrected paths. The iPhone simulator build launched and its Overview was visually checked. The signed Mac build completed a production iCloud refresh and displayed the successful status.

The live production schema export contains all active types and indexes. A release gate checks that export and enforces the disabled multi-Mac boundary. Seven schema tests and the Sparkle helper tests pass. The transport evaluation is complete: retain default-zone compatibility and scheduled reconciliation. See [implementation evidence](docs/CLOUD_RELIABILITY_IMPLEMENTATION_2026-09-05.md).

Version 1.7.0 build 32 is prepared for signed Mac release. The iPhone 0.1.9 build 1 archive succeeded, and its first App Store Connect record is `6809008416`. Distribution verification will be recorded after publication.

---

## 2026-09-05 - GitHub issue review and 1.6.6 released

Reviewed all four GitHub issues and replied with verified findings. The subscription documentation now explains which features require Calendar Plus, and issue 3 is closed. Issues 1, 2, and 4 remain open for reporter confirmation or updated error details. The CloudKit mitigation already shipped in 1.5.13, and one login reporter confirmed the latest release works on September 5.

Version 1.6.6 (build 31) identifies the method on failed API requests and preserves the HTTP status and a fixed reason when OAuth authorization fails. It excludes response bodies and callback contents from those new login diagnostics. The request-method change was preserved by sync commit `875a431`, and the login diagnostics are in `2b074a5`. A preexisting test fixture opened live sync state and waited for Keychain access. Commit `eb85d18` gives it temporary state and a test key.

All 258 tests in 26 suites pass, the optimized build passes with warnings treated as errors, and GitHub CI passed for release commit `cfe639255fc92ee323817fd38a3dbefdd950e44f`. Apple notarized the universal app and DMG, and both passed stapling and Gatekeeper checks. The public DMG matches the local artifact at 6,856,419 bytes and SHA-256 `25ae02c2ede6d1ef93b7377897e69974a94587954860bfda25b2a3b45e7f6f45`. The live signed Sparkle feed advertises 1.6.6 build 31 at gh-pages commit `9bf73ba`, and both feed and downloaded archive signatures verify.

The notarized app restored its saved account and rendered photo previews correctly. Fresh login with the saved credentials instead returned `loginRejected`, and live chore reads could not complete because of Keychain access. These checks do not establish that the remaining reported failures are fixed. No user mappings or CloudKit schema were changed. See the [issue resolution report](docs/GITHUB_ISSUE_RESOLUTION_2026-09-04.md) for evidence and follow-up links.

---

## 2026-09-04 - Startup correction and 1.6.5 released

Version 1.6.5 (build 30) supersedes 1.6.4 and completes the review with sixteen fixes plus selected-photo previews. Startup and all scenes now use one process-lifetime AppStore. This removes the uninstalled SwiftUI State access that left the optimized app disconnected.

All 256 tests in 26 suites pass after the fix, and the optimized compiler check passes with warnings treated as errors. Two fresh launches of the notarized release restored the saved account automatically. The second process emitted no uninstalled-State fault, and the final photo editor showed actual thumbnails.

The release was built from clean, pushed commit `3e56c5a2ab305858a67e06ed36d43d0b2c6f7e58`. Its universal app and DMG passed notarization, stapling, and Gatekeeper. The downloaded DMG is 6,857,444 bytes with SHA-256 `56c0c72069131ac59fb961bc2a37622bcca2dff79987a00119e57cd8149d8ea2`, matching the local artifact and published checksum. The live signed appcast advertises 1.6.5 build 30, and both the feed and downloaded archive signatures verify. GitHub reports 1.6.5 as the latest release. No private key file was exported.

GitHub CI for the final release commit remains queued as observed on September 4, 2026. Local verification completed. The existing missing Reminders list remains a mapping follow-up. See the [full review](docs/BUG_REVIEW_2026-09-04.md).

---

## 2026-09-04 - Bug review, photo previews, and 1.6.4 release

Implemented fifteen confirmed fixes across authentication, persistence, reminder and chore reconciliation, Notes saves, and retry cleanup. Added selected-photo thumbnails at Oliver's request. The [dated review](docs/BUG_REVIEW_2026-09-04.md) records each finding and its evidence.

All 256 tests in 26 suites pass, the compiler passes with warnings treated as errors, and the affected editors were visually inspected. Version 1.6.4 (build 29) was built from clean, pushed commit `5e3a04da927d10985e8c6e8e6e2a2b9cf174d300`. Its universal app and DMG passed notarization, stapling, and Gatekeeper verification. The published DMG SHA-256 is `32081e9a5c846074026532f3894ae4f4904b8903909a7b8024bddd9a6eb2c194`. The public download, signed appcast, and enclosure signature were verified. Credentials came from the existing Keychain profile, so no private key file was written.

The final release launch exposed a preexisting SwiftUI startup defect: startup reads an uninstalled State value, which can differ from the store used by the window. The next entry records the corrective 1.6.5 release. Existing activity also reports an unavailable Apple Reminders list, including entries from the previous week. That mapping needs relinking and was not changed during UI verification.

---

## 2026-08-27 - Shared Cloud gate deadlock fixed; 1.6.2 and 1.6.3 released

**What changed**: Released 1.6.2 (build 27), which shipped the reconciliation
work the previous entry left unreleased, then found and fixed a deadlock and
released 1.6.3 (build 28).

`publishSharediCloudState` and `refreshSharediCloudState` took the shared Cloud
operation gate and then awaited `waitForSharedPreferencesApplyWindow`, which
spins on `isConnecting || isSyncing`. `runTeardown` takes the same two pieces of
state in the opposite order: it sets `isSyncing` first, then calls
`retireSharedPhotoMapping`, which wants the gate. Either order alone is fine;
together they form a cycle that cannot resolve. Holding the gate through that
wait was independently harmful, because every unrelated Cloud operation blocks
on the gate, including a mapping retirement that never consults the apply
window. Commit `5323bfb` adds `acquireSharedCloudOperationInApplyWindow`, which
waits for the window first and takes the gate second; the window can close
between the two steps, so it releases the gate and retries rather than
proceeding across a sync.

**Decisions made**: No timeout was added to the wait. Once the cycle is gone a
long `isConnecting` only delays the publish, which is correct behavior, and a
timeout would turn a slow network into a spurious failure. Reordering is safe
because taking the gate first never bought exclusion in the first place:
`syncNow` gates only on `!isSyncing && !isConnecting` and never reads
`sharedCloudOperationInProgress`.

**Verification**: A new regression test asserts the gate is not held while the
publish waits for a settling connection. It fails on the previous code in 25 of
25 runs under CPU load and passes here. 242 tests in 25 suites pass via
`script/run_tests.sh`. Forty consecutive full-suite runs finished with 0
failures and 0 hangs. Both releases are Developer ID signed as Oliver Ames
(`PV3W52NDZ3`), notarized and stapled, and report "Notarized Developer ID" to
Gatekeeper. 1.6.3 DMG SHA-256
`50f90f628dc3d04c8a047d35579e1f893769b40c0ce90f8424ea2ee54c13e153` matches its
published checksum file, the release asset returns HTTP 200 at 6767331 bytes,
and the signed appcast on gh-pages serves 1.6.3 build 28 and diffs clean
against the repo copy. The notary key fetched from 1Password was deleted from
the scratch directory and confirmed gone.

**Left off at**: Released and clean. `main` is 1.6.3 build 28 with nothing
unpushed.

**Known follow-ups**: The intermittent full-suite hang that prompted this work
was never reproduced on demand; 25 loaded runs of the previous code did not
trigger it. This fixes a proven defect whose mechanism explains that hang
rather than a directly reproduced one, so an unexplained hang recurring on
1.6.3 would mean a second cause. The login keychain's `notarytool-profile`
was locked during this session, so both releases used the 1Password notary key
path (`NOTARY_KEY_FILE`/`NOTARY_KEY_ID`/`NOTARY_ISSUER_ID`) instead. The
previous entry's known follow-ups all remain open and unaddressed.

---

## 2026-08-27 - Adversarial bug-fix rounds: recovery, reconciliation, and Cloud race hardening

**What changed**: Four commits on `main` (`e7461c9`, `dc3c93b`, `7e311bf`, `46adc62`) fix the confirmed defects found across repeated full-repository reviews. Account recovery now keeps unreadable configuration and activity files read-only, retries transient connection failures, serializes sign-in and sign-out ownership, and preserves replacement-frame state when later resource loading fails. Frame changes now hydrate destinations as one persisted transaction and restore the prior frame and resource lists after failure. Chore dates use the selected frame's wall clock, unsupported recurrence rules fail closed, selected recurring reminders keep their occurrence anchor, and parser handling rejects duplicate or lossy recurrence properties.

Photo and removal reconciliation received the largest changes. Mapping teardown keeps durable retry ownership, treats only verified remote absence as completion, prevents shared-photo captions and albums from being removed while another mapping owns them, and updates the in-run deduplication view after moves. Selected-photo Cloud work now runs through one operation gate, tracks the latest portable mapping and asset intent, retains identifiers that PhotoKit cannot resolve, reapplies foreground edits after CloudKit and PhotoKit waits, and acknowledges only records the merged Cloud result accepted. A selected-photo mapping changed to an album or Favorites publishes a durable disabled record, but a later reactivation invalidates every queued retirement before it can write. Cloud preferences use versioned user mutations, so a foreground frame, interval, or dry-run change survives an in-flight refresh.

The release surface also gained stricter appcast helpers and tests, explicit live-test skips, the Apple Notes loop-source regression, and a Sparkle 2.9.6 pin. The private `skylight-bridge-ios` dependency remains pinned to version 0.1.8 at revision `448ee088fdf06247439246ee6ec33dafccb7b607`, even though its upstream tag moved.

**Verification**: `script/run_tests.sh` passes 241 tests in 25 suites plus the appcast helper tests, with five live tests skipped behind their explicit environment flags. The coordinator, identity, and authentication suites pass 106 tests under Thread Sanitizer. All 241 tests pass under Address Sanitizer. `swift build -Xswiftc -warnings-as-errors`, `bash -n` for every script, `plutil -lint`, `xmllint --noout`, and `git diff --check` pass. `script/build_and_run.sh --verify` built and launched the app. The bundle passes strict deep code-signature verification as Developer ID Application Oliver Ames, team `PV3W52NDZ3`, with hardened runtime. A fresh screenshot confirms that the 1.6.1 build 26 Overview window renders cleanly. Gatekeeper rejects only because this local development bundle was not notarized, as expected.

**Left off at**: The fixes are committed on `main` but remain unreleased. The version is still 1.6.1 (build 26). No release archive, notarization submission, DMG, or appcast publication was created in these rounds.

**Known follow-ups**: Ordinary cleanup retries for photos, recipes, and meals do not all treat a later 404 or 410 as successful completion after checkpoint failure. Selected-photo intent remains memory-only, because the shared Cloud contract has no true mapping deletion or per-photo tombstone. Meal date replacement can orphan the previous sitting after a failed delete. Explicit new photo-album and reminder-list creation lacks remote idempotency after checkpoint failure. iOS multi-device link identities still omit the frame ID, and coordination remains disabled until the production CloudKit schema is ready.

---

## 2026-08-26 - Skylight Bridge 1.6.1 released: the adversarial-review fixes ship

**What changed**: Cut and published 1.6.1 (build 26) from the thirteen commits that had accumulated on main since 1.6.0. No code changed this session — the release carries the 2026-08-25 review work as-is. Bump commit `c106e45` moves `Resources/Info.plist` to 1.6.1/26 and updates the README badge, release paragraph, and checksum command off the stale 1.6.0 text. This answers the open question the 1.6.0 entry left: the changes are behavioral fixes to real defects with no new features, so a patch release was the right shape.

**Verification**: 178 tests in 24 suites pass via `script/run_tests.sh`. `build_release.sh` ran with `DEVELOPER_ID_PROFILE` set to `32WNN7T5KR.provisionprofile` ("Skylight Bridge Developer ID CloudKit v2", the profile that authorizes `iCloud.com.oliverames.SkylightBridge`; the other installed profile carries an empty container list and would fail the script's check). Apple notarized and stapled both the app and the DMG (submissions accepted; DMG id `d94a5c2f-a7b9-4c81-83a7-011b5b780960`), and Gatekeeper reports "Notarized Developer ID" for the app, the DMG, and the app as mounted from the DMG. Published https://github.com/oliverames/skylight-bridge/releases/tag/v1.6.1 ; the downloaded `.sha256` diffs clean against local (`3ed838be4206dc0108374e41f0727207b3c57a5530ce37e9d28c693785f304cf`). Signed appcast published to gh-pages (`b09aef1`) serving 1.6.1 build 26; the live feed fetched back over HTTPS diffs clean against the repo copy and `sign_update --verify` accepts its signature. The notary key fetched from 1Password was deleted from the scratch directory and the check confirmed it gone.

**Left off at**: 1.6.1 is live and auto-update is serving it. The release is unverified visually — the same Screen Recording and Automation consent gaps from 2026-08-25 still block pixel capture on this Mac.

**Open questions**: Unchanged from the 2026-08-25 entry; see Open items.

---

## 2026-08-25 - Adversarial review pass: 24 confirmed defects fixed, no regressions

**Follow-up (same day)**: Tackled the deferred items. (1) Response-side chore status, list kind, and item status now decode leniently — a server-added value becomes nil instead of failing the whole collection, matching the API_EVIDENCE compatibility policy; request-side structs stay strict, and the chore planner skips completion reconciliation when a status is unreadable so it cannot push the same write every sync (`7e7093f`). That commit also carries three adjacent dead-field drops (reward redeemedAt/currentPointBalance, grocery redirectURL) staged with the same files. (2) Reminder updates and merges now coalesce checkpoints like photos, while creates, deletions, and suppression marks keep immediate writes; the upload-readiness poll calls GET /messages/{id} directly with 404 as the normal not-yet-queryable window, removing listing page-order dependence; a contract test pins thirty unchanged photos rendering zero times with fewer state writes than assets (`3d1d2d5`). (3) Eight decoded-but-unread response fields removed along with the photo-collection parentID plumbing (`257bf03`); SkylightJSONValue stays (live probe uses it) and upload-descriptor localFileID stays (it is encoded into requests, the finder's "dead" claim was wrong there). Also noted: AppleNoteAttachmentSnapshot is never constructed anywhere — the attachments surface is inert, a decision for later. (4) The navigation test now asserts every non-hidden section reaches the sidebar exactly once, and the Notes-script test asserts every repeat loop dereferences its variable — both previously compared constants against themselves (`d1300eb`). Visual verification attempt: the signed app launched and its main window renders on-screen (CGWindowList shows it), but pixel capture is still blocked — `screencapture` fails with "could not create image from display" (Screen Recording permission) and System Events Apple Events time out (no Automation consent), attempted live 2026-08-25. Suite grew to 178 tests; full suite green under AddressSanitizer and the coordinator/session/auth/chore suites under ThreadSanitizer. Commits `7e7093f`, `3d1d2d5`, `257bf03`, `d1300eb` pushed.

**What changed**: Full-repo review with five parallel finders (sync logic, networking/auth, parsers, stores/UI, cross-file consistency), every finding re-verified by an independent skeptic agent whose default stance was refutation, then fixes shipped in five scoped commits. 173 tests pass, up from 153; zero build warnings; coordinator/session/auth suites also pass under ThreadSanitizer and the whole suite under AddressSanitizer. Commits `12bb5c4` (parsers/fingerprints), `fff2fb9` (session hardening), `cc40443` (sync engine + teardown + store), `37a1de0` (dead code), `c0ed41e` (docs/CI/scripts).

Confirmed and fixed, highest impact first:
1. **Recurring-reminder resurrection**: deleting a recurring item on Skylight dropped the sync record while sparing the Apple reminder, so the next sync re-created it — forever. The record now carries `remoteSuppressedAt`, suppressed links plan nothing, and editing the Apple reminder afterwards lifts the suppression and re-pushes.
2. **Offline teardown data loss**: purge/teardown swallowed delete failures (`try?`), forgot the records anyway, and logged success, permanently stranding the Skylight copies. Transient errors now abort with records intact; only 404/410 count as done; AppStore keeps the mapping for retry and the confirmation buttons disable while a sync runs.
3. **Teardown raced scheduled syncs**: remove-mapping paths bypassed both `isSyncing` and the process lock, letting a concurrent checkpoint resurrect purged state or drop in-flight records. All three removals now run under the same guards as `syncNow`.
4. **Token-refresh race**: two overlapping 401s each replayed the pre-rotation refresh token against a rotating server (RFC 9700 reuse-detection can revoke the grant). Refreshes are single-flight now; the rotated pair persists refresh-token-first.
5. **Silent credential logins**: any probe failure (timeout, 5xx) fell through to a full password login on every scheduled sync; only 401/403 now trigger reconnect.
6. **Parser corruption**: "0.5 cup sugar" became "5 cup sugar" via list-marker stripping; decimal quantities survive. Date-only UNTIL landed at UTC midnight and cut the final day's occurrence (now local 23:59:59); COUNT+UNTIL throws instead of dropping COUNT. Skylight summaries with embedded newlines collapse to one line.
7. Also fixed: shared dedup messages deleted out from under a second mapping's record; one-off chore postponement read as completion; dry-run previews fabricating deletions when the destination list needed creating; dedup cache going stale after in-run uploads; pagination loops without bounds; poll errors masked as fake photo timeouts; note records frame-scoped (frame switching orphaned/duplicated recipes); configuration silently resetting past its asymmetric 1 MB read cap (now symmetric 4 MB with stale-name pruning); startup bound to window lifetime with a latch blocking retry; Sync Now enabled for hidden-meals-only configs; donation prompt evaluated mid-sync with `isSyncing: false`; every autosave restarting the scheduler countdown; activity unbounded in memory; stale failure banner after sign-out or reconnect; Sign Out unavailable exactly when connection restore failed; sign-out now revokes the refresh token too and deletes all four secrets independently; unused change-observation plumbing, Notes account enumeration, three request helpers removed; README updated from stale 1.5.13 to 1.6.0; CI test step routed through `run_tests.sh`; publish_appcast.sh verifies the DMG's bundled version before signing.

**Decisions made**: Verified the riskier calls against primary sources before shipping. RFC 5545 §3.3.10 states UNTIL bounds recurrence inclusively and that UNTIL and COUNT "MUST NOT occur in the same recur", so both converter changes are standards-correct (https://www.rfc-editor.org/rfc/rfc5545.html). RFC 9700 §4.14.2 documents that rotation invalidates the previous refresh token and that replay triggers revocation of the active tokens, confirming the single-flight fix addresses a real session-killer against Skylight's documented rotating refresh tokens (https://www.rfc-editor.org/rfc/rfc9700.html; docs/API_EVIDENCE.md line 26). RFC 7009 §2.1 makes access-token revocation's cascade to refresh tokens only a MAY, confirming sign-out should post the refresh token itself (https://www.rfc-editor.org/rfc/rfc7009.txt). Apple's EKRecurrenceEnd docs confirm an end is either date-based or count-based, never both (https://developer.apple.com/documentation/eventkit/ekrecurrenceend).

Deliberately not changed, with reasons: recipe plaintext ambiguity (a description line shaped like `Servings:` or a bare `Ingredients`) is documented in PRODUCT_SPEC.md instead of fixed — narrowing the parser would misparse notes earlier builds already wrote, converging after one normalization at worst; strict enum decoding of chore/list statuses stays until Skylight actually ships an unknown value, since naive tolerance would churn planners; the upload-readiness poll still scans `__START__` listings rather than calling `getMessage` directly because post-PUT readability is unverified live; decoded-but-unread response model fields stay as API-surface documentation; the near-tautological navigation/Notes-script tests stay. Skeptics refuted two finder claims outright: concurrent `refreshSharediCloudState` cannot duplicate photo mappings (check-plus-append is atomic on the main actor), and caption clearing is unreachable in the UI (documented retention intent).

**Verification**: 173 tests in 24 suites pass normally, the coordinator/session/auth subset passes under ThreadSanitizer, and the full suite passes under AddressSanitizer. Zero build warnings (the two retroactive-Sendable warnings are fixed by explicit `@unchecked Sendable`). `bash -n` passes on all touched scripts. Pushed to origin/main through `c0ed41e`.

**Left off at**: Five commits on main, unreleased; version still 1.6.0 (build 25). No appcast or DMG produced this session.

**Open questions**: Ship these fixes as 1.6.1 (they are behavioral fixes to real defects, which argues for a release). Carried from 1.6.0: unchanged; see Open items. New: live-probe whether freshly uploaded messages are readable via GET /messages/{id} to replace the listing-based readiness poll.

---

## Earlier history (before 2026-08-23)

- 2026-08-17 - Released 1.6.0 (build 25): confirmed Sign Out backed by `SkylightSessionManager.signOut()`, removed the deprecated plaintext `createLegacySession`, `FeatureFlags.mealSyncEnabled = false` gates the hidden Meals engine, Notes denial routes to System Settings, dead-code sweep; the `SkylightAPIClient+*` endpoint methods stay as documented API coverage; the 1.5.14 bump `fa5eaa5` was folded in and no 1.5.14 was published; `5719215`, `f947a43`, `2a1a25b`, gh-pages `9182bac`, 153 tests.
- 2026-08-17 - Four field fixes, unreleased on 1.5.13: Notes folders load on the Notes pages and at startup only when permission is already granted (reading them launches Notes); Remove Link for Notes selections; "Save Fix Script…" replaced pasted commands because interactive zsh history-expands the `!` in `#!/bin/bash`; photo sync skips render and encode on a matching `sourceFingerprint` and coalesces checkpoints every 25 changes while uploads still write immediately; `dca936e`, `a52aab8`, `27ff5a0`, 155 tests.
- 2026-08-13 - Released 1.5.13: `FeatureFlags.multiDeviceCoordinationEnabled` (default false) gates the undeployed `ClientHeartbeat` and `SharedSyncState` CloudKit paths after a Reddit report; a production deploy attempt failed because CloudKit will not promote an empty record type and the Development build hit launchd error 163 on an unregistered device; an automated `sync` commit `d8871e7` leaked a debug hook and dist-dev, reverted in `ebee760`; gh-pages `5e624f5`, 152 tests.
- 2026-08-13 - Released 1.5.12: guided AMFI permission fix that copies a grant script but never writes TCC.db itself (Oliver's "Fix Permissions" button declined: Developer ID revocation risk); `syncNow()` calls `launchNotesIfNeeded()` to fix "Connection is invalid"; "did not find record type" treated as the undeployed-schema error; gh-pages `1edc130`, 151 tests.
- 2026-08-13 - Released 1.5.10 and 1.5.11 for blocked consent prompts on home-server: `amfi_get_out_of_my_way=1` makes third-party processes platform-flagged, and tccd logs `CS_PLATFORM_BINARY set but not AppleSigned; prompt policy is Deny`; not a blanket block, and the boot arg stays for BlueBubbles Private API; Oliver granted Photos, Reminders, and Notes through direct TCC.db inserts (SIP off); gh-pages `c33a00b`, `098debd`.
- 2026-07-30 - Released 1.5.9 from `d5cecf4` (gh-pages `0656f16`): Reminders EventKit entitlement, direct Notes automation request, foreground activation before consent prompts; created `SharedSyncState` and a partial `ClientHeartbeat` in CloudKit Development; home-server Screen Sharing blocked after a TCC reset (handoffs in `~/.codex/handoffs/2026-07-30-skylight-bridge-*.json`).
- 2026-07-27 - Released 1.5.8 (build 18): recurring-chore recovery keeps the newest uncompleted EventKit occurrence and removes the extra Apple copies so duplicates cannot compound; tag `v1.5.8` at `881271c`, gh-pages `26405f8`, 146 tests.
- 2026-07-24 - Multi-device coordination: `[sb:hash]` caption photo deduplication, CloudKit heartbeats, title-only reminder adoption, `SharedSyncState` and `CloudSyncStateStore` in the shared package, bumped to 0.1.8; 145 Mac tests.
- 2026-07-23 - Fixed duplicate Apple Reminders for recurring chores (rebind from a completed occurrence to exactly one matching uncompleted one) and stale due dates (drift check emits `updateApple`); 145 tests.
- 2026-07-22 - Released 1.5.7 (build 17): Notes AppleScript dereferences every object before reading properties; one-off chores no longer send recurrence-only fields that caused HTTP 422; chore mapping removal asks which side to keep; tag `8121125`, gh-pages `048800b`. Added CI that validates build and tests only, with signing kept out.
- 2026-07-16 - Released 1.5.5 (on-device Apple Intelligence names for selected photos; tag `2d89edb`, gh-pages `7dc0b88`) and 1.5.6 (build 16: two-way chores, list title and color sync from `f03b347`, photo names as Skylight captions; first sync records values without relabeling, no color clearing; tag `5333d62`, gh-pages `4e9d804`).
- 2026-07-16 - Released 1.5.4 (build 14): deployed the CloudKit production schema and the `SharedPhotoMapping` record-name index, undeployed-schema errors logged as recoverable, bundled Sparkle, EventKit callbacks kept on the main actor for the reported crash; tag `352ffe6`.
- 2026-07-15 - Released 1.5.0 (10) and 1.5.1 (11): a Developer ID app using CloudKit needs an embedded profile authorizing `iCloud.com.oliverames.SkylightBridge`, or launchd refuses it with error 163; the release script now requires and embeds `DEVELOPER_ID_PROFILE` and drops the global warnings-as-errors flag; tags `dfc1b0d`, `12cec5b`.
- 2026-07-15 - Meal fallback-category repair (`6a570e2`), Chore Chart setup and two-way sync (`b6a8891`), iPhone companion CloudKit reconciliation (`db384c6`, `943848e`, `3107391`, package 0.1.7), Relay Ribbon icon (`0f6f46b`); cloud sharing limited to settings and individual-photo mappings, explicit removals beat stale selections; a recipe manually placed in the first category can look like an old fallback during repair.
- 2026-07-14 - Released 1.4.0 (9): shared `groupedPageLayout()` margins, 720x520 minimum window, first-run onboarding, donation prompts at 50/500/2,000/10,000 applied changes with state in UserDefaults, HIG pass (pop-up buttons, switch plus ellipsis menu rows, symbol status badges).
- 2026-07-14 - Released 1.3.0 (8): on-device FoundationModels recipe classification cached on the record, a title emoji on the Skylight summary only, emoji-insensitive title matching, shared albums in the photo picker.
- 2026-07-14 - Released 1.2.4 (7): reminder churn came from `.secondsSince1970` date encoding losing sub-microsecond precision, fixed with a 1 ms planner tolerance; a failed album listing never authorizes deletion; every persisted record decodes per field; UX sweep with autosaved Sync settings.
- 2026-07-14 - `SyncState` decode failure fixed in `8eec0c2` and `21d1773`: synthesized `init(from:)` ignores property defaults, so every persisted Codable struct uses `decodeIfPresent` per field; Notes TCC probe via `AEDeterminePermissionToAutomateTarget`; Hide Dock icon toggle.
- 2026-07-14 - Released 1.2.3 (6): deletes a bridge-created Skylight album only when empty, recipe parser fixes, menu bar pulse; Skylight does not persist the structured ingredient array; tag `aeebb93`.
- 2026-07-14 - Released 1.2.2 (5): an inline `Button` in a Form row needs an explicit button style or macOS routes the click to the row (tag `db68dd6`); 1.2.1 (4) moved Account, Sync, and Diagnostics into the main window sidebar (tag `6e8c0c4`).
- 2026-07-14 - Released 1.2.0 (3): `PhotosPicker` needs `photoLibrary: .shared()`, photo-mapping deletion purges Skylight copies, reminder-mapping deletion asks per side, field-level two-way merge, auto-sync on mapping save; tag `fff269a`.
- 2026-07-14 - Released 1.1.0 (2): symmetric list linking with title and completion adoption, optional two-way recipes (Skylight deletions move notes to Recently Deleted), grouped-settings redesign; notes with attachments are never rewritten; tag `c714a5f`.
- 2026-07-13 - Released 1.0.0 privately: Apple is the source of truth, with no calendar, task, chore, or rewards sync; tag `a6c66ac`, portable-checksum fix `5618e8a`.
