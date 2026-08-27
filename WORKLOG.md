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

**Open questions**: Unchanged from the previous entry, all carried: visually verify the sign-out, Remove Link, and permission-denial UI (best done on home-server once it updates to 1.6.1); deploy the `ClientHeartbeat` and `SharedSyncState` record types to the CloudKit production schema, then flip `multiDeviceCoordinationEnabled`; decide whether the Meals workflow gets finished or removed; decide on revoking the 2026-08-13 Apple Development cert; live-probe whether freshly uploaded messages are readable via `GET /messages/{id}` to replace the listing-based readiness poll. Also noted on 2026-08-25 and still undecided: `AppleNoteAttachmentSnapshot` is never constructed, so the attachments surface is inert.

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

**Open questions**: Ship these fixes as 1.6.1 (they are behavioral fixes to real defects, which argues for a release). Carried from 1.6.0: visually verify the sign-out/Remove Link/denial-state UI; deploy CloudKit production schema for ClientHeartbeat/SharedSyncState then flip multiDeviceCoordinationEnabled; decide Meals workflow fate; decide on revoking the 2026-08-13 Apple Development cert. New: live-probe whether freshly uploaded messages are readable via GET /messages/{id} to replace the listing-based readiness poll.

---

## 2026-08-17 - Skylight Bridge 1.6.0: sign-out, security sweep, dead-code cleanup, published release

**What changed**: Second sweep of the day on top of the four field fixes, then the 1.6.0 release. Commits `5719215` (review fixes), `f947a43` (dead code), `2a1a25b` (bump).

Review findings, all fixed: (1) No sign-out existed — credentials and tokens persisted forever and the OAuth revoke endpoint had no caller; the Account page now has a confirmed Sign Out backed by `SkylightSessionManager.signOut()`, and a scheduled sync retries the connection then goes quiet when signed out. (2) `createLegacySession` sent plaintext credentials to a deprecated endpoint with zero callers; removed with its models and three other dead symbols. (3) The hidden Meals workflow still synced for anyone who enabled it before it was hidden; `FeatureFlags.mealSyncEnabled = false` now gates the engine in lockstep with the hidden UI (ship-state test added). (4) A denied Notes Automation permission rendered as "Not requested" with a dead request button; denial is now tracked and routed to System Settings. (5) The Overview sync button offered syncs that immediately failed when signed out; it now shares the toolbar's conditions.

Dead-code sweep: removed `PhotoSyncPlanner` + `PhotoSyncModels` + tests (superseded by `SyncCoordinator.syncPhotos`), `Bootstrap`, `purgeChoreMapping` (superseded by `teardownChoreMapping`), `currentTokenPair`, `requiredDescriptor`, `userVisibleCaption`. Pruned the merged `claude/blissful-herschel-8fb46f` worktree and branch. Cleared the last build warning (`String(cString:)` → `String(decoding:)`). The large block of unused `SkylightAPIClient+*` endpoint methods was deliberately kept: they are the documented "Discovered API coverage" surfaced in Diagnostics.

**Decisions made**: Endpoint-coverage methods are product surface, not dead code. Meals gating lives in `AppStore.syncConfiguration` (forced-off copy) so the coordinator and tests stay flag-free. The 1.5.14 bump (`fa5eaa5`) was folded into 1.6.0; no 1.5.14 was published.

**Verification**: 153 tests pass, zero build warnings. `build_release.sh` notarized and stapled app + DMG; Gatekeeper accepts both ("Notarized Developer ID"). Published https://github.com/oliverames/skylight-bridge/releases/tag/v1.6.0 ; downloaded `.sha256` diffs clean against local (`35b43397cec111a0325196300abce94a0477f26f0b0a4b46d8888271089915c2`). Signed appcast published to gh-pages (`9182bac`), serving 1.6.0 build 25.

**Left off at**: 1.6.0 is live. The new UI (Sign Out, Remove Link, denial states) is built and logic-tested but NOT visually verified — another Claude session held the computer-use bridge for the whole session and `screencapture` lacks Screen Recording permission. Verify visually on next launch or on home-server after it updates.

**Open questions**: Visual verification of the 1.6.0 UI. Carried: CloudKit production schema deploy for `ClientHeartbeat`/`SharedSyncState`, then flip `multiDeviceCoordinationEnabled`; decide on revoking the 2026-08-13 Apple Development cert; decide whether the Meals workflow gets finished or removed outright.

---

## 2026-08-17 - Four field-reported fixes: Notes folders, Notes unlink, TCC script paste, photo sync performance

**What changed**: Four defects Oliver reported from home-server use, in three commits on top of 1.5.13 (unreleased; version still 1.5.13).

1. **Notes folders never appeared** (`dca936e`). `notesFolders` was populated only inside `AppStore.requestNotesAccess()`, while `refreshSources()` reloaded Photos collections and Reminders lists and skipped Notes entirely. After the first launch the folder picker was empty even with Automation access already granted, so a saved folder showed no selection. Added `AppStore.loadNotesFolders()`, called from a `.task` on the Notes pages and from `refreshSources()` only when `AppleNotesStore.authorizationStatus() == .granted` (a definite answer implies Notes is already running, so no Apple Event silently launches it at startup). The picker also keeps a previously saved folder as an entry when the live list has not arrived, which otherwise made saving drop the link.

2. **No way to unlink a Notes folder** (`dca936e`). The row menu offered only Edit. Added Remove Link to the row menu, the context menu, and the editor, behind a `confirmationDialog`, backed by `AppStore.removeNotesSelection(kind:)` which resets the `NotesSelection` while preserving its `id`, saves, and logs an Activity entry naming the unlinked folder.

3. **The permission-fix paste did not work** (`a52aab8`). Root cause is zsh, not TCC: pasting the whole script into an interactive shell makes zsh treat the `!` in `#!/bin/bash` as a history expansion, producing exactly the `zsh: event not found: /bin/bash` in Oliver's screenshot. Interactive zsh also does not enable comments by default, so the comment block would have failed next. Replaced "Copy Fix Commands…" with "Save Fix Script…": `SystemSecurityDiagnostics.writePermissionGrantScript()` writes the script into Application Support at 0700, the view reveals it in Finder so it can be read before running, and the pasteboard gets only `permissionGrantCommand(forScriptAt:)`, a single `bash '<path>'` line with no `!` and no `#`.

4. **Photo sync was slow and overwhelmed the machine** (`27ff5a0`). Three separate costs:
   - `syncPhotos` rendered and JPEG-encoded **every** asset on **every** run, downloading from iCloud when needed, purely to compare the resulting hash with the hash already stored. Added `PhotoSyncRecord.sourceFingerprint` (asset id, modification date, adjustment date, pixel dimensions, adjustment state, mapping's `maximumLongEdge` and `jpegQuality`) via `PhotoDeduplication.sourceFingerprint(for:maximumLongEdge:jpegQuality:)`. A matching fingerprint skips the render and encode entirely. Records written before the field existed render once more and then store it, so the upgrade is self-healing.
   - `checkpoint()` JSON-encodes, HMAC-seals, and atomically rewrites the *whole* sync state, and was called after every photo, making a run quadratic in record count. Added `markStateDirty()` / `checkpointIfDue()` coalescing at 25 changes; each domain still flushes at its end, and an upload keeps its own immediate write because losing that record means re-uploading the same bytes.
   - The selected-photos editor sorted the whole selection through a `photoTitle`-lookup comparator *inside* `body` and built one non-lazy Form row per asset, so every generated Apple Intelligence name re-sorted and re-rendered the entire list. Display order now lives in `@State` and is rebuilt only on real changes, rows scroll in a `LazyVStack`, and names apply in batches of 10 with an "n of N" progress line.

**Decisions made**:
- Notes folders are **not** loaded unconditionally at startup. Reading them sends an Apple Event, which launches Notes; doing that on every launch is intrusive. The startup path runs only when the permission answer is already definite, and the Notes pages carry the general case.
- Rejected a hard cap on Apple Intelligence photo naming. The on-device model is a single shared resource so the work stays sequential; the fix is that the UI no longer stalls while it runs, and progress is now visible. Hundreds of photos still take minutes.
- The upload path keeps a per-item checkpoint while bookkeeping updates coalesce. Losing a bookkeeping update costs a recomputation; losing an upload record costs a duplicate upload.
- `docs/PRODUCT_SPEC.md:21` already claimed the bridge records a "render fingerprint". It did not until now. The implementation moved to match the spec rather than the other way round; no doc edit was needed.

**Verification**: 155 tests pass (`swift test`), up from 152. New coverage: an unchanged photo renders zero times when its fingerprint matches and older state gains a fingerprint on one more render; a photo with a stale fingerprint is re-rendered; the grant script is written 0700 and its copied command contains no `!`, `#`, or newline. `./script/build_and_run.sh build` produces a signed bundle. Commits `dca936e`, `a52aab8`, `27ff5a0` pushed to `origin/main`.

**Left off at**: All four fixes are on `main`, unreleased. Version is still 1.5.13; no appcast, notarization, or DMG was produced this session.

**Open questions**:
- NEW: The new UI (Remove Link, the Save Fix Script panel) is built and logic-tested but **not visually verified**. Computer-use access was denied when requested. The BlockedPromptFix panel only renders under AMFI-disabling boot arguments anyway, so home-server is the only place to see it.
- NEW: Decide whether these fixes ship as 1.5.14 or wait for more work. They are user-visible fixes to reports from real use, which argues for a release.
- Still open (from 1.5.13): deploy the `ClientHeartbeat` and `SharedSyncState` record types to the CloudKit **production** schema, then flip `FeatureFlags.multiDeviceCoordinationEnabled` on. Needs a registered development device to run a Development build that publishes real records, then a console promote.
- Still open (from 1.5.13): decide whether to revoke the Apple Development certificate created on 2026-08-13 (identity SHA-1 `6FFCB2B37E85086E8150CE4C7AD0F6CA0023A99A`).

---

## 2026-08-13 - Skylight Bridge 1.5.13: gate undeployed multi-device coordination

**What changed**: Added `FeatureFlags.multiDeviceCoordinationEnabled` (default false) and gated the three CloudKit paths that touch record types not deployed to production — `publishAndCheckHeartbeat` (ClientHeartbeat) inside `refreshSharediCloudState`, and `importSharedSyncState`/`publishSharedSyncState` (SharedSyncState). Shared preferences and selected-photo sync use already-deployed types (SharedPreferences, SharedPhotoMapping, SharedPhotoSelection) and keep running. A test asserts the flag ships off.

**Why**: A Reddit user (mitty22) reported the Activity message "Could not import sync state from iCloud: Did not find record type: SharedSyncState". Root cause: the ClientHeartbeat and SharedSyncState record types were never deployed to the container's production CloudKit schema, but the signed app runs against Production and publishes them. 1.5.12 only suppressed the repeat warning down to one message; 1.5.13 removes the message entirely by not making the calls. Flip the flag on once the schema is deployed.

**CloudKit production deploy attempt (did NOT complete)**: Tried to deploy the schema instead of gating. Blockers, in order: (1) CloudKit won't promote an "empty" record type — needs a record with populated fields; console record-creation is blocked from typing field values by the environment's safety classifier. (2) Publishing real records needs a Development-CloudKit build. Created an Apple Development cert under team PV3W52NDZ3 (CSR via openssl, uploaded in the developer portal via Chrome, imported as a legacy PKCS#12; identity SHA-1 6FFCB2B37E85086E8150CE4C7AD0F6CA0023A99A, CN shows "(Y3Z79XM83W)" but OU=PV3W52NDZ3). Built + signed a Development bundle (icloud-container-environment=Development, Mac Team Provisioning Profile). (3) That bundle won't launch via LaunchServices (RBS error 163 / launchd spawn failed) because this Mac (Provisioning UDID 00006020-001C71EA0A6B401E) is not a registered development device in the profile; running the raw binary doesn't give CloudKit a proper app context, so no records published. Finishing the deploy needs: register the device, regenerate/re-embed the profile, re-sign, re-auth the CloudKit console, run, promote. Deferred in favor of the gate.

**Cleanup**: An automated `sync` commit (d8871e7) had captured in-progress local work onto public main — a debug-only bootstrap hook (SKYLIGHT_BOOTSTRAP_DEV_SCHEMA, dormant) and a tracked dist-dev build. Reverted the hook, untracked dist-dev, added it to .gitignore, committed (ebee760) and pushed. History still holds d8871e7 (no secrets: a provisioning profile carries no private keys), not force-rewritten.

**Verification**: 152 tests pass. `./script/build_and_run.sh --verify` launched the signed bundle cleanly. Apple notarized and stapled the app and DMG; Gatekeeper accepts both. Published checksum SHA-256 `2b26e93297e550d89474987176fc54de519a77374953975f036ac19f873c8a77` matches; signed live appcast matches the repo copy (gh-pages `5e624f5`).

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.13

**Open questions**: Deploy the ClientHeartbeat + SharedSyncState record types to the CloudKit production schema (needs a registered dev device to run a Development build that publishes real records, then a console promote), then flip `multiDeviceCoordinationEnabled` on. Decide whether to revoke the newly created Apple Development cert.

---

## 2026-08-13 - Skylight Bridge 1.5.12: guided permission fix + Notes-sync and iCloud-warning fixes

**What changed**: Three things. (1) A guided fix for the AMFI-suppressed-prompt condition: when a boot argument disables Apple Mobile File Integrity, macOS suppresses privacy consent dialogs for non-Apple apps, so Diagnostics now explains the condition, links to Privacy settings, and can copy a self-contained Terminal script (`SystemSecurityDiagnostics.permissionGrantScript()`, csreq blobs + bundle identity resolved at runtime) that grants Photos/Reminders/Notes. The app never writes the TCC database itself. (2) Scheduled syncs failed with "Apple Notes automation failed: Connection is invalid" because `syncNow()` never launched Notes and Apple Events need a live target; it now calls `launchNotesIfNeeded()` (no focus steal) before a sync whose recipe or meal source is enabled. (3) The import path logged "Could not import sync state from iCloud: Did not find record type: SharedSyncState" every run; `SharedCloudKitFailure.isProductionSchemaConfigurationError` now also matches "did not find record type" (the read-side face of the undeployed-production-schema condition the publish path already suppressed), leaving only the single actionable "needs its schema deployed" message.

**Design decision (declined a request)**: Oliver asked for a "Fix Permissions" button that runs the grant commands. Shipping a programmatic TCC.db write inside a signed app is a bypass that only works with SIP disabled and that Apple treats as malware (Developer ID revocation risk), and it defeats consent/audit. Chose the guide-and-copy design via AskUserQuestion instead; the user agreed. The peer session apple-core-88 was told the same, with the cross-session-permission caveat.

**Underlying infra still open**: The `SharedSyncState` (CloudSyncStateStore) record type is not deployed to the CloudKit **production** schema, so multi-device sync-state sharing does not actually run; 1.5.12 only silences the benign repeat warning. Deploying that record type via the CloudKit console/cktool is the real fix and is Oliver's action.

**Verification**: 151 tests pass (new coverage for the grant-script contents, the boot-arg detection, and the "did not find record type" matcher). `./script/build_and_run.sh --verify` launched the signed bundle cleanly. Apple notarized and stapled the app and DMG; Gatekeeper accepts both. Published checksum SHA-256 `46566f5c19ba279b300ce08a0f6a6f0a5100ec7f7e2de5b4b19a67f33b74379b` matches; signed live appcast matches the repo copy (gh-pages `1edc130`). The BlockedPromptFix UI and the Notes-launch-at-sync path are logic-verified but not visually confirmed on this Mac (clean boot-args); best confirmed on home-server after it updates to 1.5.12.

**Earlier today**: 1.5.10 (detect AMFI-suppressed prompts), 1.5.11 (reworded the diagnostic after proving the boot arg is not a blanket block: BlueBubbles got a FocusStatus consent prompt under the same boot args). Oliver granted Photos/Reminders/Notes on home-server via direct TCC.db inserts (SIP off), all three now Authorized.

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.12

**Open questions**: Deploy the SharedSyncState record type to CloudKit production (Oliver). Verify Notes sync succeeds on home-server after it updates to 1.5.12.

---

## 2026-08-13 - Skylight Bridge 1.5.11 blocked-consent wording + verified TCC root cause

**What changed**: Version 1.5.11 rewords the blocked-prompt diagnostic added in 1.5.10. The old copy claimed macOS "cannot show permission prompts" and prescribed removing the boot argument + restarting as the only fix; the new copy states that macOS suppresses consent dialogs for non-Apple apps while AMFI is disabled and that access can be restored by removing the boot argument OR granted another way.

**Root cause (now proven, correcting the 1.5.9/1.5.10 record)**: The earlier "AMFI disables every Developer ID prompt" claim was overstated. Live tccd streaming on home-server (Tahoe 26.5.2, up 13 days on `amfi_get_out_of_my_way=1` + SIP off) showed the exact denial: `CS_PLATFORM_BINARY set but not AppleSigned; prompt policy is Deny`. With AMFI out of the way every third-party process is platform-flagged, and Tahoe's tccd refuses consent dialogs for a platform-flagged non-Apple binary. It is NOT a blanket block: BlueBubbles got a FocusStatus consent prompt (auth_reason=2) under the same boot args, which is why the wording changed. The on-disk bundle is flawless (spctl "Notarized Developer ID: accepted", codesign --deep --strict valid), so nothing is wrong with the app or its signature. The boot arg is load-bearing: BlueBubbles Private API on Tahoe requires SIP off + `amfi_get_out_of_my_way=1` (BlueBubbles docs), and BlueBubbles was reinstated 2026-08-12.

**Fix that worked on home-server (no reboot, keeps BlueBubbles)**: Because SIP is off the user TCC.db is writable. Oliver inserted Allow rows into `~/Library/Application Support/com.apple.TCC/TCC.db` with a csreq blob (`codesign -d -r-` -> `csreq -r- -b` -> hex) for kTCCServiceReminders and kTCCServicePhotos, then `killall tccd`. Both went to Authorized immediately (confirmed in the app's Apple access panel). Notes (kTCCServiceAppleEvents targeting com.apple.Notes) still needs its row: same client csreq plus indirect_object_identifier='com.apple.Notes' and indirect_object_code_identity = Notes' own csreq. Claude is walled off from executing TCC-database edits (auto-mode classifier blocks the write and even the csreq generation), so Oliver runs those commands.

**Verification**: All 149 tests pass (SecurityHardeningTests covers boot-arg detection + explanation gating). `./script/build_and_run.sh --verify` launched the signed bundle cleanly. Apple notarized and stapled the app and DMG; Gatekeeper accepts both. Published checksum SHA-256 `305cb3fb95d731c13c7d1f3451a49429535ea0c24f592651dbce318423c07626` matches the local digest; the signed live appcast matches the repo copy (gh-pages `098debd`).

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.11

**Open questions**: None. Notes TCC row is a manual one-liner for Oliver; everything else is done.

---

## 2026-08-13 - Skylight Bridge 1.5.10 blocked-consent diagnosis release

**What changed**: Version 1.5.10 detects AMFI-disabling boot arguments (`kern.bootargs` via the new `SystemSecurityDiagnostics`) and, when a Photos, Reminders, or Notes permission request ends with no recorded TCC decision, replaces the generic "not authorized" error with the actionable explanation (remove the boot argument, restart, request again). The same warning appears in Diagnostics.

**Root cause**: The 1.5.9 code fix was correct but could not help on `home-server`: that Mac still boots Tahoe 26.5.2 with `amfi_get_out_of_my_way=1` (live-verified 2026-08-13 via `sysctl kern.bootargs`), and Tahoe refuses every Developer ID consent prompt while AMFI is disabled. TCC on the server holds no Photos/Reminders/AppleEvents rows for the app, confirming prompts were never registered. The boot argument is load-bearing again: BlueBubbles was reinstated on 2026-08-12 (LaunchAgent `com.bluebubbles.server`, app running), and its Private API mode is the standard reason for SIP-off + AMFI-off. Removing the boot argument therefore trades Skylight Bridge prompts against BlueBubbles Private API, needs `sudo` and a restart, and is left as Oliver's decision.

**Verification**: All 149 tests pass (two new SecurityHardeningTests cover boot-argument detection, including the literal home-server string, and explanation gating). `./script/build_and_run.sh --verify` launched the signed bundle cleanly; the Diagnostics warning row cannot render on this Mac (clean boot-args), so the on-server presentation is built but not visually verified. Apple notarized and stapled the app and DMG; Gatekeeper accepts both. Published checksum SHA-256 `72cd64a7a04213a2faf33c2980f03a456543c70220fd65a9d94131b242f726ec` matches the local digest, and the signed live appcast matches the repo copy (gh-pages `c33a00b`).

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.10

**Open questions**: Whether to remove `amfi_get_out_of_my_way=1` from home-server's boot-args (breaks BlueBubbles Private API, needs sudo + restart) or leave Skylight Bridge permissions ungrantable on that Mac.

---

## 2026-07-30 - Skylight Bridge 1.5.9 permission request release

**What changed**: Version 1.5.9 adds the required Reminders privacy entitlement, asks for Notes automation access directly against a running Notes app, and brings Skylight Bridge to the foreground before macOS presents Photos, Reminders, or Notes consent.

**Root cause**: The 1.5.8 Reminders request was missing its EventKit entitlement, and Notes relied on an indirect AppleScript prompt that Tahoe denied. Live testing also found that `home-server` boots with SIP disabled and `amfi_get_out_of_my_way=1`; Tahoe rejects every Developer ID privacy prompt while AMFI is disabled, including correctly signed apps.

**Verification**: All 147 tests pass from clean commit `d5cecf4`. Apple accepted notarization submissions `c5d88e50-03e6-48c5-9a35-493ae669387e` for the app archive and `ff5f7f12-b5a9-4bc6-9327-be44e460e4ec` for the DMG. The published checksum matches SHA-256 `9aced5f030bd615fa951902ec165b267fc6b8f8122fc14a0b28c82c45deac2e3`, and the signed live appcast matches `gh-pages` commit `0656f16`.

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.9

**Home Server**: The exact published release is installed and passes strict code-signing and Gatekeeper checks. The remaining live prompt test requires removing the AMFI-disabling boot argument and restarting the Mac; that system-wide change is waiting for Oliver's approval.

---

## 2026-07-30 - New-Mac permissions and CloudKit schema investigation

**What changed**: Added a foreground activation path around Photos, Reminders, and Notes consent requests, added the Reminders privacy entitlement, and made Skylight HTTP failures identify the endpoint while continuing to redact unstructured response bodies. Built and notarized a 1.5.9 test release and installed it on `home-server`. In CloudKit Development, created the complete `SharedSyncState` record type and created the still-incomplete `ClientHeartbeat` record type.

**Decisions made**: The permission changes remain uncommitted until they are tested after a clean TCC reset and ordinary post-reboot launch. The CloudKit schema will not be deployed to Production until `ClientHeartbeat` has the code-required `payload` Bytes and `installationID` String fields.

**Left off at**: Oliver reset all privacy permissions and restarted `home-server`. Automatic login and Skylight Bridge launch succeeded, but Screen Sharing remained blocked even after `kickstart` reactivated Remote Management and granted `oliverames` remote access and control. macOS 26 reported that Screen Recording and Screen Control must be enabled through local System Settings or MDM. Resume Screen Sharing recovery from `/Users/oliverames/.codex/handoffs/2026-07-30-skylight-bridge-screen-sharing-blocked.json`, then continue the app work from `/Users/oliverames/.codex/handoffs/2026-07-30-skylight-bridge-permissions-cloudkit.json`.

**Open questions**: Screen Sharing first needs local System Settings or MDM approval after the TCC reset. Once GUI access returns, do Photos, Reminders, and Notes prompt correctly? Is the foreground activation workaround necessary once that clean test is complete? The earlier HTTP 422 cannot currently be reproduced because its chore mapping was removed.

**Verification**: All 146 tests in 24 suites passed. Apple accepted notarization submissions `f6e132b6-e18c-4ce7-9dcf-150e5f4ceeaa` for the app archive and `f9a842c8-d5a1-4b12-8146-c2d89aacef58` for the DMG. The installed 1.5.9 app passes strict signature verification and Gatekeeper assessment as Notarized Developer ID.

---

## 2026-07-27 - Skylight Bridge 1.5.8 release

**Release contents**: Version 1.5.8 (build 18) includes recurring-chore duplicate recovery, stale chore due-date correction, content-hash photo deduplication, title-only reminder adoption, sync heartbeats, and shared CloudKit sync-state coordination.

**Verification**: All 146 tests pass. Apple accepted notarization submissions `171f767a-a5bf-46fe-ae3b-c5fa017dae52` for the app archive and `ce0cc019-2a43-42d3-90a8-4031ef1e243c` for the DMG. Both artifacts are stapled and pass Gatekeeper, code-signing, and disk-image verification. GitHub's published DMG digest matches the local SHA-256 `7f251f2beaa209bab82fcc4f0ce4a3e0be43002a9f61609c372633ed2df5a2a1`. Tag `v1.5.8` points to `881271c`, and the signed live appcast matches this repository at `gh-pages` commit `26405f8`.

**Published**: https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.8

## 2026-07-27 - Collapse duplicate recurring chore occurrences

**What changed**: Recurring chore recovery now handles more than one uncompleted EventKit replacement occurrence. It keeps the newest occurrence, rebinds the existing Skylight link to it, removes the extra Apple Reminders copies, and excludes those copies from the planner so they cannot become additional Skylight chores.

**Why**: The earlier recovery required exactly one replacement. Once duplicate copies already existed, it stopped rebinding and every unlinked copy was interpreted as a separate new chore, allowing the duplication to compound.

**Verification**: Added a coordinator regression test with one stale completed occurrence and three uncompleted replacements. The sync retains the newest occurrence, removes the other two, creates no Skylight chores, and leaves one persisted link.

## 2026-07-24 - Multi-device coordination: photo dedup, title-only reminder adoption, heartbeat detection, CloudKit sync state

**What changed**: Five improvements to make the bridge safe when the same Skylight account is used on two Macs or when a mapping is disconnected and reconnected:

1. **Photo deduplication by content hash**: Before uploading, the bridge fetches existing messages in the destination album and parses captions for a `[sb:hash]` tag embedded by a previous upload. A match links the Apple asset to the existing Skylight message instead of creating a duplicate.

2. **Multi-client detection via CloudKit heartbeats**: Each Mac publishes a heartbeat to the private CloudKit database. When another Mac's heartbeat is active (within 10 minutes), the Account section shows an orange warning.

3. **Reminder adoption by title-only fallback**: Secondary adoption pass links remaining unlinked items by title alone, ignoring completion state. Catches the disconnect/reconnect case where one side toggled completion while the mapping was inactive.

4. **CloudKit sync state sharing**: Added SharedSyncState model and CloudSyncStateStore in the shared iOS package. Each Mac publishes sync link records to CloudKit after each sync, and imports other Macs' records before each sync.

5. **Shared package version bumped to 0.1.8**.

**Verification**: All 145 Mac tests pass (12 new). All 14 shared-package tests pass (5 new). `swift build` succeeds in both repos.

**Left off at**: Changes are on `main` and ready to push. No release cut.

**Open questions**: CloudKit stores require ClientHeartbeat and SharedSyncState record types to be deployed to the production schema.

---

## 2026-07-23 - Fix duplicate Apple Reminders and stale due dates for recurring chores

**What changed**: Fixed two bugs in the Chore Chart sync that caused duplicate Apple Reminders and stale due dates for recurring chores. (1) When a recurring Apple Reminder was completed, EventKit generated a new occurrence with a fresh identifier, but the old completed reminder was still returned by fetchReminders. The existing ID-based rebind only fired when the old ID disappeared entirely, so the link stayed on the stale completed reminder and each complete-reopen cycle accumulated a duplicate. Added a second rebind pass that detects when a linked recurring reminder is completed and a matching uncompleted occurrence exists, then moves the link and drops the stale reminder from the planner snapshot. (2) When a recurring chore rolled to a new day without being completed on either side, Skylight advanced the occurrence start date but the Apple reminder kept its old due date. The planner content-change detection only compared title, notes, recurrence, and memberKey, so the due date drift was invisible and the Apple reminder stayed stuck on the previous day. Added a drift check that generates an updateApple action when the Skylight occurrence start date has advanced past the Apple reminder due date to a different calendar day.

**Decisions made**: The stale-completed rebind requires exactly one matching uncompleted occurrence (same title and member) to avoid ambiguity. The due-date drift check only fires in the skylight-to-apple and two-way directions, and only when no content change was already detected, to avoid duplicate update actions.

**Verification**: All 145 tests pass in 24 suites, including three new tests: stale completed recurring reminder rebind, due-date drift roll-forward, and due-date match no-op.

**Left off at**: Both fixes are on `main` and pushed. No release cut.

**Open questions**: None.

---

## 2026-07-22 - Add and stabilize continuous integration

**What changed**: Added automated build and test coverage for the Mac bridge, including authenticated access to its private shared package dependency and a deterministic Sparkle staging step.

**Decisions made**: Kept production signing and release concerns out of CI; the workflow validates source, dependencies, build, and tests only.

**Left off at**: The workflow fixes are on `main`; the live workflow is green.

**Open questions**: The physical iCloud round-trip validation with the iOS companion remains as recorded in the project backlog.

**Verification**: The post-fix GitHub Actions run completed successfully with the expected build and test coverage.

---

## 2026-07-22 - Skylight Bridge 1.5.7: Notes and one-off chore reliability

**What changed**: Released version 1.5.7 (build 17). Apple Notes automation now dereferences account, folder, and note objects before reading their properties, preventing the folder-traversal failure that could stop sync in a large or nested Notes hierarchy. One-off Chore Chart completion and deletion no longer send recurrence-only fields that Skylight rejects with HTTP 422. Removing a Chore Chart mapping now asks whether to keep the Skylight side or the Reminders side and deletes only the other side.

**Decisions made**: The Notes fix applies the same safe dereferencing rule to every Apple Notes object loop, not only the folder lookup that exposed the error. Chore teardown remains explicit and recoverable through the user's keep-side choice.

**Verification**: All 132 tests passed in 23 suites. A read-only live AppleScript probe enumerated and reselected all 51 Notes folders. The universal app and DMG passed Developer ID signing, Apple notarization, stapling, disk-image verification, mounted-app strict signature checks, and Gatekeeper assessment.

The published SHA-256 matched the local DMG (`81641a397fcc39d208eff846979b85b9e45c3fc84ad5e4f6fcc2194bc4b8c3ed`). The signed Sparkle appcast was published to `gh-pages` and matched the live feed byte for byte.

**Left off at**: Version 1.5.7 is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.7. Tag `v1.5.7` points to `8121125`; the appcast mirror is published from `gh-pages` commit `048800b`.

**Open questions**: None.

---

## 2026-07-16 - Skylight Bridge 1.5.6: Two-way chores and list metadata

**What changed**: Released version 1.5.6 (build 16). Chore Chart mappings now remain two-way, including older saved mappings. Linked Apple Reminders and Skylight lists sync title and color changes according to the mapping direction and conflict policy.

Selected-photo names now publish as captions on linked Skylight copies. The README documents the complete Photos, Reminders, Recipe Box, and Chore Chart feature set.

**Decisions made**: The first list-metadata sync records existing titles and colors without relabeling either list. Color clearing remains excluded because Skylight has no documented clear contract. Apple Photos remain unchanged.

**Verification**: All 126 tests passed. The signed local build passed verification. Apple accepted and stapled the universal app and DMG. Both passed Gatekeeper, disk-image, mounted-app, and strict signature checks.

The published SHA-256 matched the local DMG (`37f4c457eaaf0b0423cf2b90a672ebee3876a319bc3e1e86a415833ee797e4b8`). The signed Sparkle appcast was published to `gh-pages`.

**Left off at**: Version 1.5.6 is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.6. Tag `v1.5.6` points to `5333d62`; the appcast mirror is published from `gh-pages` commit `4e9d804`.

**Open questions**: None.

---

## 2026-07-16 - Metadata sync

**What changed**: Commit `f03b347` syncs linked Apple Reminders and Skylight list titles and colors in both directions. Selected-photo names now publish as captions on their bridge-linked Skylight message without changing Apple Photos. The README now separates the published 1.5.5 build from the live next-release work, accurately presents Chore Chart sync as live in the current build, and removes the hidden meal-plan workflow.

**Decisions made**: The first sync records existing list values without relabeling either side. Later conflicts use the selected policy, with Apple as the stable newest-change fallback. Color clearing is excluded because Skylight has no documented clear contract.

**Verification**: `swift test` passed 126 tests in 22 suites. The signed build, strict signature check, and `git diff --check` passed. The final README scan found no meal-plan references.

**Left off at**: Pushed to `main` as `f03b347`; this is not a public release.

**Open questions**: None.

---

## 2026-07-16 - Skylight Bridge 1.5.5: On-device selected-photo names

**What changed**: Released version 1.5.5 (build 15). Selected Photos mappings now generate concise, descriptive names with Apple Intelligence after the picker has returned, so selection is never interrupted. Names appear as they are ready, persist locally with the mapping, and keep saving in the background if the mapping sheet closes first.

**Decisions made**: Image naming runs on device when the required Apple Intelligence image capability is available. The application continues to support macOS 26 for its other features. Generated names do not change Apple Photos or cross-device selected-photo records.

**Verification**: The clean release worktree passed 109 tests in 20 suites. The universal DMG and bundled app passed Developer ID signing, Apple notarization, stapling, disk-image verification, mounted-app signature checks, and Gatekeeper assessment. The published SHA-256 matched the local DMG (`c8ab779144e1b26ba186c3347842d14f878e8009a3e901a9b02e0bbf212a1d25`). The signed Sparkle appcast was published to `gh-pages`, and `/Applications/Skylight Bridge.app` is installed as version 1.5.5 (15) and launched successfully.

**Left off at**: Version 1.5.5 is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.5. Tag `v1.5.5` points to `2d89edb`; the appcast mirror is published from `gh-pages` commit `7dc0b88`.

**Open questions**: None.

---

## 2026-07-16 - Skylight Bridge 1.5.4: CloudKit sharing, crash, and release reliability

**What changed**: Fixed the original iCloud sharing errors by deploying the required CloudKit production schema and adding the `SharedPhotoMapping` record-name query index. The app now recognizes undeployed-production-schema errors and logs a concise recoverable message rather than exposing CloudKit record internals. Bundled and signed Sparkle for local app runs, kept EventKit reminder callbacks on the main actor to address the reported crash, and reordered Configuration to Account, Sync, Activity, then Diagnostics. Released version 1.5.4 (build 14), including an accurate README badge/install command and signed Sparkle appcast entry.

**Decisions made**: Production CloudKit failures are handled as recoverable sharing failures while preserving local work. The public release is the Developer ID-signed, notarized, stapled DMG; the appcast names the release-specific fixes and retains a generic default for future releases. Only `/Applications/Skylight Bridge.app` remains installed locally after release verification.

**Verification**: 106 tests in 19 suites passed. The CloudKit production schema and query indexes were verified in the Apple Developer dashboard. The 1.5.4 app and DMG passed nested-signature checks, notarization, stapling, Gatekeeper assessment, disk-image verification, and published SHA-256 comparison. The signed appcast was published to `gh-pages`, and the installed 1.5.4 (14) app launched successfully.

**Left off at**: Version 1.5.4 is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.4. Tag `v1.5.4` points to `352ffe6`; the appcast mirror is committed on `main` as `0f784ff`.

**Open questions**: None.

---

## 2026-07-15 - Skylight Bridge 1.5.1 release

**What changed**: Published version 1.5.1 (11), including the CloudKit app-identity signing correction, guided Chore Chart setup, refined menu-bar and sidebar navigation, temporarily hidden Meals workflow, and clearer first-run onboarding.

**Verification**: The Mac test suite passed 103 tests. The universal DMG was Developer ID signed, Apple-notarized, stapled, and accepted by Gatekeeper. `hdiutil verify` passed; the mounted app passed strict code-signature and Gatekeeper checks; and GitHub's downloaded SHA-256 file exactly matches the local DMG checksum (`724cef9130869804a30a01bf1cf6d6897e7cb92640ca79e6f6687d94928b5340`).

**Left off at**: Version 1.5.1 is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.1. The tag points to `12cec5b` and includes the notarized DMG plus its SHA-256 checksum.

**Open questions**: The physical iPhone CloudKit add, offline-edit, and removal round trip remains pending.

---

## 2026-07-15 - Skylight Bridge 1.5.0 release

**What changed**: Published the CloudKit-enabled Mac release as 1.5.0 (10). The regenerated Developer ID profile authorizes `com.oliverames.SkylightBridge` and the shared `iCloud.com.oliverames.SkylightBridge` container, and the release script embeds it before signing.

**Verification**: The release DMG and app are notarized, stapled, accepted by Gatekeeper, and the mounted DMG passed signature verification. A fresh launch of the released app stayed running. The Mac test suite passed 103 tests, the companion shared package passed 11 tests, and a signed generic iOS build verified the same team, app identifier, and CloudKit container. GitHub's downloaded SHA-256 file matches the local DMG checksum.

**Left off at**: Version 1.5.0 is published privately at https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.0. The tag points to `dfc1b0d` and includes the notarized DMG plus its SHA-256 checksum.

**Open questions**: The physical iPhone CloudKit add, offline-edit, and removal round trip remains pending. The paired iPhone must be unlocked, connected, and placed in Developer Mode before it can accept the signed build.

---

## 2026-07-15 - Release validation and CloudKit provisioning gate

**What changed**: Prepared the next Mac release as 1.5.0 (10) and corrected the release script's universal build invocation. The shared companion package deliberately suppresses warnings, which conflicted with the script's global warnings-as-errors flag under Swift 6.2. The script now builds both architectures without that contradictory option. It also requires a readable Developer ID provisioning profile, verifies that the profile authorizes `com.oliverames.SkylightBridge` and `iCloud.com.oliverames.SkylightBridge`, and embeds it at `Contents/embedded.provisionprofile` before signing.

**Verification**: The unprovisioned 1.5.0 app ZIP and DMG were both accepted by Apple's notary service, stapled, and accepted by Gatekeeper. The DMG passed `hdiutil verify`; its mounted app passed strict signature and Gatekeeper checks; and the SHA-256 checksum was `3fea2cee1ae49018d241ac927c4d39f0068d6913d770811a28b8145cc8f8263a`. `swift test` passed 103 Mac tests in 17 suites and the companion's shared SwiftPM test run passed 11 tests. The actual release artifact then reproduced the earlier launch failure outside Xcode: launchd reported security-policy error 163 before the process began. It has CloudKit entitlements but no embedded profile, which Apple documents as required for Developer ID apps using CloudKit.

**Left off at**: Do not publish the unprovisioned 1.5.0 DMG. In the Apple Developer account, enable and assign `iCloud.com.oliverames.SkylightBridge` to both `com.oliverames.SkylightBridge` and `com.oliverames.SkylightBridge.iOS`, then create and install the matching Developer ID macOS profile and iOS development/distribution profiles. Re-run the Mac release script with `DEVELOPER_ID_PROFILE` after the profile is installed. The physical iPhone 17 Pro Max is paired but locked, has Developer Mode disabled, and cannot accept the requested CloudKit test. Xcode also has no signed-in developer account, so automatic iOS provisioning fails before build.

**Open questions**: None in code. The remaining work is Apple Developer portal and on-device authorization, then the physical add, offline-preference-edit, and confirmed-removal round trip.

---

## 2026-07-15 - Meal resync, two-way chores, and iPhone iCloud reconciliation

**What changed**: Completed three related workstreams across this repo and `/Users/oliverames/Developer/Projects/skylight-bridge-ios`. `6a570e2` stopped treating the fallback meal category as an Apple Intelligence classification and added a one-time per-frame repair for older cached fallback assignments. `b6a8891` added first-time Chore Chart setup, per-person and Up for Grabs Apple Reminders lists, one-way or two-way content reconciliation, recurrence conversion, assignee moves, and occurrence-aware completion. `db384c6` added the Mac side of the native iPhone companion through the shared CloudKit package and entitlement for `iCloud.com.oliverames.SkylightBridge`. Individual-photo mappings now reconcile portable asset identifiers, destination, enabled state, JPEG conversion, location-removal policy, selected frame, preview mode, and cadence. `943848e` imports remote removal records before Mac publication and republishes merged offline preferences. `3107391` consumes companion package `0.1.7` and publishes an add only for a genuinely new local selection or initial CloudKit seeding, so passive Mac updates cannot resurrect a photo removed elsewhere. `0f6f46b` replaces the legacy packaging input with the Relay Ribbon Icon Composer document, builds its Liquid Glass catalog and ICNS into the Mac app, and retains all three original 1024 x 1024 SVG layers in `Design/AppIcon`.

**Decisions made**: A cached recipe category now means the model actually classified it; fallback assignments remain eligible for a later retrofit. Chore Chart people are configured on Skylight first, then mapped to explicit Reminders lists. Recurring completion represents today's occurrence rather than the whole series, and recurrence details that EventKit cannot faithfully write back remain protected from narrowing. Cloud sharing is deliberately limited to settings and individual-photo mappings that iOS can manage; album, Favorites, folder, standard Reminders, Chores, Recipes, and Meals mappings stay on the Mac. The cross-device photo set uses independent observed add/remove records so concurrent additions survive and explicit removals win over stale selections. A deliberate user selection can re-add a removed photo, while passive publication preserves the remote removal.

**Verification**: `swift test` passed 103 tests in 17 suites after the icon change. The opt-in Chore Chart read test passed against 9 categories, 3 grouped chores, and 10 dated occurrences. The live recurring lifecycle passed create, update, complete, reopen, delete, and final no-residue polling. The built Mac bundle is validly signed, declares `CFBundleIconName` as `AppIcon`, and contains `Assets.car` plus 11 `AppIcon` renditions up to 1024 x 1024. The companion passed 11 SwiftPM tests and 11 Xcode Simulator tests; its icon-enabled build installed and launched as process 25641 without the prior CloudKit trap.

**Left off at**: Mac feature implementation is pushed through `0f6f46b`; companion implementation is pushed through `07c2419`, with `0.1.7` still the latest release tag at `a30439f`. The README now distinguishes the published Mac 1.4.0 release from the tested post-release Chore Chart, CloudKit reconciliation, and Relay Ribbon work, and links the companion repo with its physical-device provisioning gate. The Apple Note `💻 Tech/🌉 Skylight Bridge` was refreshed to match the live implementation. The remaining end-to-end check is on physical signed devices.

**Open questions**: **NEW**: The Mac changes after the existing 1.4.0 release have not been released, and the locally built bundle still hits launchd error 163 when opened outside Xcode even though compilation, signing validation, and icon-catalog validation pass. Complete normal provisioning and notarization before distribution. Physical-device CloudKit synchronization requires the shared container to be enabled for both app IDs with regenerated profiles, followed by add, offline-edit, and explicit-removal tests between a Mac and signed-in iPhone. A recipe manually placed into the first Skylight category can be indistinguishable from an old fallback assignment during the one-time repair; recipes in other categories are unaffected.

---

## 2026-07-14 (late night) - 1.4.0: margins, resizable window, onboarding, donation reminders

**What changed**: Four items from Oliver's screenshot review (TinyStart vs Skylight Bridge, green margin marks) and feature requests. (1) **Margins**: all eight grouped-settings pages now share a `groupedPageLayout()` modifier (Components.swift). First pass used a centered 840pt column, which Oliver flagged as too-wide side margins in wide windows; the final version mirrors TinyStart — no max-width column, cards stretch with the window behind a fixed `contentMargins(.horizontal, 24)` gutter. (2) **Resizing**: the main window's rigid 1,040×700 minimum dropped to 720×520 with `.windowResizability(.contentMinSize)` and a 1,040×700 `defaultSize`; verified live that the window now clamps at 720×572 when dragged smaller. (3) **Onboarding**: first-run `OnboardingView` sheet (hero icon, three feature rows, setup callout, Get Started → Account) modeled on Ping Warden's WelcomeView; `hasCompletedOnboarding` in UserDefaults; interactive dismiss disabled so the choice is explicit. (4) **Donation reminders**: `SupportPromptPolicy` (pure, tested) ports Ping Warden's policy with sync-count milestones — the lifetime applied-change counter (UserDefaults, incremented after every live sync) crossing 50 / 500 / 2,000 / 10,000 raises `DonationPromptView` (buymeacoffee.com/oliverames), subject to a 30-day prompt cooldown, 180-day post-donation grace, and a permanent "Don't Ask Again"; prompts never fire while disconnected, syncing, or during onboarding. A manual "Donate…" row lives in Diagnostics → Support.

**Decisions made**: Onboarding/donation state lives in UserDefaults, not the sealed config — it is advisory UI state, not sync configuration. Milestones count applied changes (the "tasks synchronized" number Oliver asked for) rather than sessions. The donation sheet reuses Ping Warden's exact interaction contract (Support / Maybe Later / Don't Ask Again) for consistency across the apps.

**Verification**: 80 tests pass (6 new SupportPromptPolicy tests covering milestones, cooldowns, and hard blocks). Live: onboarding sheet appeared on first launch of the new build and Get Started landed on Account with the flag persisted; margins visually match the TinyStart reference; window resize clamps at 720×572.

**HIG pass (same release)**: Oliver flagged two un-Mac patterns against the HIG. (a) The mapping editors' segmented controls rendered iOS-style (accent-filled selected pill); grouped settings forms should use pop-up buttons, so the `.segmented` overrides were removed and the forms' native pop-ups now match every neighboring row. (b) Mapping rows carried four trailing controls (status badge + bordered Edit + switch + tiny ellipsis); redundant state text next to a switch and a persistent Edit pill are not macOS list idioms. Rows now follow the System Settings/Wi-Fi grammar: the switch carries the state (with an accessibilityValue for VoiceOver) and a single "ellipsis.circle" menu holds Edit…/Delete…, plus a right-click context menu. (c) The capsule status chip itself ("● Granted", "● Connected") was a web-dashboard idiom that read as a disabled button next to real ones; StatusBadge's tonal states now render as a small colored SF symbol plus secondary text (checkmark.circle.fill green / exclamationmark.triangle.fill orange), matching the Account page's access rows, while the neutral capsule remains only for tag-like uses (Activity's "Preview" chip and entry counts).

**Left off at**: Released as 1.4.0 (9).

**Open questions**: None.

---

## 2026-07-14 (night) - 1.3.0: on-device recipe classification, title emoji, shared albums

**What changed**: Three features. (1) **Automatic meal categories now classify each recipe on device.** New `RecipeIntelligence` actor (FoundationModels, `LanguageModelSession` + `@Generable` guided generation) picks the best frame category per recipe; previously "Automatic" filed everything under `categories.first` (all 52 recipes were "Breakfast"). `resolveRecipeCategoryContext` replaces the single-ID resolution for recipes (meals keep the old behavior); `classifyRecipePush` runs at push time and caches its result on the record (`autoCategoryID`/`autoEmoji`, decoded per-field per the repo rule), so the model runs at most once per recipe. A one-time retrofit in `reconcileLinkedRecipes` classifies existing unchanged recipes; unavailable Apple Intelligence falls back to the old behavior plus a one-time Activity note. The category picker returned to the Recipes editor (hidden earlier today — wrong, recipes do send `meal_category_id`) with a footer explaining Automatic. (2) **Every recipe gets a title emoji**: the same classification picks one emoji for titles that lack one; it decorates the Skylight summary only (notes untouched). Title matching for recipe adoption and meal-sitting lookup is now emoji-insensitive (`recipeTitleKey`) so "Tacos" still matches "🌮 Tacos". (3) **Shared albums in the photo picker**: `ApplePhotoLibrary.collections()` now fetches `.albumCloudShared` (new `.sharedAlbum` kind, "(Shared)" suffix in the picker). Photo render options already allow network access, so shared assets download on demand.

**Decisions made**: Classification is cached-on-record, never re-run for unchanged recipes; a classifier failure never blocks a sync (falls back to first category / no emoji). Emoji decorates only the pushed summary so user notes are never rewritten for cosmetics. The classifier is injected (`RecipeClassifying` protocol) so tests use a deterministic stub.

**Verification**: 74 tests pass (new: automatic-classification push, one-time retrofit idempotence, no double-decoration of emoji titles). Live: retrofit sync applied 52 changes; read-only API probe confirms 0 of 52 recipes lack an emoji; state shows a sensible spread (16 Breakfast / 11 Lunch / 14 Dinner / 11 Snack); the following sync applied 0 changes. Shared albums verified at the data level: this Mac's Photos library has zero `albumCloudShared` collections (Photos.sqlite kind 1505), so the picker correctly has none to show until Photos → iCloud → Shared Albums syncs some.

**Left off at**: Released as 1.3.0 (8).

**Open questions**: The Oatmeal recipe drew 🍌 (its ingredients include banana) — classification quirks like this are one-off and can be fixed by editing the note title. Shared Albums appear to be disabled in Photos on this Mac; enable them for the picker entries to appear.

---

## 2026-07-14 (evening) - 1.2.4: reminder-churn root cause, album-delete safety, UX sweep, data cleanup

**What changed**: (1) **Reminder sync churn fixed.** The scheduled sync had been applying the same ~9 reminder updates every 10 minutes forever. Root cause: the sealed state store encodes dates as Unix seconds (`.secondsSince1970`) while `Date` stores seconds since 2001; the 978,307,200-second epoch shift loses sub-microsecond mantissa bits, so ~25% of persisted baselines decode fractionally below the live EventKit date (measured drift: exactly ±1.19e-07 s via a temporary planner-input dump). The planner's strict `>` then saw a phantom "Apple changed" on those items every cycle. `ReminderSyncPlanner` now uses `Date.isMeaningfullyAfter(_:)` (1 ms tolerance); no real edit is sub-millisecond. Verified live: post-fix sync logs "Sync complete: 0 changes applied." (2) **Album cleanup no longer trusts a failed list call.** `purgePhotoMapping` treated a `listAllAlbumMessageIDs` failure as an empty album (`try? ... ?? []`), which could delete a bridge-created album still holding user-added photos on a network blip; a failed listing now skips deletion and keeps the record. (3) **All four persisted record structs** (`PhotoSyncRecord`, `ReminderSyncRecord`, `NoteSyncRecord`, `PhotoAlbumRecord`) now decode per-field with `decodeIfPresent`, completing the repo rule established after the 1.2.3 outage — previously a new required field on any record element would have stranded old state files again. (4) **UX sweep** from a structured review: sign-in failures now show inline on Account (new `connectionError`); denied Photos/Reminders access shows "Open System Settings…" deep links instead of a dead "Allow Access" button; raw enum values ("Notdetermined", "Writeonly") replaced with friendly labels; Sync settings autosave (Save button removed — Hide Dock icon previously looked broken until Save, and quit discarded changes); adding a mapping while signed out now records a warning instead of silently skipping the promised auto-sync; sync buttons (toolbar, menu bar, ⌘⇧R) disable when signed out with an explaining tooltip; the meal-category picker no longer appears in the Recipes editor; the Overview connection row shows the frame name instead of the global status channel; Overview shows "(paused)" for disabled Recipes/Meals and counts Reminders in "mappings"; the menu bar shows last-sync time and switches to a warning glyph with an error line after a failed sync. (5) **Docs** aligned on "Preview mode" (was "Dry Run" in README/spec but never in the UI) and updated for autosave and the menu bar states.

**Data cleanup (user request)**: The "Family ⇄ To-Do List" 0-item mystery is resolved: the mapping is healthy; the Apple "Family" list is genuinely empty (verified via EventKit-backed sync records; AppleScript can't see that account's lists). The Skylight recipe duplicates were two different pizza recipes sharing the title "Pizza"; renamed the English-muffin one to "English Muffin Pizzas" (Apple note p10200) and verified the rename synced — zero duplicate recipe names on the frame now. The 🥘 Food folder still mixes 23 quick meal names with 29 real recipes; left as-is pending Oliver's preference (Selected notes vs. dedicated folder).

**Decisions made**: Sub-millisecond timestamp deltas are never real edits; tolerance lives in the planner, not the store, so existing state files stay valid. Failed remote listings never authorize deletions. Sync settings follow the same autosave model as mapping toggles.

**Verification**: 71 tests pass (new: lossy-baseline tolerance test, missing-field record decode test). Live: rebuilt, relaunched, manual sync converged to 0 changes; recipe rename pushed ("1 change applied") and confirmed via read-only API probe; duplicate-name count on Skylight is zero.

**Left off at**: Released as 1.2.4 (7).

**Open questions**: Whether to split the 23 quick-meal notes out of the 🥘 Food recipe mapping (Selected notes or a second folder). `ReminderSyncRecord.tombstonedAt` is written nowhere and read nowhere — candidate for removal or completion.

---

## 2026-07-14 (later) - Sync-state decode fix, Notes TCC status, Hide Dock icon

**What changed**: Three fixes in two commits (`8eec0c2`, `21d1773`). (1) Every scheduled sync was failing with "The data couldn't be read because it is missing" — the `photoAlbums` field added to `SyncState` in 1.2.3 made older `sync-state.json` files undecodable, because Swift's synthesized `init(from:)` does not fall back to property default values when a key is absent (verified empirically this session: decoding `{}` into a struct whose only property has an `= []` default throws `keyNotFound`). `SyncState` now decodes all sections with `decodeIfPresent`, and the same hardening went into `AppConfiguration`, whose `try? ... ?? .empty` load would otherwise silently wipe all settings the next time a field is added. (2) Decoding errors are no longer flattened to the generic sentence: the API client wraps them in `SkylightAPIError.decodingFailed` with endpoint and coding path, and `AppStore` formats local `DecodingError`s via a new `fieldLevelDescription` helper. (3) The Account/Recipes access rows showed Notes as "not requested" on every launch because the app never queried TCC; `refreshSources` now probes `AEDeterminePermissionToAutomateTarget` (declared in `AE.framework/Headers/AppleEvents.h`, macOS 10.14+; confirmed in the local SDK this session) with a UserDefaults fallback for when Notes isn't running, since the probe needs a live target process. New "Hide Dock icon" toggle in Sync settings switches the activation policy to accessory, mirrored to UserDefaults so the app delegate applies it at launch without a Dock-icon flash.

**Decisions made**: All persisted Codable structs in this app should decode with explicit `decodeIfPresent` per field; property defaults are not decode defaults. The Dock preference lives in the sealed configuration as the source of truth, with the UserDefaults key acting only as a launch-time mirror. Hide Dock icon was left enabled after verification since that was the request's intent.

**Verification**: 69 tests pass (four new regression tests covering legacy `SyncState` and `AppConfiguration` decoding). The failing sync was reproduced live via the improved error message (named `photoAlbums` at root), and after the fix a manual sync completed with "Sync complete: 9 changes applied." The Notes row shows Authorized on a cold launch. The Dock icon was verified hidden via the real toggle plus save, and stays hidden across a relaunch.

**Left off at**: Both commits pushed to `main`. Version string is still 1.2.3 (6); these fixes are unreleased — cut 1.2.4 when convenient. Verification left a second main window open in the running app (cosmetic only).

**Open questions**: None.

---

## 2026-07-14 - Skylight Bridge 1.2.3: album cleanup, recipe-parse fixes, menu bar pulse, backend verification

**What changed**: Six items from live testing. (1) Deleting a photo mapping now also deletes the Skylight album the bridge created for it, once that album is empty — tracked via a new `PhotoAlbumRecord` in SyncState, recorded only for bridge-created albums, and gated on `listAllAlbumMessageIDs` being empty so a bridge album holding user-added photos is left alone. (2) The RecipeParser now splits bullet-packed metadata lines ("Source: AllRecipes • Servings: 8" → Servings captured, source kept as text since it is not a URL), strips U+FFFC attachment placeholders that were becoming bogus steps, and only routes a value into the Skylight url field when it looks like a URL. (3) Two-way verbiage updated across Reminders and Recipes rows/editors to describe field-level merge accurately ("merges edits, newest change wins on a clash") instead of implying whole-record newest-wins, and the reminder conflict picker now shows only for two-way (not one-way Skylight→Apple). (4) The menu bar icon pulses via `.symbolEffect(.pulse, isActive: store.isSyncing)` while syncing. (5) Read-only backend check against the live Skylight API (temporary opt-in test, not committed).

**Backend verification (read-only, live API)**: Frame ames-family-5173. "Selected Photos" album = 11 photos (confirms the selected-photos fix landed end to end). Reminder lists: "Grocery List" 5 items, "Dad's To-dos" 28 items (16 completed) — both new mappings synced. "To-Do List" showed 0 items, so the Family mapping pushed nothing (the Apple Family list is likely empty or that sync had not run). 52 recipes exist (the Food folder mixes meal names and real recipes, with some duplicates); every recipe reports 0 structured ingredients while the description carries the full recipe, confirming Skylight does not persist the structured ingredient array.

**Decisions made**: Album deletion is bridge-created + empty only, never a pre-existing or user-populated album. Kept sending the structured ingredients field (harmless) but rely on the description for display since the backend ignores it. Did not add heuristic sub-header detection for ingredient groups (e.g. "Dry Mix") to avoid round-trip risk; the description already reads as a recipe.

**Verification**: 65 tests pass (added parser tests for bullet-split, attachment stripping, URL capture; album-delete tests for empty-delete and non-empty-keep). Rebuilt and relaunched. Bumped to 1.2.3 (6).

**Left off at**: 1.2.3 (6) published (private) at https://github.com/oliverames/skylight-bridge/releases/tag/v1.2.3; notarized DMG and SHA-256 checksum, Gatekeeper accepts both, published checksum matches local. Tag points at `aeebb93`.

**Open questions**: The "Family ⇄ To-Do List" mapping shows 0 items on Skylight — worth confirming the Apple Family list has reminders. The Food recipe folder mixes quick meal names with real recipes and has duplicates on Skylight; the user may want to curate the folder or use "Selected notes".

---

## 2026-07-14 - Skylight Bridge 1.2.2: fix unclickable inline Edit button

**What changed**: The Edit button on mapping rows stopped responding after the 1.1.0 grouped-settings redesign. Root cause: an inline SwiftUI `Button` sharing a `Form`/`List` row with other controls needs an explicit button style, or macOS routes the click to the row and the button never fires; the pre-redesign rows had `.buttonStyle(.glass)` and the rewrite dropped it. Added `.buttonStyle(.bordered)` to the Edit button in the shared `MappingRow` (Photos, Reminders) and to the Notes selection row. The Toggle and overflow Menu were unaffected because they install their own gesture recognizers.

**Decisions made**: Used `.bordered` (not `.borderless`) so the button keeps its visible pill; any explicit style restores independent hit-testing. Fix is centralized in `MappingRow` so it covers Photos and Reminders at once.

**Verification**: 61 tests pass (UI-only change). Rebuilt and relaunched; a mapping editor sheet opened in the running build. Separately confirmed the selected-photos fix end to end: the Activity log shows "Photos: 12 changes applied" (11 selected photos + first-time Skylight album creation) inside "Sync complete: 15 changes applied", and earlier entries confirm cleanup-on-delete ("Removed 2 photos from Skylight for 'Our House'", "Removed 2 items from Skylight for 'Money'"). Bumped to 1.2.2 (5).

**Left off at**: 1.2.2 (5) published (private) at https://github.com/oliverames/skylight-bridge/releases/tag/v1.2.2 with the notarized DMG and SHA-256 checksum; Gatekeeper accepts both and the published checksum matches local. Tag points at `db68dd6`.

**Open questions**: None.

---

## 2026-07-14 - Skylight Bridge 1.2.1: settings consolidated into the main window

**What changed**: Sign-in was hard to find because Account, Sync, and Diagnostics lived in a separate Settings/Preferences scene. Since Skylight Bridge is a menu-bar-first app, those three now live in the main window's sidebar under a "Configuration" group, and the separate `Settings` scene is gone. `AccountView`/`SyncSettingsView`/`DiagnosticsView` were extracted from the old `SettingsView` into `ConfigurationViews.swift`. The standard Settings shortcut (⌘,), the menu bar "Account & Settings…" item, and the Overview "Sign In…" button all navigate to the in-window Account section and bring the main window forward. The sign-in section leads with a clear header and a Sign In / Reconnect button.

**Decisions made**: Kept ⌘, working by replacing the app-settings command group with one that opens the main window on Account, rather than dropping the shortcut. The sidebar uses two `List` sections (sources, then configuration) for visual grouping. Account/Sync/Diagnostics forms are verbatim extractions of the previously shipped Settings tabs, so behavior is unchanged, only their location.

**Verification**: 61 tests pass normally, under AddressSanitizer, and under ThreadSanitizer (no logic changed, so coverage is unchanged). `./script/build_and_run.sh --verify` produced a signed bundle that launched cleanly; a screenshot confirmed the new "Configuration" sidebar group with Account, Sync, and Diagnostics. Bumped to 1.2.1 (4).

**Left off at**: 1.2.1 (4) published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.2.1 with the notarized DMG and SHA-256 checksum. The tag points at `6e8c0c4`. Gatekeeper accepts the app and DMG, and the published checksum matches the local digest.

**Open questions**: None.

---

## 2026-07-14 - Skylight Bridge 1.2.0: cleanup flows, field-level merge, auto-sync

**What changed**: Eight issues from testing the 1.1.0 build. (1) The "Selected Photos" picker now passes `photoLibrary: .shared()` so `PhotosPickerItem.itemIdentifier` resolves instead of returning nil and reporting zero selected. (2) Deleting a photo mapping now purges the Skylight copies it created, since Apple Photos is never touched. (3) Deleting a reminder mapping opens a confirmation dialog asking whether to also remove the synced items from Skylight, from Apple Reminders, or from neither. (4) Two-way reminder merge became field-aware: separate additions on both sides are preserved, and simultaneous edits merge title and completion independently, using the conflict policy only when the same field changed on both sides (new `.merge` action; last-synced title/completion baseline stored on the record). (5) Adding, editing, or enabling a mapping now triggers an automatic sync (a preview under Dry Run) so changes land in Activity immediately. Confirmed already-correct and left as-is: Skylight albums are real (API evidence), RAW/ProRAW already convert to sRGB JPEG before upload, and recipes pulled from Skylight already write formatted Apple Notes.

**Decisions made**: Photo-mapping deletion always removes the Skylight copies (Apple Photos is the untouched source), while reminder-mapping deletion asks per side because reminders can live on both. Field-level merge carries the merged value in the action and writes both sides only when the merge differs from each; when it coincides with one side it reuses the existing one-way update. Cleanup is best-effort per item (an already-deleted item does not abort the sweep) and requires a Skylight connection. Auto-sync is wired to mapping save and enable toggles specifically, not to Settings changes like interval or Dry Run.

**Verification**: 61 tests pass normally, under AddressSanitizer, and under ThreadSanitizer, including new coverage for field-level merge (disjoint edits, same-field conflict, preserved additions) and both cleanup paths. Bumped to 1.2.0 (3).

**Left off at**: 1.2.0 (3) published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.2.0 with the notarized DMG and SHA-256 checksum. The tag points at `fff269a`. The notarized app and DMG both pass Gatekeeper assessment and the published checksum matches the local digest.

**Open questions**: None.

---

## 2026-07-14 - Skylight Bridge 1.1.0: two-way sync and grouped-settings redesign

**What changed**: Reminders mappings now link lists symmetrically: either side can be an existing list or created new, including creating a fresh Apple Reminders list from the app to adopt a list that already lives on the Skylight. The first sync into an existing list links items whose title and completion state match instead of duplicating them. Recipes gained an optional two-way mode with a per-selection conflict policy: new Skylight recipes become notes, remote edits rewrite unchanged notes, both-changed conflicts resolve by newest/Apple/Skylight, and recipes deleted on Skylight move their notes to Recently Deleted. The recipe parser now accepts title-only and description-only notes so Skylight-authored recipes round-trip, and pushed recipe descriptions use the same grammar the parser reads. Photos and Meals stay push-only. The whole interface moved from Liquid Glass cards to standard grouped-settings forms (flat cards, bordered buttons, capsule badges, Tip footers) modeled on TinyStart; Liquid Glass remains only in system chrome.

**Decisions made**: Meal plans stay one-way because rewriting freeform meal notes from parsed data would risk user text. Recipe-note retirement uses the Notes trash (recoverable for 30 days) rather than hard deletion. Adoption matching is title+completion, case- and whitespace-insensitive, deterministic by identifier order. Conflict ties keep Apple as the source of truth. Notes the bridge writes follow the household Apple Notes formatting conventions (h1 title, h2 sections, native lists, spacer after each list, bare URLs) with a per-selection "Format notes automatically" toggle; the title-emoji habit was deliberately skipped because it would break title matching with Skylight. Notes with attachments are never rewritten.

**Verification**: All 54 tests pass normally, under AddressSanitizer, and under ThreadSanitizer. `./script/build_and_run.sh --verify` produced a signed bundle that launched cleanly; the running app performed a live sync against the real account and applied zero changes (no regressions or duplicates against 1.0 sync state). Screenshots confirmed the grouped-settings layout on Overview and Reminders. The formatted note HTML was round-tripped through the live Notes app and re-parsed without drift. A coordinator test caught and fixed a resurrection bug where a note trashed by a Skylight-side deletion would have been re-pushed as a new recipe in the same run. The notarized app and DMG both pass Gatekeeper assessment, and the published release checksum matches the local SHA-256 digest.

**Left off at**: Version 1.1.0 (2) is published at https://github.com/oliverames/skylight-bridge/releases/tag/v1.1.0 with the notarized DMG and SHA-256 checksum. The tag points at `c714a5f`. Notarization credentials were sourced just-in-time from the 1Password Development vault ("App Store Connect AuthKey (.p8)", "App Store Connect API Key", "App Store Connect Issuer ID").

**Open questions**: None.

---

## 2026-07-13 - Skylight Bridge 1.0 release

**What changed**: Completed the native macOS 26 and 27 application with selective Apple Photos, Reminders, Recipes, and Meals configuration; Liquid Glass layouts; Keychain-backed authentication; signed local state; discovered Skylight API diagnostics; and Developer ID release packaging.

**Decisions made**: Apple remains the source of truth. Photos mirror only selected albums, Favorites, or hand-picked assets. Reminders sync only selected lists or items to Skylight lists. The app intentionally provides no calendar, task, chore, or rewards synchronization interface.

**Verification**: All 39 tests passed normally, under AddressSanitizer, under ThreadSanitizer, and with the authenticated live API lifecycle enabled. The Skylight portal showed exactly two items in Money and two photos from Our House; a repeated live sync applied zero changes. Apple accepted and stapled the signed app and DMG, Gatekeeper accepted both, the mounted DMG app revalidated, and the private GitHub release assets matched their local SHA-256 digests.

**Left off at**: Version 1.0.0 is published privately at https://github.com/oliverames/skylight-bridge/releases/tag/v1.0.0. The release tag points to `a6c66ac`, and `main` includes the follow-up portable-checksum fix at `5618e8a`.

**Open questions**: None.

---
