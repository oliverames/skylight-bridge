# Skylight Bridge

Skylight Bridge is a private macOS utility, with an iPhone companion, that mirrors explicitly selected Apple content to a Skylight Calendar account.

The app keeps Apple Photos, Reminders, and Notes as the source systems, while Skylight's Chore Chart defines the household members and recurring chore schedule. Nothing syncs until the user creates and enables a mapping.

## Product scope

- Photos: choose an album, folder, shared album, Favorites, or individual photos. The bridge renders the current edited appearance (including RAW and ProRAW), converts it to sRGB JPEG, strips location metadata by default, uploads it, and manages only its own Skylight copies. Photos always push one way to Skylight. An individual-photo mapping can be managed from the Mac or iPhone: selections are merged into the shared iCloud list, and an explicit, confirmed removal on either device removes only that photo from both. Its destination, conversion, removal policy, and enabled state are shared too. Deleting a photo mapping removes the copies it created from Skylight, since Apple Photos is never touched, and also deletes the Skylight album if the bridge created it and it is now empty. The menu bar icon pulses while a sync is running and switches to a warning glyph if the last sync failed; the menu shows the last sync time.
- Reminders: link an Apple Reminders list with a Skylight list. Either side can be an existing list or created new, so a list that already lives on the Skylight can flow into a fresh Apple Reminders list. Each mapping is one-way or two-way, and the first sync into an existing list links items whose title and completion state match instead of duplicating them. Two-way sync preserves separate additions on each side and merges simultaneous edits field by field, using the conflict policy only when both sides changed the same field. Deleting a mapping asks whether to also remove the synced items from Skylight or Apple Reminders.
- Chores: configure the Chore Chart on Skylight first, then use the clear **Set Up Lists from Skylight** action to create or reuse one Apple Reminders list per selected family member, plus an Up for Grabs list. The bridge carries true recurrence rules in both directions and synchronizes today's completion as an occurrence, so checking off a repeating reminder marks that day's Skylight chore complete and a Skylight completion advances the reminder. Unsupported recurrence details are preserved on Skylight instead of being overwritten.
- Recipes: choose an Apple Notes folder, then synchronize every note or selected recipe notes. Recipe sync can be push-only or two-way; two-way pulls Skylight recipe-box changes back into the folder as notes. With the meal category set to Automatic, each recipe is sorted into the right Skylight category (Breakfast, Lunch, Dinner, …) on this Mac by Apple Intelligence, and recipes without a title emoji get one; picking a category files everything there instead, and without Apple Intelligence the bridge falls back to the first category. Notes the bridge writes use native Apple Notes styling (title heading, section headings, and real bullet and numbered lists) with a toggle to fall back to plain text, and notes containing attachments are never rewritten.
- Meals: choose a separate Notes folder, then synchronize every note or selected meal-plan notes. Meal plans always push one way because rewriting freeform meal notes from parsed data would risk user text.
- API coverage: typed clients cover the stable discovered resources, including the grouped Chore Chart inventory and occurrence-completion contract. A generic authenticated path covers live routes whose schemas remain provisional. Calendar, standalone routines, rewards, and Task Box resources do not appear as sync features in the product UI.

There is intentionally no calendar sync interface. Google Calendar already covers that use case. Standalone routines and Task Box remain outside the sync interface; Chore Chart routines are represented as recurring Apple reminders with guarded per-occurrence completion handling.

## Requirements

- macOS 26 or 27
- An iPhone running iOS 18.2 or later, if using the companion app
- Swift 6.4 or later
- A Skylight Calendar account
- Skylight Plus for Skylight features that require it
- Photos, Reminders, and Apple Events permissions for the sources you use

Skylight does not publish a supported public API. The private API client can break when Skylight changes its service.

## Current project status

The latest published Mac release is
[**1.5.0**](https://github.com/oliverames/skylight-bridge/releases/tag/v1.5.0).
It includes two-way Chore Chart synchronization, cross-device selected-photo
reconciliation, and the Relay Ribbon app icon. Its Developer ID build embeds
the CloudKit provisioning profile, is notarized and stapled, and is accepted by
Gatekeeper.

The native iPhone companion lives in the separate private
[`skylight-bridge-ios`](https://github.com/oliverames/skylight-bridge-ios)
repository. It configures shared preferences and individual-photo mappings;
the Mac remains responsible for Skylight authentication and synchronization.
Simulator builds intentionally report iCloud as unavailable. Both app IDs now
have the shared `iCloud.com.oliverames.SkylightBridge` container and matching
profiles. The remaining validation is the physical-device CloudKit round trip.

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
3. Open Photos, Reminders, Chores, Recipes, and Meals to grant only the source permissions you need.
4. For chores, configure people and chores on Skylight first, then choose **Set Up Lists from Skylight**. For other areas, add source mappings. No unselected list, reminder, folder, note, album, or photo is considered. Individual-photo selections can then be added or explicitly removed from either client.
5. Run a sync preview and inspect Activity.
6. Turn off Preview mode only after the preview matches the intended changes.

Adding, editing, or enabling a mapping triggers a sync automatically (a preview while Preview mode is on), so changes appear in Activity without waiting for the background schedule.

Skylight credentials and OAuth tokens are stored in the macOS Keychain. Mapping configuration and bridge-owned identity records are stored in the user's Application Support directory. The preferences and individual-photo mappings that the iPhone can manage are additionally reconciled through the signed-in person's private iCloud CloudKit database (`iCloud.com.oliverames.SkylightBridge`). The iPhone cannot access Apple Notes, so recipes and meal plans remain Mac-only.

Sync settings (interval, Launch at login, Hide Dock icon, Preview mode) save automatically as you change them. A short welcome walkthrough appears on first launch, and after the bridge has synchronized enough changes it may occasionally invite an optional donation (buymeacoffee.com/oliverames); "Don't Ask Again" silences that forever. Hiding the Dock icon keeps the app running in the menu bar only; reopen the main window from the menu bar icon.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [API evidence and compatibility](docs/API_EVIDENCE.md)

## Verification

Unit tests cover production sync orchestration, deterministic reconciliation, recurrence conversion, parsers, authentication, and API request contracts. Opt-in live tests cover the read-only Chore Chart response shape and a temporary recurring chore create, update, complete, reopen, and delete lifecycle with cleanup:

```bash
SKYLIGHT_LIVE_TESTS=1 SKYLIGHT_EMAIL="..." SKYLIGHT_PASSWORD="..." \
  swift test --build-system native --disable-xctest --enable-swift-testing \
  --filter LiveSkylightIntegrationTests
```

Each live test is disabled unless its corresponding opt-in variable is set. `SKYLIGHT_LIVE_READS` uses the saved Keychain session and does not mutate Skylight. `SKYLIGHT_LIVE_CHORE_MUTATIONS` creates a temporary recurring chore, exercises its lifecycle, and removes it in cleanup. The broader legacy lifecycle test uses `SKYLIGHT_LIVE_TESTS` plus the supplied account credentials.

```bash
SKYLIGHT_LIVE_READS=1 swift test --filter liveChoreInventoryContract
SKYLIGHT_LIVE_CHORE_MUTATIONS=1 swift test --filter liveRecurringChoreLifecycle
```

The release script produces a universal Developer ID-signed DMG, submits both the app and DMG for notarization, staples both tickets, mounts the finished image read-only, re-verifies the nested app, and writes a SHA-256 checksum:

```bash
DEVELOPER_ID_PROFILE="/path/to/SkylightBridge.provisionprofile" \
NOTARY_KEY_FILE="/path/to/AuthKey.p8" \
NOTARY_KEY_ID="..." \
NOTARY_ISSUER_ID="..." \
  ./script/build_release.sh
```

Embedded Apple Notes attachments are not uploaded to recipes because the discovered private recipe API does not expose a stable image-write contract.
