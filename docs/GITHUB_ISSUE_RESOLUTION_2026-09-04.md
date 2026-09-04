# GitHub issue resolution, September 4, 2026

Author: Oliver Ames

## Task list

- [ ] In progress: reproduce issue 4 through fresh authentication and fix confirmed login defects.
- [ ] Investigate the HTTP 422 in issue 2 and improve request diagnostics or fix the reproduced request.
- [ ] Document subscription requirements for issue 3 and verify the shipped CloudKit mitigation for issue 1.
- [ ] Complete tests and release verification, publish required updates, and reply to all four issues with evidence.

## Scope and evidence

The user authorized proceeding with all four reviewed GitHub issues. Work starts from main commit 1315545876c18e5bdfd2f138ac2b00fb77841343, following release 1.6.5. Existing production data and the CloudKit schema are not changed to reproduce failures. GitHub comments will distinguish confirmed fixes from requests for reporter confirmation. Findings and verification are recorded below as work progresses.
