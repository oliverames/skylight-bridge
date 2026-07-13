# Skylight API Evidence and Compatibility

Evidence was refreshed on July 13, 2026. Skylight still does not publish a supported public Calendar API.

## Source priority

1. [Live Skylight web bundle](https://ourskylight.com/_expo/static/js/web/index-db6c51f7d0e1cdbc5e6e08a465068e7d.js)
2. [go-skylight v0.1.8](https://github.com/sebrandon1/go-skylight/releases/tag/v0.1.8)
3. [Successful July 13, 2026 integration run](https://github.com/sebrandon1/go-skylight/actions/runs/29233209721/job/86761849295)
4. [go-skylight integration tests](https://github.com/sebrandon1/go-skylight/blob/main/lib/integration_test.go)
5. [HAR-derived OpenAPI project](https://github.com/TheEagleByte/skylight-api)
6. [OpenClaw skill mirror](https://playbooks.com/skills/openclaw/skills/skylight-skill)

The live web bundle is newer than OpenClaw and parts of the current community clients. OpenClaw is historical evidence, not the implementation authority.

## Current transport

```text
API root: https://app.ourskylight.com/api
API version header: Skylight-Api-Version: 2026-05-01
Authorization: Bearer <access token>
OAuth client: skylight-mobile
OAuth scope: everything
```

Current login uses a web session, OAuth authorization code exchange, access token, and rotating refresh token. The old OpenClaw Basic-auth session endpoint is stale.

## Important corrections

- Current list kinds are `to_do`, `shopping`, and `other`.
- The current list visibility field is `hide_on_device`.
- Current Task Box routes use `/frames/{frameId}/task_box/items`.
- The live app models routines as chores carrying a `routine` field.
- Standalone `/routines` routes are experimental and absent from the live bundle.
- The current API header version is `2026-05-01`.

## Confidence grades

- Grade A: present in current source and exercised by authenticated integration tests
- Grade B: present in the live Skylight bundle but not independently exercised
- Grade C: present only in a current community client
- Grade D: historical or contradicted evidence

The in-app API Coverage page is generated from `SkylightEndpointCatalog`. It currently records 201 unique method and path combinations across frames, devices, albums, photos, lists, chores, Task Box, rewards, recipes, meals, categories, calendars, Sidekick, notifications, account operations, and experimental routes.

## Photo behavior

Album CRUD, album membership, photo listing, photo upload presigning, and managed deletion are present in the live client. The two-step upload uses `POST /upload_url`, followed by a raw upload to a presigned object-storage URL. Album membership uses `POST /frames/{frameId}/albums/add_to` and `/remove_from`.

Official Skylight support confirms JPEG, HEIC, and PNG support, album creation and management, and the distinction between removing an album membership and deleting a photo:

- [Supported file types](https://skylight.zendesk.com/hc/en-us/articles/360024406912-What-file-types-does-Skylight-support)
- [Photos feature](https://skylight.zendesk.com/hc/en-us/articles/45778462751899-Photos)
- [Photo management](https://skylight.zendesk.com/hc/en-us/articles/45794667935003-Managing-Your-Photos)
- [Photo sizing guidance](https://skylight.zendesk.com/hc/en-us/articles/360022886012-What-is-the-recommended-size-of-photos-that-work-best-with-the-frame)

## Compatibility policy

- Decode unknown response fields without failing.
- Keep the API version configurable.
- Keep flat JSON and JSON:API envelopes separate.
- Add strongly typed operations only when request and response shapes are observed.
- Retain a generic authenticated request path for lower-priority live namespaces with incomplete schemas.
- Run account-backed integration tests only against explicitly configured test data.
- Never interpret endpoint visibility as proof of Skylight Plus entitlement. Query `/plus_access`.
