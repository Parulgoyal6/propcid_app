# Phase 0 Impact Report — Model + read service

**Date:** 2026-08-05
**Phase class:** 🟢 FE-ONLY
**Risk:** Low — **zero existing files modified**
**Status:** complete, verified, awaiting approval

---

## 1 · Files created

| Path | LOC | Purpose |
|---|---|---|
| `lib/models/user_profile.dart` | 554 | Read model over one `profiles` row + `ProfileSocialMedia` typed view over the jsonb column. Encodes the portal's display fallback chains with JS-truthiness semantics. |
| `lib/services/user_profile_service.dart` | 160 | `fetchOwn` (delegates to `AuthService.getUserProfile`), `fetchPublic` (auth-dependent column list), `fetchProfilesByIds` (rater/viewer name resolution). |
| `test/user_profile_model_test.dart` | 537 | 43 tests: column-list parity, tolerant parsing, fallback chains, `isVerified`, dual social-key spellings, role helpers, initials. |

**Total: 1 251 lines, 3 new files.**

## 2 · Files modified

**None.** No existing `.dart` file was touched. Nothing imports the new files yet, so no existing
widget, provider or service can behave differently. Phase 0 is dead code until Phase 1 wires it in.

Documentation added/updated in the same session (not source code):
`docs/REGRESSION_PROTECTION_CHECKLIST.md`, `docs/IMPACT_ANALYSIS.md`,
`docs/SAFE_IMPLEMENTATION_RULES.md` (new), plus corrections to
`docs/USER_PROFILE_MIGRATION_PLAN.md` and `docs/PUBLIC_PROFILE_UI_SPEC.md` (see §7).

## 3 · Files deliberately NOT modified

| File | Why left alone |
|---|---|
| `lib/services/auth_service.dart` | `getUserProfile()` is **called**, not changed. Its null-on-error contract is depended on by several callers (Checklist §1.12) |
| `lib/providers/auth_provider.dart` | `profileRow` is consumed read-only |
| `lib/core/utils/profile_completion.dart` | consumed read-only in Phase 3; `UserProfile.raw` exists precisely so it can keep taking a `Map` |
| `lib/models/profile_stats.dart` | unrelated stats value object |
| `lib/services/profile_service.dart` | carries defects R1/R2; out of bounds (Rules R5) |
| `test/phase8_social_test.dart` | carries a pre-existing failure; fixing needs approval (§5) |

## 4 · Backend interaction

**Reads only. No writes, no schema/RLS/RPC/function/bucket contact.**

| Operation | Table / columns | Permission relied on |
|---|---|---|
| `fetchOwn` | via `AuthService.getUserProfile` → `profiles.select()` `.eq(user_id)` `.maybeSingle()` | existing own-profile read, unchanged |
| `fetchPublic` (anon) | `profiles` — 31 named columns | `anon` column GRANT (`20270311000000` + `20270312000000`) |
| `fetchPublic` (signed in) | those 31 + `phone, email, mobile_number` | `authenticated` table-level GRANT |
| `fetchProfilesByIds` | `profiles` — `user_id, display_name, avatar_url, user_type, username` | all five in the `anon` grant |

No new query shape: every one of these already runs from the portal against the same project with the
same keys.

## 5 · Verification

| Gate | Baseline | After Phase 0 | Result |
|---|---|---|---|
| `flutter analyze` | 447 issues (0 errors, 0 warnings) | **447 issues** | ✅ **0 new** — issue set diffed as byte-identical; **0 issues in the new files** |
| `flutter test` | 540 pass / 1 fail | **583 pass / 1 fail** | ✅ **+43 pass, 0 new failures** |
| `flutter build apk --debug` | — | `√ Built build\app\outputs\flutter-apk\app-debug.apk` | ✅ PASS |
| `git status --short` | 176 entries, 69 modified | 179 entries, **69 modified** | ✅ only the 3 declared new files added; **no tracked file modified** |

Artefacts: `baseline-analyze.txt`, `baseline-status.txt`, `phase0-analyze.txt`, `phase0-status.txt`.

### The one pre-existing failure

`phase8_social_test.dart` → `SocialAnalytics.fromLogs windows are relative to now` fails **before and
after** Phase 0, identically.

Cause: the `_log()` helper hardcodes `createdAt = '2026-08-03T10:00:00Z'` (line 54) and line 189
asserts `analytics.today == 1`, but `SocialAnalytics` derives its windows from `DateTime.now()`. The
assertion only ever held on 2026-08-03. A time-bomb, unrelated to this migration.

Proposed one-line fix — **needs approval**, as it edits an existing file:
`createdAt = DateTime.now().toIso8601String()`.

### Regression checklist

Per Checklist §18, Phase 0's scope is **§16 only** — no existing file was touched.

| Item | Result |
|---|---|
| 16.1 analyze — no new issues | ✅ |
| 16.2 test — no new failures | ✅ |
| 16.3 debug build | ✅ |
| 16.8 provider trees in sync | ✅ neither touched |
| 16.9 only declared files changed | ✅ |
| 16.10 no `supabase/`, `pubspec`, manifest change | ✅ |
| 16.12 theme tokens unchanged | ✅ not touched |
| §1.12 `getUserProfile` null-on-error preserved | ✅ by inspection — called, never redefined |
| 16.4–16.7, 16.11 (runtime) | not applicable — no code path reaches the new files yet |

## 6 · Deviations from the plan

### 6.1 `background_image_url` added to the public column list

The plan said "the portal's **two exact column lists**". I added one column and want this confirmed.

The portal's `publicCols` (UserProfile.tsx:331) omits `background_image_url`, yet its own cover hero
renders `profile.background_image_url` (UserProfile.tsx:964). For any non-self viewer the value is
therefore always absent and the hardcoded Unsplash fallback always wins — **on the web, a visitor
never sees anyone's cover photo.** That reads as an oversight, not a decision.

- The column **is** granted to `anon` (`20270311000000`, grant list line 26), so requesting it is safe
  and cannot fail the query.
- Without it, the redesigned cover hero (Spec S1) could never display a real cover.
- The deviation is documented in the source and asserted in the test, which pins
  `publicColumns == portalPublicCols + ', background_image_url'` — so drift in either direction fails.

**If you would rather match the portal exactly (bug included), say so and I will remove it.**

### 6.2 `maybeSingle()` instead of `single()` + `PGRST116` handling

The portal uses `.single()` and the plan's Phase 0 note mentioned tolerating `PGRST116`.
`maybeSingle()` returns null for "no rows" instead of throwing, which is both simpler and the
convention `AuthService.getUserProfile` already uses. Same observable outcome, no error-code string
matching.

### 6.3 `fromMap` rather than `fromSupabase`

`ArticleSummary` uses `fromSupabase`. `fromMap` is used here because the map does not have to come
from a query — `AuthProvider.profileRow` already holds one, and Phase 1 may build a model from it
without a round-trip. Documented in the file header.

## 7 · Corrections made to already-approved documents

### 7.1 🔴 R3 was wrong — the follower columns ARE readable by `anon`

Revision 2 of the migration plan claimed `fb_followers_count`, `ig_followers_count`,
`ig_follows_count`, `ig_media_count` and `social_followers_synced_at` were missing from the `anon`
grant, and both documents gated the Social Reach section behind sign-in on that basis.

`20270312000000_social_follower_counts.sql:74-79` grants them explicitly:

```sql
-- New columns are NOT auto-granted to anon (see 20270311000000). Grant SELECT on
-- just these public vanity counts so logged-out visitors see them too.
GRANT SELECT (
  fb_followers_count, ig_followers_count, ig_follows_count,
  ig_media_count, social_followers_synced_at
) ON public.profiles TO anon;
```

They are absent from `integrations/supabase/types.ts` — which is why the portal casts with
`(supabase as any)` — but a stale generated type is not a permission.

**Effect:** Social Reach has no auth gate; follower tiles are visible to logged-out visitors; the
portal's `publicCols` is correct as written; P8-1 loses its restriction. `email`, `phone` and
`mobile_number` remain the *only* columns withheld from `anon`, and the sole reason `fetchPublic`
needs two lists. Corrected in `USER_PROFILE_MIGRATION_PLAN.md` (R3, §Phase-1 scope, P8-1),
`PUBLIC_PROFILE_UI_SPEC.md` (S9, hierarchy diagram, visibility table) and `IMPACT_ANALYSIS.md` (P8-1).
A test pins the five columns into the anonymous list so the mistake cannot recur.

### 7.2 Test-suite baseline is not green

All three documents were written asserting "all 28 test files pass". Measured baseline is **540 pass
/ 1 fail**. The gate in each is now "no **new** failures vs. 540/1", with the failure diagnosed.

### 7.3 Analyzer baseline recorded

447 issues, all `info` (0 errors, 0 warnings) — mostly `withOpacity` deprecations. The gate is "no new
issues", so these are not this migration's to fix.

## 8 · Known issues / follow-ups

| # | Item | Owner |
|---|---|---|
| 1 | `phase8_social_test.dart` time-bomb — one-line fix awaiting approval | you |
| 2 | 🔴 R1 / R2 (placeholder avatar, wizard dropping ~17 fields) still open by design | reported |
| 3 | No safety commit exists — 69 modified / 4 deleted / 103 untracked, all uncommitted | you |
| 4 | `formatCount` promotion to a shared util deferred to Phase 1 (🟡) | pending |
| 5 | `UserProfile` has 52 typed fields; only ~30 are rendered by the spec. Deliberate — a complete model means later phases add no fields, keeping Rules R7 satisfiable | — |

## 9 · Rollback procedure

```bash
rm lib/models/user_profile.dart
rm lib/services/user_profile_service.dart
rm test/user_profile_model_test.dart
```

Nothing else to undo — no existing file was modified, so there are no hunks to revert. Optionally
also remove `docs/impact-reports/phase0-*.txt`.

**Do not use git** for this (Rules R13): the working tree holds 172 uncommitted changed paths and any
`git checkout` / `reset --hard` / `clean -fd` would destroy them.

## 10 · Approval requested

Phase 0 is complete and verified. **Stopping here as instructed — Phase 1 will not begin
automatically.**

To proceed I need:

**Decisions carried over**
- **D1** — Message button reuses `AppConstants.chatThreadScreen`? *(assumed yes)*
- **D2** — Confirm skipping the anonymous 10-second login nag and the 30-minute `tempAuth` window
- **D3** — Confirm the self-only "My Connections" tab defers to the existing `myNetworksScreen`
- **D4** — Confirm appending methods to existing Flutter **client** services is acceptable
  (Phases 2, 5, 6, 7 depend on this; the alternative is sibling files)

**New, from Phase 0**
- **D5** — Keep `background_image_url` in the public column list (§6.1), or match the portal's
  omission exactly?
- **D6** — Approve the one-line `phase8_social_test.dart` fix, or leave the baseline at 540/1?
- **D7** — Create the safety commit before Phase 1? Phase 1 modifies five existing files, so this is
  the last comfortable moment to establish a real rollback point.

**Phase 1 preview** — ~16 new files; 5 existing files modified additively
(`app_constants.dart` +1 constant, `app.dart` +1 route case, `main.dart` +1 provider,
`test/widget_test.dart` +1 provider, `profile_role.dart` +2 functions). Risk: Medium. Every edit will
be explained before it is made, per Rules R8.
