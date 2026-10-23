# Skylight Bridge worklog

## Current guidance

- [README](README.md) covers the app, opt-in mappings, setup and source layout.
- [API evidence](docs/API_EVIDENCE.md) records the private Skylight contract and the dates of its verification. [Product specification](docs/PRODUCT_SPEC.md) retains the integration model and limits.
- [Cloud reliability review](docs/CLOUD_RELIABILITY_REVIEW_2026-09-05.md) and [implementation record](docs/CLOUD_RELIABILITY_IMPLEMENTATION_2026-09-05.md) retain recovery and reconciliation details.
- [Release reporting](<Release Reporting.md>) covers verified delivery and its historical baselines. Use [GitHub issues](https://github.com/oliverames/skylight-bridge/issues) for current task status.

The source remains version 1.7.3. The September 11 release record preserves the PKCE correction, reporter-confirmed sign-in, tests and signed distribution evidence. Those are dated results, not fresh installed-app or account verification. The recorded CloudKit schema export must be refreshed before a later schema-affecting release.

## Developer-account migration

Oliver abandoned this migration on October 13, 2026 and requested removal of the paused local and remote branch and its worktree. The existing shipping identity is unchanged. Preparation remains reverted from main by `26ca980`; the original preparation and pause entries below are historical records, not instructions to retain or restore the deleted checkout.

## Boundaries to retain

The archived open-item list preserves unresolved remote idempotency, Notes attachment support, the hidden Meals workflow, live API probes and account/device observations. It does not establish that those features were completed or that old live-state observations remain current. API and release guidance stays in the maintained documents above.

## October 13, 2026: documentation cleanup

Preserved the complete previous worklog and corrected the README's obsolete migration-branch direction. Source, shipping identity and workflows are unchanged. Verification covered document preservation, links and heading compatibility. No app build or suite ran; the existing full suite initializes application services. No Apple app, private account or deployment was accessed.

## October 13, 2026: documentation CI

The required `build-and-test` job now validates an exact allowlist of documentation changes without configuring private package access or running native app code. The checker compares tracked Git objects, archive bytes and source blobs, retained headings, and current local links. Existing archives and preservation manifests remain immutable. Runtime, dependency, schema, resource, release and later CI changes retain the native path; invalid comparison inputs fail the job.

The initial CI change is pinned to the reviewed base and exact workflow transformation. The job name, runner, triggers, permissions and branch protections are unchanged. [Issue #12](https://github.com/oliverames/skylight-bridge/issues/12) separately tracks isolation of the app fixtures from Photos and live host services. No app build, native suite or Photos access was performed for this change.

## October 23, 2026: security review

The permission-grant script that Skylight Bridge writes for SIP-disabled Macs now keeps its two code-requirement files in a `mktemp -d` directory, which a trap removes on exit. It used to write fixed `/tmp/sb_*.csreq` names, which another local account could pre-create as symlinks. The rest of the review covered Keychain items, local-file HMAC envelopes, OAuth redirect validation, AppleScript literal escaping, the CI workflow and the signed Sparkle feed; the runbook audit verified the live `gh-pages` appcast. It found nothing else to change. The unused Skylight API client endpoints remain as documented API coverage.

Verification: `swift build` succeeded. A standalone compile of `SystemSecurityDiagnostics.swift` produced a script that passed `bash -n`. Its temporary-directory section produced both requirement blobs and removed the directory on exit. The native suite did not run because it initializes app services, including Photos (#12).

## Historical record

The [complete previous worklog](WORKLOG-2026-10-13.md) is preserved byte for byte at the repository root, keeping its original relative-link context. Older line references refer to that file. The [preservation record](docs/archive/worklog-2026-10-13.json) identifies the source revision, byte count and SHA-256 digest.

<details>
<summary>Previous entry links</summary>

<a id="2026-10-07---preserve-paused-migration-outside-main"></a>
- [2026-10-07 - Preserve paused migration outside main](WORKLOG-2026-10-13.md#2026-10-07---preserve-paused-migration-outside-main)
<a id="2026-10-07---github-issue-review-closeout"></a>
- [2026-10-07 - GitHub Issue Review Closeout](WORKLOG-2026-10-13.md#2026-10-07---github-issue-review-closeout)
<a id="2026-10-07---readme-refresh-closeout"></a>
- [2026-10-07 - README Refresh Closeout](WORKLOG-2026-10-13.md#2026-10-07---readme-refresh-closeout)
<a id="open-items"></a>
- [Open items](WORKLOG-2026-10-13.md#open-items)
<a id="2026-09-11---skylight-sign-in-restored-and-173-released"></a>
- [2026-09-11 - Skylight sign-in restored and 1.7.3 released](WORKLOG-2026-10-13.md#2026-09-11---skylight-sign-in-restored-and-173-released)
<a id="2026-09-09---skylight-bridge-172-released"></a>
- [2026-09-09 - Skylight Bridge 1.7.2 released](WORKLOG-2026-10-13.md#2026-09-09---skylight-bridge-172-released)
<a id="2026-09-09---github-issue-review-and-chore-api-compatibility"></a>
- [2026-09-09 - GitHub issue review and chore API compatibility](WORKLOG-2026-10-13.md#2026-09-09---github-issue-review-and-chore-api-compatibility)
<a id="2026-09-05---codex-session-review-170-closeout-and-171-released"></a>
- [2026-09-05 - Codex session review, 1.7.0 closeout, and 1.7.1 released](WORKLOG-2026-10-13.md#2026-09-05---codex-session-review-170-closeout-and-171-released)
<a id="2026-09-05---cloud-reliability-and-170-preparation"></a>
- [2026-09-05 - Cloud reliability and 1.7.0 preparation](WORKLOG-2026-10-13.md#2026-09-05---cloud-reliability-and-170-preparation)
<a id="2026-09-05---github-issue-review-and-166-released"></a>
- [2026-09-05 - GitHub issue review and 1.6.6 released](WORKLOG-2026-10-13.md#2026-09-05---github-issue-review-and-166-released)
<a id="2026-09-04---startup-correction-and-165-released"></a>
- [2026-09-04 - Startup correction and 1.6.5 released](WORKLOG-2026-10-13.md#2026-09-04---startup-correction-and-165-released)
<a id="2026-09-04---bug-review-photo-previews-and-164-release"></a>
- [2026-09-04 - Bug review, photo previews, and 1.6.4 release](WORKLOG-2026-10-13.md#2026-09-04---bug-review-photo-previews-and-164-release)
<a id="2026-08-27---shared-cloud-gate-deadlock-fixed-162-and-163-released"></a>
- [2026-08-27 - Shared Cloud gate deadlock fixed; 1.6.2 and 1.6.3 released](WORKLOG-2026-10-13.md#2026-08-27---shared-cloud-gate-deadlock-fixed-162-and-163-released)
<a id="2026-08-27---adversarial-bug-fix-rounds-recovery-reconciliation-and-cloud-race-hardening"></a>
- [2026-08-27 - Adversarial bug-fix rounds: recovery, reconciliation, and Cloud race hardening](WORKLOG-2026-10-13.md#2026-08-27---adversarial-bug-fix-rounds-recovery-reconciliation-and-cloud-race-hardening)
<a id="2026-08-26---skylight-bridge-161-released-the-adversarial-review-fixes-ship"></a>
- [2026-08-26 - Skylight Bridge 1.6.1 released: the adversarial-review fixes ship](WORKLOG-2026-10-13.md#2026-08-26---skylight-bridge-161-released-the-adversarial-review-fixes-ship)
<a id="2026-08-25---adversarial-review-pass-24-confirmed-defects-fixed-no-regressions"></a>
- [2026-08-25 - Adversarial review pass: 24 confirmed defects fixed, no regressions](WORKLOG-2026-10-13.md#2026-08-25---adversarial-review-pass-24-confirmed-defects-fixed-no-regressions)
<a id="earlier-history-before-2026-08-23"></a>
- [Earlier history (before 2026-08-23)](WORKLOG-2026-10-13.md#earlier-history-before-2026-08-23)

</details>
