# Product Specification

## Purpose

Skylight Bridge lets a person choose a narrow set of Apple content and mirror it to Skylight without turning every Apple list, note, or photo into household content.

Apple remains the source of truth for Photos and meal-plan notes. Reminders, Recipes, and Chores can be one-way or two-way because their content naturally changes on either device. Skylight remains the first-time setup authority for Chore Chart people.

## Selection model

Every integration is opt-in.

### Photos

A mapping can use one of three sources:

1. A selected Apple Photos album or folder
2. The built-in Favorites smart album
3. An explicit set of images chosen with the system photo picker

Each mapping targets one Skylight album. The bridge records the Apple asset identifier, render fingerprint, output hash, Skylight message identifier, album membership, and the identifier of any album it creates. It never deletes a Skylight photo that it did not create. Deleting a photo mapping removes the copies it created from Skylight; because Apple Photos is never modified, the Skylight album is the only place those copies live. If the bridge created the destination album, that album is also deleted once it is empty, so a bridge-created album with photos the user added on Skylight is left in place.

RAW and ProRAW sources are rendered to a displayable image by PhotoKit and then encoded as sRGB JPEG, so nothing RAW is ever uploaded.

For selected individual photos, a generated local name is published as the caption of the linked Skylight message. The bridge never writes that name to Apple Photos.

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

### iCloud sharing for individual photos

The iPhone companion and Mac share selected Skylight frame, preview mode, preferred cadence, and the settings for individual-photo mappings through the person's private CloudKit database. An individual asset is represented by a separate portable iCloud identifier record, rather than a whole-list replacement. Adding photos on either device therefore preserves the existing selections. Removing a photo requires an explicit confirmation and writes a removal record, so the same photo disappears from the other client's list without deleting the original from Apple Photos. A client that reconciles an offline local preference change republishes the merged preference set when iCloud becomes available, and the Mac imports removal records before it publishes its local selections to prevent a cold launch from resurrecting a deliberately removed item.

### Reminders

A mapping links one Apple Reminders list with one Skylight list. Either side can be an existing list or a new one:

- an existing Apple Reminders list, or a fresh list the bridge creates in Apple Reminders when the mapping is saved
- an existing Skylight list, or a new destination list created during the first live sync
- every reminder in the Apple list, or selected reminders only
- Apple to Skylight, Skylight to Apple, or two-way sync
- newest change, Apple, or Skylight as the conflict policy

Starting from a Skylight list is the "new Apple list" case: pick the Skylight list, create the Apple side fresh, and the first two-way sync populates it.

At the list level, title and color are portable fields. The first sync records both baselines without relabeling either existing list; later changes flow in the allowed direction. Simultaneous edits use the mapping's conflict policy. Color clearing is intentionally not attempted because the observed Skylight request contract does not document it.

Skylight does not expose equivalents for Apple due dates, notes, URLs, priorities, tags, subtasks, or attachments. Those fields remain in Apple and local metadata. Title and completion state are the portable fields.

The bridge stores local and external Apple identifiers, the Skylight item identifier, content fingerprints, the last-synced title and completion baseline, and last-seen modification times. On the first sync into an existing list, unlinked items whose title and completion state match are linked instead of duplicated, in deterministic identifier order.

It stores the linked list identifiers and independent title and color baselines as well, so a later list metadata change can be reconciled without disturbing the list's items.

Two-way merge is field-aware. A reminder added on only one side is created on the other; neither side's independent additions are lost. When a linked reminder changed on both sides, the title and completion fields merge independently against the baseline: a field only counts as a conflict when both sides changed that same field, and only then does the conflict policy (newest, Apple, or Skylight) decide that one field. Disjoint edits, such as a rename on one side and a completion toggle on the other, are combined rather than resolved by discarding one.

Deleting a reminder mapping asks whether to also remove the items it synced from Skylight, from Apple Reminders, or from neither. Neither list itself is deleted. Cleanup is best-effort per item so an already-removed item does not block the rest.

### Chores

Chore setup begins on Skylight. After the user selects people for the Chore Chart, the Chores screen creates or reuses one Apple Reminders list per person and an Up for Grabs list. The generated mapping records each Skylight category ID, Apple list ID, list title, sync direction, conflict policy, and enabled state. Matching titles assigned to the same person are adopted on first sync rather than duplicated.

Recurring chores use a strict RRULE converter. Supported frequency, interval, weekday, month-day, end-date, count, and Skylight time-slot fields become native EventKit recurrence rules. Unknown components are never silently discarded. When a Skylight recurrence contains details EventKit cannot reproduce, Apple still receives the usable repeat schedule, the mapping is marked degraded, and later Apple-side content edits preserve the original Skylight recurrence verbatim.

Completion is occurrence-based. The bridge fetches the series inventory and the dated chore window separately, then synchronizes today's state. Completing a recurring Apple reminder marks that Skylight occurrence complete; a Skylight completion advances the Apple reminder to its next due date. Persisted due-date and completed-instance baselines prevent the same occurrence from firing twice and allow either side to reopen today's occurrence.

### Recipes

The user chooses an Apple Notes folder, then selects every note or individual recipe notes.

The interface recommends a dedicated Recipes folder with one recipe per note. Structured notes can provide title, description, servings, prep time, cook time, ingredients, instructions, tags, and source URL. A note needs only a title; ingredients and instructions are optional so recipes created in the Skylight app survive the round trip. Password-protected notes are skipped. Embedded attachments remain in Apple Notes because the discovered private recipe API does not expose a stable image-write contract.

Recipe sync is push-only by default. Two-way sync adds, with a per-selection conflict policy:

- new Skylight recipes become notes in the mapped folder, when the selection covers the entire folder
- Skylight edits rewrite the linked note when the note has not changed since the last sync
- edits on both sides resolve by newest change, Apple, or Skylight preference
- a recipe deleted on Skylight moves its linked note to Recently Deleted, which macOS keeps recoverable for 30 days
- on the first two-way sync, unlinked notes and recipes with the same title are linked instead of duplicated

The bridge writes notes in the same grammar its parser reads, so a pulled recipe produces no push on the following cycle. By default it writes rich Apple Notes HTML: an `h1` title, `h2` section headings flowing directly into native bullet and numbered lists, a spacer line after every list and between sections, escaped entities, and bare source URLs because Notes strips anchor tags on update. A per-selection toggle falls back to plain single-style text. Notes that contain attachments are never rewritten, because updating a note body through automation can wipe its attachments; those notes stay Apple-authoritative and remote edits to them are acknowledged without being applied.

Known grammar limit: the plaintext note format cannot distinguish a description line that merely *looks* like structure — a bare `Ingredients` heading word or a `Servings:`-shaped sentence written as prose — from real structure. Such a line parses into that field on the next cycle. The parser deliberately keeps this ambiguity rather than escaping on write, because narrowing it would misparse notes already written by earlier builds; freeform description prose in those shapes should avoid starting a line with a section word or a field label.

The safe Skylight representation uses the recipe summary and freeform description. The recipe body (ingredients as a bulleted list, instructions as a numbered list, plus servings, timing, tags, and a plain source name) travels in the description because a July 2026 backend check confirmed Skylight does not persist the structured ingredient array the API accepts; sending it is harmless but it is not what displays. Real source URLs go in the url field, while a plain source name such as "AllRecipes" stays in the description. Bullet-packed metadata lines like "Source: X • Servings: Y" are split into their fields, and Apple Notes attachment placeholder characters are stripped so they never become ingredient or instruction lines.

### Meals

The Meals workflow is hidden from the interface and its sync engine is gated off (`FeatureFlags.mealSyncEnabled`) until the workflow is finished; the description below is the intended behavior. The user chooses a separate Apple Notes folder, then selects every note or individual meal-plan notes. Meal entries are parsed from structured lines and matched to synchronized recipes when possible.

## Explicit exclusions

- No calendar sync interface
- No routines sync interface
- No Task Box sync interface
- No automatic ingestion of every Reminders list
- No automatic ingestion of every note in Apple Notes
- No modification of the Apple Photos library
- No iPhone access to Apple Notes folders, so recipe and meal-plan mapping remains Mac-only

The underlying Skylight client also covers discovered calendar, standalone routine, Task Box, and reward endpoints for completeness and diagnostics.

## Safety rules

- Preview mode (dry run) is enabled by default.
- A write requires an enabled mapping.
- Managed deletion is limited to remote identifiers recorded as bridge-owned, including identifiers adopted by explicit title matching when the user links existing lists.
- Two-way recipe sync never destroys a note outright; retirement moves it to Recently Deleted.
- Deleting a mapping cleans up only the items that mapping recorded as bridge-owned, and reminder cleanup is limited to the side the user explicitly chooses.
- Adding, editing, or enabling a mapping triggers a sync automatically. While Preview mode is on this is a preview, so automatic runs never change data until the user turns it off. If no Skylight account is connected yet, the app instead records a warning in Activity; the mapping syncs on the next run after sign-in.
- Manual Skylight content outside managed albums and lists is untouched.
- The activity log records previews, applied changes, and errors by integration.
- A failed or partial upload is reconciled before retrying a non-idempotent request.
- A 401 triggers at most one token refresh and the rotated refresh token is persisted.
- A 429 honors `Retry-After`.

## macOS architecture

- macOS 26 deployment floor, with macOS 27 verification
- standard grouped-settings forms for all content areas, with Liquid Glass only in system chrome
- SwiftUI `WindowGroup` for the main workspace, with account, sync, and diagnostics in the sidebar rather than a separate Settings scene, so sign-in and every setting stay in one window
- `MenuBarExtra` for quick sync and status; the standard Settings shortcut and menu open the main window on the Account section
- PhotoKit adapter isolated on the main actor
- EventKit adapter isolated on the main actor
- Apple Notes automation through `NSAppleScript`
- Core Image and Image I/O conversion actor
- Security framework Keychain store
- pure, sendable reconciliation models
- `NSBackgroundActivityScheduler` for periodic work
- `SMAppService.mainApp` for explicit launch-at-login opt-in

Apple Notes has no public data framework. A private Developer ID distribution is the practical release path because a sandboxed app needs Apple Events exceptions that are unsuitable for a normal Mac App Store build.

## iPhone companion architecture

- iOS 18.2 deployment floor with a native SwiftUI settings interface
- system Photos picker for adding individual assets, with an explicit confirmed removal mechanism
- no Apple Notes integration, because iOS does not expose a public API for app access to Apple Notes folders
- CloudKit entitlement for `iCloud.com.oliverames.SkylightBridge`, shared with the Mac client

Physical-device CloudKit testing requires the container to be enabled and assigned to both app IDs in the Apple Developer portal, followed by regenerated provisioning profiles. The simulator can build without that provisioning but is not proof of cross-device iCloud synchronization.

## Persistence

Application Support stores:

- mapping configuration
- managed Apple-to-Skylight identity links
- content hashes and modification clocks
- activity history

The private iCloud CloudKit database stores only the cross-client preferences and individual-photo mapping metadata described above. It never receives Skylight credentials or Apple Notes content.

Keychain stores:

- Skylight email
- Skylight password, only when required for reauthentication
- OAuth access token
- rotating OAuth refresh token
- stable device fingerprint

No credentials are written to project files, logs, or Application Support JSON.
