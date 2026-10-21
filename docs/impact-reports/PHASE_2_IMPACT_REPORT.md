# Phase 2 Impact Report — Profile-view recording

**Date:** 2026-08-05
**Phase class:** 🟢 FE-ONLY
**Risk:** Low–Medium (one appended method on a pre-existing service)
**Status:** complete, verified, awaiting approval

---

## 1 · Files created

| Path | Tests | Purpose |
|---|---|---|
| `test/profile_view_recording_test.dart` | 13 | Every branch the client controls: the three no-ops, the per-pair guard, release-on-error, and a guard that `getCount` was not refactored |

## 2 · Files modified — 2

### 2.1 `lib/services/profile_view_service.dart` — appended (R8 justification given before editing)

Added: `_recorded` (static `Set<String>`), `recordView({viewerId, profileUserId})`,
`resetRecordedGuard()` (`@visibleForTesting`). Replaced the stale comment block.

**Pre-edit content of the replaced comment, verbatim:**

```dart
  // NOTE: recording a view (the `record_profile_view` RPC) is deliberately not
  // implemented here. Blueprint §9 scopes it to "when a Flutter user opens
  // someone else's profile", and the app has no other-user profile screen yet
  // — calling it from the user's own Profile screen would be wrong (React
  // no-ops self-views, server-side too).
```

That note's stated reason — no other-user profile screen — expired when
`PublicProfileScreen` shipped in Phase 1.

**`getCount()` is untouched.** Same signature, same body, same exact-head-count behaviour. Its only
caller, `ProfileProvider` (the own-profile Profile Views tile, §10.3), is unaffected. A test asserts
the signature still exists so a future refactor of the method it now sits beside cannot go unnoticed.

**D4 compliance:** ✅ no existing method changed, no existing behaviour changed, no existing caller affected.

### 2.2 `lib/providers/public_profile_provider.dart` — Stage 1 file

`+ import 'dart:async'`, `+ import '../services/profile_view_service.dart'`,
`+ ProfileViewService? profileViewService` constructor param, `+ _profileViewService` field, and the
`unawaited(...)` call in `load()`.

## 3 · Files deliberately NOT modified

| File | Why |
|---|---|
| `lib/providers/profile_provider.dart` | Owns the own-profile stats; recording is not its concern |
| `lib/screens/profile/profile_screen.dart` | A self-view must never record — the RPC no-ops it anyway |
| `app.dart`, `app_constants.dart`, `main.dart`, `test/widget_test.dart` | No route or provider added |
| Anything in `messaging/` | Untouched since Stage 2A |

## 4 · Backend interaction

Calls the existing `record_profile_view(p_profile_user_id uuid)` RPC. **Nothing defined, altered or
migrated.** `EXECUTE` is granted to `authenticated` and revoked from `anon`/PUBLIC
(`20270316010000_profile_views.sql:170-172`), which is exactly the audience the client-side guard
allows through.

The RPC does all the real work: upserts `profile_views`, increments `view_count`, and inserts the
`profile_view` notification behind its own 30-minute cooldown. The client adds no logic the server
does not already own — it only avoids pointless round-trips.

## 5 · Deviation from the plan — the guard is in memory, not `shared_preferences`

The approved plan specified a `shared_preferences` key `profileViewed:{viewer}:{owner}`, with an
in-memory alternative noted. **I chose the in-memory alternative**, as a `static final Set<String>`.

`shared_preferences` persists across app launches. The portal's guard is `sessionStorage`, which dies
with the browser tab. Using persistent storage would mean a user who viewed a profile once would
**never record another view for that pair** — `view_count` frozen at 1 forever, and the owner stops
hearing about repeat interest. That is not a faithful port with a caveat; it is a worse product than
the portal.

A process-lifetime `Set` is the closest equivalent Flutter offers to a browser session, needs no
async read on the render path, and resets on app restart. The trade-off — a long-running app session
suppresses longer than a browser tab typically would — is bounded by the RPC's own 30-minute
notification cooldown, so the owner's notifications are unaffected either way.

## 6 · Design notes

- **Fire-and-forget.** `unawaited(...)`, outside the `Future.wait`. An RPC on the critical path would
  sit between the user and their first frame for no benefit.
- **Fired only after the profile resolves**, so a 404 or a failed identity read never records a view.
- **The claim is taken before the `await`,** so two near-simultaneous loads cannot both fire.
- **Released in the `catch`,** mirroring the portal removing its `sessionStorage` key on error. Without
  this, one transient failure suppresses that pair for the whole session — invisible in production,
  and the single most valuable thing in this phase's test file.
- **Never throws.** A failed recording must not affect a screen whose other eleven sections are fine.

## 7 · Verification

| Gate | Baseline | Phase 1 end | Phase 2 | Result |
|---|---|---|---|---|
| `flutter analyze` | 447 (0 err) | 447 | **447** | ✅ 0 new; **no issues in either modified file** |
| `flutter test` | 540 / 1 fail | 668 / 1 | **681 / 1** | ✅ **+13, no new failures** |
| `flutter build apk --debug` | — | ✓ | **✓ built** | ✅ PASS |
| `git status --short` | 69 M | 69 M | **69 M**, +1 new file | ✅ only the declared test file added |

The single failure remains the pre-existing `phase8_social_test.dart` time-bomb (D6).

### Regression checklist — Phase 2 scope (§18)

| Item | Result |
|---|---|
| §10.3 `ProfileStatsRow` / Profile Views tile | ✅ `getCount()` byte-identical; signature asserted by test |
| §10.4 `ProfileProvider.load/refresh` | ✅ untouched |
| §11 Notifications | ✅ the RPC inserts `profile_view` server-side; no client path changed |
| §5.1 pull-to-refresh does not re-fire | ✅ guard suppresses within the session |
| §14 navigation | ✅ no route or provider registration change |
| §16.1–16.3, 16.9, 16.10, 16.12 | ✅ |
| §16.4–16.7, 16.11 (runtime) | ⚠️ unexercised — no device (V1) |

## 8 · Not covered by tests

**The suppression of a *successful* repeat call cannot be asserted here.** Every RPC attempt fails
against the loopback URL, and a failure deliberately releases the guard — so the state where a claim
survives is unreachable without a live Supabase project. Verifying "one profile is recorded once per
app session, and `view_count` increments on a later session" belongs with the Android device
validation tracked as a release requirement (V1).

Stated plainly because it is the one behaviour a reader would reasonably assume these 13 tests cover.

## 9 · Rollback

```bash
rm test/profile_view_recording_test.dart
```

Then remove from `profile_view_service.dart`: `_recorded`, `recordView`, `resetRecordedGuard`, and the
replacement comment block — restoring the original quoted verbatim in §2.1. And from
`public_profile_provider.dart`: the two imports, the constructor param, the field, and the
`unawaited(...)` call.

**Do not use git** — the tree holds ~180 uncommitted paths and both modified files were already dirty.

## 10 · Approval requested

Phase 2 is complete. **Stopping — Phase 3 will not begin automatically.**

Also delivered this turn: `docs/FEATURE_COMPLETION_CHECKLIST.md` — 106 line items, ✅ 44 / 🟡 38 /
🔴 7 / ❌ 17.

For Phase 3 (Edit Profile — the largest remaining phase) I need:

- **P3-1 — 🟡 A-1.** Repoint `profile_screen.dart`'s `_editProfile()` from the registration wizards to
  the new edit screen (Option A), or leave it and add a separate "Edit details" row (Option B)?
  This is the only pre-existing-screen edit Phase 3 needs, and it is the sharpest edge in the whole
  plan: four independent callers reach those wizard routes.
- **P3-2.** Defects R1/R2 (checklist 9.7 and 11.7) remain blocked. Until they are fixed, Phase 3's
  edit screen will show fields **empty** for users who filled them in during registration, and
  completion percentages will under-report. Do you want R2 addressed before or alongside Phase 3?
  It is the highest-value blocked item on the board.
