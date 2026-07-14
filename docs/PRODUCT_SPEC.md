# Product Specification

## Purpose

Skylight Bridge lets a person choose a narrow set of Apple content and mirror it to Skylight without turning every Apple list, note, or photo into household content.

Apple remains the source of truth for Photos and Notes. Reminders can be one-way or two-way because completion naturally happens on either device.

## Selection model

Every integration is opt-in.

### Photos

A mapping can use one of three sources:

1. A selected Apple Photos album or folder
2. The built-in Favorites smart album
3. An explicit set of images chosen with the system photo picker

Each mapping targets one Skylight album. The bridge records the Apple asset identifier, render fingerprint, output hash, Skylight message identifier, and album membership. It never deletes a Skylight photo that it did not create.

Default conversion behavior:

- use the current edited PhotoKit rendering
- download iCloud-only assets when needed
- preserve aspect ratio
- render RAW, ProRAW, HEIC, HDR, and wide-gamut sources to sRGB JPEG
- flatten alpha against white
- set a maximum long edge of 3,840 pixels
- use JPEG quality 0.9
- remove GPS and XMP metadata
- use the Live Photo still image in the first release

### Reminders

A mapping starts with one selected Apple Reminders list. The user then chooses:

- every reminder in that list, or selected reminders only
- Apple to Skylight, Skylight to Apple, or two-way sync
- newest change, Apple, or Skylight as the conflict policy
- an existing Skylight list or a new destination list

Skylight does not expose equivalents for Apple due dates, notes, URLs, priorities, tags, subtasks, or attachments. Those fields remain in Apple and local metadata. Title and completion state are the portable fields.

The bridge stores local and external Apple identifiers, the Skylight item identifier, content fingerprints, and last-seen modification times. Exact title and completion matches are linked during the first two-way sync to prevent avoidable duplicates.

### Recipes

The user chooses an Apple Notes folder, then selects every note or individual recipe notes.

The interface recommends a dedicated Recipes folder with one recipe per note. Structured notes can provide title, description, servings, prep time, cook time, ingredients, instructions, tags, and source URL. Password-protected notes are skipped. Embedded attachments remain in Apple Notes because the discovered private recipe API does not expose a stable image-write contract.

The safe Skylight representation uses the recipe summary and freeform description. Structured ingredient fields are provisional because their private API behavior is less stable.

### Meals

The user chooses a separate Apple Notes folder, then selects every note or individual meal-plan notes. Meal entries are parsed from structured lines and matched to synchronized recipes when possible.

## Explicit exclusions

- No calendar sync interface
- No chores sync interface
- No routines sync interface
- No Task Box sync interface
- No automatic ingestion of every Reminders list
- No automatic ingestion of every note in Apple Notes
- No modification of the Apple Photos library

The underlying Skylight client still covers discovered calendar, chore, routine, Task Box, and reward endpoints for completeness and diagnostics.

## Safety rules

- Dry Run is enabled by default.
- A write requires an enabled mapping.
- Managed deletion is limited to remote identifiers recorded as bridge-owned.
- Manual Skylight content outside managed albums and lists is untouched.
- The activity log records previews, applied changes, and errors by integration.
- A failed or partial upload is reconciled before retrying a non-idempotent request.
- A 401 triggers at most one token refresh and the rotated refresh token is persisted.
- A 429 honors `Retry-After`.

## macOS architecture

- macOS 26 deployment floor, with macOS 27 verification
- native SwiftUI Liquid Glass materials and system navigation components
- SwiftUI `WindowGroup` for the main workspace
- `MenuBarExtra` for quick sync and status
- dedicated Settings scene
- PhotoKit adapter isolated on the main actor
- EventKit adapter isolated on the main actor
- Apple Notes automation through `NSAppleScript`
- Core Image and Image I/O conversion actor
- Security framework Keychain store
- pure, sendable reconciliation models
- `NSBackgroundActivityScheduler` for periodic work
- `SMAppService.mainApp` for explicit launch-at-login opt-in

Apple Notes has no public data framework. A private Developer ID distribution is the practical release path because a sandboxed app needs Apple Events exceptions that are unsuitable for a normal Mac App Store build.

## Persistence

Application Support stores:

- mapping configuration
- managed Apple-to-Skylight identity links
- content hashes and modification clocks
- activity history

Keychain stores:

- Skylight email
- Skylight password, only when required for reauthentication
- OAuth access token
- rotating OAuth refresh token
- stable device fingerprint

No credentials are written to project files, logs, or Application Support JSON.
