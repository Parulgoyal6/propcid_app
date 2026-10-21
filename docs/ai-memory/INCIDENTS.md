# Incidents

Structured incident log for this project, initialized 2026-09-26 by a repository documentation/memory audit. No past incidents are fabricated here — this audit found no verifiable record of a formally-logged production incident (with symptoms/root-cause/fix/verification detail) in the existing repository documentation to migrate in. Historical bug fixes that ARE verifiable from code comments and tests are instead recorded in `DECISIONS.md` and `KNOWN_ISSUES.md`, since they read as resolved defects with an in-code rationale rather than dated incident reports.

Future significant production bugs should be logged here using the template below. Do not mark a status as RESOLVED without evidence (a merged fix + a regression test, at minimum).

---

## Template

```
## YYYY-MM-DD — Short title

Status: OPEN | INVESTIGATING | MITIGATED | RESOLVED
Severity: SEV1 | SEV2 | SEV3 | SEV4
Affected area: (cross-reference HIGH_RISK_AREAS.md if applicable)

### Symptoms

### User impact

### Root cause

### Affected files/components

### Fix

### Verification

### Regression protection
(which test file(s) now pin this, if any)

### Git reference
(commit hash / PR)

### Prevention / future notes
```
