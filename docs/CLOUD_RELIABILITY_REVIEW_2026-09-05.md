# Cloud reliability review, September 5, 2026

Author: Oliver Ames

## Task list

- [x] Inspect the current Mac integration and pinned CloudKit package for concrete reliability gaps.
- [x] Challenge findings against existing safeguards and Apple's current CloudKit guidance.
- [x] Record prioritized improvements, implementation scope, and deployment decisions.

## Scope

Review starts at `983aa28`, after the verified 1.6.6 release. It covers shared preferences, selected-photo mappings, offline intent, conflict recovery, account boundaries, retry scheduling, and the disabled multi-Mac coordination feature. Production CloudKit data and schemas are not changed during this review.

## Recommendation

Prioritize automatic recovery and truthful cloud status, then strengthen account isolation and preference conflict handling across Mac and iPhone. Evaluate Apple's sync engine after these corrections. Replacing the transport alone would not fix the data model or local save races.

This is an assessment of additional work following the 1.6.6 release. The improvements below are recommendations, not shipped changes. The Mac integration was inspected at `983aa28`, and the shared package and iPhone implementation were inspected at the Mac's pinned version, 0.1.8 (`448ee088`). Findings about that iPhone snapshot do not establish the state of a newer iPhone release.

## Confirmed findings

### 1. Cloud recovery can require opening the app

If the first preference refresh fails, `hasLoadedSharediCloudState` remains false. Ordinary preference saves then omit publication. The regular Skylight scheduler does not refresh shared preferences or selected photos. Automatic refresh occurs at launch and when the window becomes active.

Evidence: `Sources/SkylightBridge/Services/SharedCloudBridge.swift:42-79`, `Sources/SkylightBridge/Stores/AppStore.swift:315,362-364,1218-1339`, and `Sources/SkylightBridge/Views/ContentView.swift:30-35`.

A selected-photo edit can trigger a separate publish, so this does not strand every cloud operation. However, a Mac left in the menu bar can remain stale after a transient failure.

**Proposed change:** Add one serialized cloud worker that retries recoverable failures, refreshes periodically while the app runs, and resumes after wake, network recovery, or account availability. Coalesce duplicate requests. Honor Apple's requested delay for throttling and service outages, with increasing delays between other transient failures. Configuration and schema errors should remain actionable errors rather than trigger rapid retries. Apple documents the server delay through [retryAfterSeconds](https://developer.apple.com/documentation/cloudkit/ckerror/retryafterseconds?changes=l_8).

Keep retry delays outside the existing operation gate. Do not call a refresh that waits for `isSyncing` to clear from inside an active Skylight sync.

### 2. Pending removals can be reported as synchronized

Mapping retirement catches a failed cloud write and returns no failure result. The enclosing refresh can then display "Shared preferences and selected photos are up to date with iCloud." Publication can also return true while retirement remains pending.

Evidence: `Sources/SkylightBridge/Services/SharedCloudBridge.swift:76-77,89-95,393-425`.

The removal intent survives failure and relaunch, and the retired mapping cannot silently reimport. The defect concerns reporting and recovery, not loss of that intent.

**Proposed change:** Aggregate pending work before reporting success. Show the last successful iCloud synchronization, pending changes, and a clear retry state independently of Skylight's own sync result. A successful preference write must not clear an unresolved photo-removal failure.

### 3. Local cloud state is not bound to an iCloud account

The Mac uses global preference and mapping cache keys. Pending photo changes belong to the local configuration without an iCloud owner. The cloud stores address the current account's private database. A search across Mac `Sources` and `Tests`, and the pinned shared package, found no account-change observer or user-record identity check.

Evidence: `Sources/SkylightBridge/Services/SharedCloudBridge.swift:921-958`, `Sources/SkylightBridge/Models/AppConfiguration.swift:248-253`, and pinned `Shared/CloudPreferencesStore.swift:66-77,92-102`.

**Risk:** Changing Apple Accounts within the same macOS user account could carry cached preferences or pending changes into the new account. No live account switch or cross-account upload was performed or observed.

**Proposed change:** Bind caches and pending operations to the verified cloud account. Retain the previous account's local data and suspend its publication after an account change. Switching accounts must not silently migrate that data. Apple's [CKSyncEngine account handling](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9?language=objc) explicitly leaves local persistence changes to the app.

### 4. Equal-time preference conflicts depend on merge order

Each preference has its own modification time, but all fields use one document-wide writer ID to resolve equal timestamps. An unrelated edit changes that ID. Identical input edits can consequently produce different final values.

Evidence: pinned `Shared/SharedPreferences.swift:82-112,115-133`.

**Executed reproduction:** Using the actual pinned Swift model, let `a` set Preview false at time 10, `b` set Preview true at time 10, and `z` change the frame at time 20. `(a.merging(z)).merging(b)` produces false. `a.merging(z.merging(b))` produces true. Two independent source reviews confirmed the cause. This scenario requires equal timestamps for conflicting values.

**Proposed change:** Preserve modification time and writer identity for each field. Persist the original local edit metadata before publication, so retry and relaunch do not turn an old edit into a new one. Test all merge orders and repeated delivery. The shared package needs a compatibility strategy because older clients can discard new metadata when they rewrite the payload.

### 5. An older iPhone save response can erase a newer edit

The pinned iPhone implementation starts independent publication tasks. After an asynchronous save completes, it replaces the current preferences with the returned snapshot and persists it. A user can edit a setting during that wait. If the newer request then fails, the older response has already replaced the newer local value.

Evidence: pinned `SkylightBridgeiOS/Models/MobileAppStore.swift:267-279`.

**Proposed change:** Adapt the Mac's mutation reconciliation and serialize publication. Persist unacknowledged edits, merge responses into the current state, and acknowledge only the edit versions actually saved. Verify the current iPhone source before implementing this shared-client phase. This race does not apply to the Mac's already-repaired response handling.

### 6. One malformed record blocks an otherwise healthy fetch

Photo mapping and selection loads decode with a throwing `map`. One malformed payload prevents the caller from receiving healthy records. An individual query-result error likewise aborts the collection.

Evidence: pinned `Shared/CloudPhotoMappingStore.swift:40-45,67-74,106-136`.

No malformed production record was observed. The current behavior fails closed, which protects against treating an incomplete result as a complete inventory.

**Proposed change:** Represent incomplete results explicitly, retain the last good local state, and report the affected record without exposing its content. Continue independent safe work where possible. Never interpret a failed or missing record as a deletion. Apple similarly recommends handling individual failures within a [partial CloudKit failure](https://developer.apple.com/documentation/cloudkit/ckerror?changes=_8_2).

## Existing safeguards to preserve

The review rejected the idea that query pagination stops after the first page: the pinned stores consume every cursor. It also rejected the idea that a failed Mac retirement loses its removal intent: the pending retirement persists until the cloud confirms a disabled record and the local acknowledgement saves successfully.

Other safeguards include separate selection records with explicit removal markers, one fresh read-and-merge retry for concurrent record changes, serialization of Mac cloud operations, and Mac reconciliation of edits made during an asynchronous preference request.

## Implementation sequence and acceptance checks

| Phase | Scope | Required evidence before release |
| --- | --- | --- |
| 1. Recovery and status | Mac cloud worker, aggregate results, pending-work status, focused regression tests | Start offline, change a setting, restore connectivity without activating the window, and observe eventual cloud convergence. Fail one retirement while other writes succeed and confirm status remains pending. Verify cancellation and operation ordering without deadlocks. |
| 2. Account and edit integrity | Account-bound persistence, shared preference model, iPhone publication, compatible package release | Simulate account A changing to B and prove A's queued writes cannot reach B. Restart with pending edits. Exercise every conflict order, old/new client payload round trips, and an older response followed by a failed newer save. |
| 3. Transport resilience | Explicit incomplete results and a CKSyncEngine evaluation in a development container | Inject throttling, repeated conflicts, one malformed record, partial failure, expired change state, and interrupted writes. Prove retries neither duplicate content nor lose removals. Test a large paginated selection. |

Apple's [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9?language=objc) can manage scheduling, transient retries, and account events. It still requires the app to persist engine state and resolve application-specific conflicts. Its schedule depends on system conditions, so adopting it would not justify promising immediate delivery. Existing records, entitlements, and compatibility with installed clients need a staged migration plan.

Keep multi-Mac coordination disabled during this work. Its current heartbeat warns about another Mac but does not grant exclusive permission to write. Enabling multiple writers needs a separate coordination design, including expired ownership, interrupted writes, deletion propagation, and frame/account isolation.

Add a release check for the production record types, fields, and query indexes that each enabled feature requires. Signing and notarization do not verify these. Apple requires [deploying the CloudKit schema](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema?changes=_9%2C_9) separately, and production schema changes are additive. This review did not inspect or deploy the live schema.

## Verification and boundaries

The review used current local source, two read-only reviewers, an executed reproduction of the shared preference model, and Apple's documentation accessed September 5, 2026. Four failure paths, one missing account safeguard, and one availability limitation survived review. Two suspected gaps, pagination and lost retirement intent, were refuted.

The remaining scenarios have source evidence and specified regression tests, not live fault-injection results. No application code, credentials, cloud records, schema, or dependency checkout was changed. The full app test suite was not rerun for this documentation-only assessment. Version 1.6.6 remains the release from the preceding work.
