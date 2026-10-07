# Developer-account migration is paused

Oliver requested this preserved branch and worktree on October 7, 2026. Do not resume migration implementation, Apple support follow-up, account changes, packaging, merging or release work until Oliver explicitly resumes it. Keep this branch and worktree available.

- Branch: `migration/paused-developer-account`
- Worktree: `/Users/oliverames/Developer/Projects/skylight-bridge-migration-paused`
- Preserved source: `7812080d8f69ac8be35c4f122f27d17c53eeaf53`
- Preparation commits: `87c4599` and `61536f1`
- Tracking: [GitHub #9](https://github.com/oliverames/skylight-bridge/issues/9)

The preparation contains the existing-key integrity safeguard, its standalone synthetic fixtures and the migration safeguards review. It does not establish cross-team key access, paired-client CloudKit continuity or a completed customer migration. Existing installed apps, data, Apple records, identifiers, signing settings, update feeds and the iOS repository are unchanged by this preservation step.

The preparation was already on `main`. Its source changes are being removed with a normal revert, without rewriting shared history. This branch retains the preparation and the later README and release-reporting changes. Its only additional changes document the pause.

Do not merge this branch automatically. If Oliver resumes the migration, first inspect the revert on `main` and deliberately restore the required changes on a new working branch. Merging an old branch alone does not undo a revert of commits already in shared history. Preserve subsequent unrelated changes and complete the original-key and paired-client continuity work before any release.
