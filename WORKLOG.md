## 2026-07-14 - Skylight Bridge 1.2.0: cleanup flows, field-level merge, auto-sync

**What changed**: Eight issues from testing the 1.1.0 build. (1) The "Selected Photos" picker now passes `photoLibrary: .shared()` so `PhotosPickerItem.itemIdentifier` resolves instead of returning nil and reporting zero selected. (2) Deleting a photo mapping now purges the Skylight copies it created, since Apple Photos is never touched. (3) Deleting a reminder mapping opens a confirmation dialog asking whether to also remove the synced items from Skylight, from Apple Reminders, or from neither. (4) Two-way reminder merge became field-aware: separate additions on both sides are preserved, and simultaneous edits merge title and completion independently, using the conflict policy only when the same field changed on both sides (new `.merge` action; last-synced title/completion baseline stored on the record). (5) Adding, editing, or enabling a mapping now triggers an automatic sync (a preview under Dry Run) so changes land in Activity immediately. Confirmed already-correct and left as-is: Skylight albums are real (API evidence), RAW/ProRAW already convert to sRGB JPEG before upload, and recipes pulled from Skylight already write formatted Apple Notes.

**Decisions made**: Photo-mapping deletion always removes the Skylight copies (Apple Photos is the untouched source), while reminder-mapping deletion asks per side because reminders can live on both. Field-level merge carries the merged value in the action and writes both sides only when the merge differs from each; when it coincides with one side it reuses the existing one-way update. Cleanup is best-effort per item (an already-deleted item does not abort the sweep) and requires a Skylight connection. Auto-sync is wired to mapping save and enable toggles specifically, not to Settings changes like interval or Dry Run.

**Verification**: 61 tests pass normally, under AddressSanitizer, and under ThreadSanitizer, including new coverage for field-level merge (disjoint edits, same-field conflict, preserved additions) and both cleanup paths. Bumped to 1.2.0 (3).

**Left off at**: 1.2.0 pending the verified build, screenshot of the photo-selection fix, and notarized release.

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
