# Skylight Bridge

Skylight Bridge is a private macOS utility that mirrors explicitly selected Apple content to a Skylight Calendar account.

The app keeps Apple Photos, Reminders, and Notes as the source systems. Nothing syncs until the user creates and enables a mapping.

## Product scope

- Photos: choose an album, folder, shared album, Favorites, or individual photos. The bridge renders the current edited appearance (including RAW and ProRAW), converts it to sRGB JPEG, strips location metadata by default, uploads it, and manages only its own Skylight copies. Photos always push one way to Skylight. Deleting a photo mapping removes the copies it created from Skylight, since Apple Photos is never touched, and also deletes the Skylight album if the bridge created it and it is now empty. The menu bar icon pulses while a sync is running and switches to a warning glyph if the last sync failed; the menu shows the last sync time.
- Reminders: link an Apple Reminders list with a Skylight list. Either side can be an existing list or created new, so a list that already lives on the Skylight can flow into a fresh Apple Reminders list. Each mapping is one-way or two-way, and the first sync into an existing list links items whose title and completion state match instead of duplicating them. Two-way sync preserves separate additions on each side and merges simultaneous edits field by field, using the conflict policy only when both sides changed the same field. Deleting a mapping asks whether to also remove the synced items from Skylight or Apple Reminders.
- Recipes: choose an Apple Notes folder, then synchronize every note or selected recipe notes. Recipe sync can be push-only or two-way; two-way pulls Skylight recipe-box changes back into the folder as notes. With the meal category set to Automatic, each recipe is sorted into the right Skylight category (Breakfast, Lunch, Dinner, …) on this Mac by Apple Intelligence, and recipes without a title emoji get one; picking a category files everything there instead, and without Apple Intelligence the bridge falls back to the first category. Notes the bridge writes use native Apple Notes styling (title heading, section headings, and real bullet and numbered lists) with a toggle to fall back to plain text, and notes containing attachments are never rewritten.
- Meals: choose a separate Notes folder, then synchronize every note or selected meal-plan notes. Meal plans always push one way because rewriting freeform meal notes from parsed data would risk user text.
- API coverage: typed clients cover the stable discovered resources, and a generic authenticated path covers live routes whose schemas remain provisional. Calendar, chores, routines, rewards, and Task Box resources do not appear as sync features in the product UI.

There is intentionally no calendar sync interface. Google Calendar already covers that use case. There is also no chores, routines, or Task Box sync interface because Apple Reminders does not provide a faithful equivalent.

## Requirements

- macOS 26 or 27
- Swift 6.4 or later
- A Skylight Calendar account
- Skylight Plus for Skylight features that require it
- Photos, Reminders, and Apple Events permissions for the sources you use

Skylight does not publish a supported public API. The private API client can break when Skylight changes its service.

## Build and test

```bash
swift test
./script/build_and_run.sh --verify
```

The run script builds a Developer ID-signed local app bundle at `dist/Skylight Bridge.app` when the signing identity is available, validates the bundle, launches it, and verifies the process. The Codex Run action uses the same script.

The interface uses native macOS 26 SwiftUI navigation with standard grouped-settings forms for all content: flat cards, plain bordered controls, and capsule status badges. Liquid Glass appears only in system chrome such as the toolbar and sidebar. There are no compatibility shims for older systems.

## First run

1. Open the Account section in the sidebar and sign in to Skylight. The app discovers its frames and devices automatically.
2. Keep Preview mode enabled (the "Preview changes without applying them" toggle in the Sync section).
3. Open Photos, Reminders, Recipes, and Meals to grant only the source permissions you need.
4. Add source mappings. No unselected list, reminder, folder, note, album, or photo is considered.
5. Run a sync preview and inspect Activity.
6. Turn off Preview mode only after the preview matches the intended changes.

Adding, editing, or enabling a mapping triggers a sync automatically (a preview while Preview mode is on), so changes appear in Activity without waiting for the background schedule.

Skylight credentials and OAuth tokens are stored in the macOS Keychain. Mapping configuration and bridge-owned identity records are stored in the user's Application Support directory.

Sync settings (interval, Launch at login, Hide Dock icon, Preview mode) save automatically as you change them. A short welcome walkthrough appears on first launch, and after the bridge has synchronized enough changes it may occasionally invite an optional donation (buymeacoffee.com/oliverames); "Don't Ask Again" silences that forever. Hiding the Dock icon keeps the app running in the menu bar only; reopen the main window from the menu bar icon.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [API evidence and compatibility](docs/API_EVIDENCE.md)

## Verification

Unit tests cover production sync orchestration, deterministic reconciliation, parsers, authentication, and API request contracts. The opt-in live integration test exercises OAuth plus temporary list, photo, album, recipe, and meal lifecycles, with cleanup:

```bash
SKYLIGHT_LIVE_TESTS=1 SKYLIGHT_EMAIL="..." SKYLIGHT_PASSWORD="..." \
  swift test --build-system native --disable-xctest --enable-swift-testing \
  --filter LiveSkylightIntegrationTests
```

Live tests are disabled unless `SKYLIGHT_LIVE_TESTS=1` is set because they create and then remove temporary Skylight content. The release script produces a universal Developer ID-signed DMG, submits both the app and DMG for notarization, staples both tickets, mounts the finished image read-only, re-verifies the nested app, and writes a SHA-256 checksum:

```bash
NOTARY_KEY_FILE="/path/to/AuthKey.p8" \
NOTARY_KEY_ID="..." \
NOTARY_ISSUER_ID="..." \
  ./script/build_release.sh
```

Embedded Apple Notes attachments are not uploaded to recipes because the discovered private recipe API does not expose a stable image-write contract.
