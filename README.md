# Skylight Bridge

Skylight Bridge is a private macOS utility that mirrors explicitly selected Apple content to a Skylight Calendar account.

The app keeps Apple Photos, Reminders, and Notes as the source systems. Nothing syncs until the user creates and enables a mapping.

## Product scope

- Photos: choose an album, folder, Favorites, or individual photos. The bridge renders the current edited appearance, converts it to sRGB JPEG, strips location metadata by default, uploads it, and manages only its own Skylight copies.
- Reminders: choose individual Reminders lists, then include the whole list or selected reminders. Each mapping can be one-way or two-way.
- Recipes: choose an Apple Notes folder, then synchronize every note or selected recipe notes.
- Meals: choose a separate Notes folder, then synchronize every note or selected meal-plan notes.
- API coverage: typed clients cover the stable discovered resources, and a generic authenticated path covers live routes whose schemas remain provisional. Calendar, chores, routines, rewards, and Task Box resources do not appear as sync features in the product UI.

There is intentionally no calendar sync interface. Google Calendar already covers that use case. There is also no chores, routines, or Task Box sync interface because Apple Reminders does not provide a faithful equivalent.

## Requirements

- macOS 14 or later
- Swift 6.2 or later
- A Skylight Calendar account
- Skylight Plus for Skylight features that require it
- Photos, Reminders, and Apple Events permissions for the sources you use

Skylight does not publish a supported public API. The private API client can break when Skylight changes its service.

## Build and test

```bash
swift test
./script/build_and_run.sh --verify
```

The run script builds a local app bundle at `dist/Skylight Bridge.app`, validates its `Info.plist`, launches it, and verifies the process. The Codex Run action uses the same script.

## First run

1. Open Settings and connect the Skylight account. The app discovers its frames and devices automatically.
2. Keep Dry Run enabled.
3. Open Photos, Reminders, Recipes, and Meals to grant only the source permissions you need.
4. Add source mappings. No unselected list, reminder, folder, note, album, or photo is considered.
5. Run a sync preview and inspect Activity.
6. Turn off Dry Run only after the preview matches the intended changes.

Skylight credentials and OAuth tokens are stored in the macOS Keychain. Mapping configuration and bridge-owned identity records are stored in the user's Application Support directory.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [API evidence and compatibility](docs/API_EVIDENCE.md)

## Verification

Unit tests cover production sync orchestration, deterministic reconciliation, parsers, authentication, and API request contracts. The opt-in live integration test exercises OAuth plus temporary list, photo, album, recipe, and meal lifecycles, with cleanup:

```bash
SKYLIGHT_EMAIL="..." SKYLIGHT_PASSWORD="..." \
  swift test --build-system native --disable-xctest --enable-swift-testing \
  --filter LiveSkylightIntegrationTests
```

Embedded Apple Notes attachments are not uploaded to recipes because the discovered private recipe API does not expose a stable image-write contract.
