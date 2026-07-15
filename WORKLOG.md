## 2026-07-15 - iPhone companion iCloud reconciliation

**What changed**: Added the Mac side of the native iPhone companion. The app now carries the CloudKit entitlement for `iCloud.com.oliverames.SkylightBridge` and depends on the shared CloudKit package from the iPhone repository. Individual-photo mappings use portable iCloud asset identifiers. Their destination, enabled state, JPEG conversion, location-removal policy, selected frame, preview mode, and cadence reconcile with the iPhone. Selecting another photo unions it into the shared list; a confirmed removal creates a per-photo removal record that propagates to the other client without touching the original in Apple Photos. The final hardening commit (`943848e`) imports those removal records before the Mac publishes local selections, and republishes a locally merged offline preference set, preventing a cold start or reconnect from restoring removed photos or losing a local preference change.

**Decisions made**: Cloud sharing is intentionally limited to the settings and individual-photo mappings that iOS can manage. Album, Favorites, folder, Reminders, Chores, Recipes, and Meals mappings stay on the Mac. Recipes and meal plans cannot be reproduced on iPhone because Apple does not expose an API for app access to Apple Notes folders. The cross-device photo set is modeled as independent observed add/remove records, not one mutable array, so independent additions survive and deletion remains explicit.

**Verification**: `swift test` passed 103 tests in 17 suites after the reconciliation changes. The companion repository's iPhone target passed 10 tests through XcodeBuildMCP on an iPhone 17 Pro simulator, built and ran successfully, and its overview UI was inspected in the simulator. The Mac and iPhone repositories were both pushed to `main` before this worklog entry.

**Left off at**: The Mac changes are committed as `db384c6` and `943848e`; the companion's current release tag is `0.1.6` at `960b018`. The remaining end-to-end check is on physical signed devices.

**Open questions**: Xcode has no Apple Developer account/provisioning profile that enables `iCloud.com.oliverames.SkylightBridge` for the iPhone app. Enable the container for both app IDs in the Developer portal, regenerate profiles, then test add, offline edit, and explicit removal between the Mac and a signed-in iPhone. The locally signed Mac bundle also needs normal notarization before Gatekeeper will launch it outside the development context.

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
