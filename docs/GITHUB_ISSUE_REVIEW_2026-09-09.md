# GitHub issue review, September 9, 2026

Author: Oliver Ames

## Task list

- [x] Verify reporter confirmations and close #1.
- [x] Correct and test the current Up for Grabs request contracts for #2.
- [x] Investigate the HTTP 400 authorization failure in #4 and record remaining evidence needed.
- [x] Remove the inactive Mac heartbeat and warning UI for #5, retaining the disabled shared-sync-state boundary.
- [x] Align the unused creation and search helpers in #6, authorized during this review.
- [ ] Run repository checks, review changes, commit, push, and update issue status.

## Initial evidence

All four open issues and their comments were read on September 9, 2026.
Issue #1 now has success confirmations from all three reporters.
Issue #2's September 8 screenshot confirms POST /chores returns HTTP 422 without validation details for an unassigned, nonrepeating reminder.
Issue #4's latest screenshots both report HTTP 400 at authorization, after credential submission. Both affected reporters rule out plus signs and Google sign-in.
Issue #5 explicitly permits removing the unused heartbeat instead of designing multi-Mac write ownership.

The current first-party web bundle is https://ourskylight.com/_expo/static/js/web/index-a6cbc594b1fcb290cba924c25e88fdeb.js.
It sends a flat chore object to POST /frames/{id}/chores/create_multiple and explicitly requests include_up_for_grabs on chore inventories.
These are source observations, not authenticated confirmation of the reporters' account behavior.

## Changes and verification

For [#2](https://github.com/oliverames/skylight-bridge/issues/2), unassigned creation now uses the observed flat-object request and collection response at `create_multiple`. It requires exactly one returned resource and does not retry an ambiguous successful write. Assigned creation retains its existing single-resource endpoint. Both the full inventory and current-occurrence requests explicitly include unassigned chores, allowing subsequent reconciliation to find them.

For [#6](https://github.com/oliverames/skylight-bridge/issues/6), `createChores` now accepts one chore definition with selected profile IDs and returns the complete collection. The unused array wrapper was removed. Search now uses `search_query` and includes unassigned results. The active unassigned-create path reuses the corrected helper.

For [#5](https://github.com/oliverames/skylight-bridge/issues/5), the Mac no longer publishes or reads heartbeats, stores their warning, or renders the unused warning UI. Shared sync links remain disabled. The release gate still rejects enabling multi-Mac coordination. No upstream shared-package types, production records, or schemas were changed.

The repository test runner passes 272 tests in 27 suites, plus seven schema-validator tests and the appcast helper checks. Transport fixtures cover unassigned creation, assigned creation, empty and ambiguous creation responses, both inventory shapes, multi-profile creation, and search. Live account tests remain disabled because their explicit test credentials are not configured. No personal chores were created or modified.

The optimized build passes with warnings treated as errors. The final source diff passes whitespace checks, and a reference search confirms the removed heartbeat and batch-wrapper symbols have no remaining references in Sources or Tests.

## Remaining work

[Issue #2](https://github.com/oliverames/skylight-bridge/issues/2) remains open pending a packaged release and confirmation on the reporter's account. The request mismatch is corrected and fixture-tested, but the underlying HTTP 422 was not independently reproduced with that account.

[Issue #4](https://github.com/oliverames/skylight-bridge/issues/4) remains unresolved. The screenshots now confirm the same HTTP 400 authorization failure for both affected reporters on 1.7.1. No raw response or OAuth error code is available. An unauthenticated request using the app's authorization parameters and User-Agent returned the expected HTTP 302 login redirect on September 9, 2026. This does not test the failing authenticated step. An initial Python-default User-Agent probe was blocked with HTTP 403, Cloudflare error 1010, so it was repeated with the app's actual User-Agent.

The next diagnostic step is a sanitized authenticated trace from an affected account, retaining HTTP statuses and a recognized OAuth error classification without passwords, cookies, tokens, authorization codes, or raw response bodies. No authentication changes were made without that evidence. Existing live OAuth tests require explicitly configured test credentials, which are absent in this session.

This work changes source only. It does not install an app or publish a signed release.
