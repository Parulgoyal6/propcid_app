# PropCid Flutter — User Profile Migration: Impact Analysis

Per-phase file inventory, justification for every edit, risk rating, regression exposure and rollback
procedure. Companion to `USER_PROFILE_MIGRATION_PLAN.md` (what/why) and
`REGRESSION_PROTECTION_CHECKLIST.md` (verification).

---

# §A · Repository state — read this before any rollback

Captured at the start of this workstream:

```
HEAD                ca41a46  "Phase 0: make listing metadata edit-safe and non-destructive"
modified (tracked)  69 files
deleted  (tracked)   4 files   (incl. lib/models/profile_model.dart)
untracked          103 paths   (incl. all of docs/, assets/, 20+ lib/ files)
```

**The working tree contains a large amount of uncommitted work** — the Search Module Phases 1–2, the
dashboard redesign, the shared component library and more. None of it is committed.

## ⚠ Consequence: git-based rollback is UNSAFE

`git checkout .`, `git reset --hard`, `git stash` and `git clean -fd` would each **destroy weeks of
uncommitted work**. None of them may be used as a rollback mechanism for any phase.

**Every rollback in this document is therefore file-level:** delete the specific new files the phase
created, and revert the specific hunks the phase added to existing files. Because every phase is
additive by design, this is always sufficient.

## Recommended mitigation (your decision, not mine to take)

Create a safety commit **before Phase 0** so a real rollback point exists:

```
git add -A && git commit -m "checkpoint: pre-User-Profile-migration working state"
```

Until that exists, the rollback procedures below are the only safe option. I have not run it —
committing 172 changed paths is your call, not a side effect of my work.

## Baseline to capture before Phase 0

| Artefact | Command | Captured value (2026-08-05) |
|---|---|---|
| Analyzer baseline | `flutter analyze > docs/impact-reports/baseline-analyze.txt` | **447 issues — 0 errors, 0 warnings, all `info`** |
| Test baseline | `flutter test` | **540 passing, 1 failing** |
| File manifest | `git status --short > docs/impact-reports/baseline-status.txt` | **176 entries** |

Both baseline files exist in `docs/impact-reports/`. The gate for every phase is *no new* issues and
*no new* failures — never "zero".

> **⚠ One test already fails at baseline.** `phase8_social_test.dart` →
> `SocialAnalytics.fromLogs windows are relative to now`. Its `_log()` helper hardcodes
> `createdAt = '2026-08-03T10:00:00Z'` (line 54) and line 189 asserts `analytics.today == 1`, but
> `SocialAnalytics` derives its windows from `DateTime.now()` — so that assertion only held on
> 2026-08-03. Pre-existing, unrelated to this migration, **not fixed** (R5). Diagnosed with a
> proposed one-line fix in the Regression Protection Checklist §0.

---

# §B · Risk rating scale

| Level | Definition |
|---|---|
| **Low** | New files only, or additive hunks in files nothing else reads at runtime. No existing code path's behaviour can change. |
| **Medium** | Edits a file that existing screens execute, but only by appending new members or new `case`/registration entries. Existing members untouched. |
| **High** | Changes the behaviour of an existing code path, or edits a file whose failure breaks an unrelated module. Requires explicit written approval. |

---

# §C · Cross-phase invariants

Applies to every phase; not repeated per phase.

| Invariant | Enforcement |
|---|---|
| No `supabase/**`, `*.sql`, migration, RLS, RPC or Edge Function change | §16.10 |
| No `pubspec.yaml` / `pubspec.lock` change — **no new packages in any phase** | §16.10 |
| No `AndroidManifest.xml` / `Info.plist` change | §16.10 |
| No `app_colors.dart` / `app_text_styles.dart` / `app_theme.dart` value change | §16.12 |
| `app_constants.dart` gains constants only; no existing value edited | code review |
| A provider added to `main.dart` is added to `test/widget_test.dart` in the same commit | §16.8 / `widget_test` |
| `flutter analyze` + `flutter test` + `flutter build apk --debug` after every phase | §0 |
| Impact Report written to `docs/impact-reports/PHASE_N_IMPACT_REPORT.md` | this doc |
| Stop for approval after every phase | — |

---

# PHASE 0 · Model + read service

**Class:** 🟢 FE-ONLY · **Risk:** **Low** · **Existing files modified: 0**

## New files

| File | Purpose | LOC est. |
|---|---|---|
| `lib/models/user_profile.dart` | `profiles` row model: tolerant `fromMap`, dual-variant `social_media` accessor, portal fallback chains | ~260 |
| `lib/services/user_profile_service.dart` | `fetchOwn` (delegates to `AuthService.getUserProfile`), `fetchPublic` (portal's exact column lists), `fetchProfilesByIds` | ~130 |
| `test/user_profile_model_test.dart` | fallback chains, both social-key variants, `isVerified`, **anon column-list byte equality** | ~200 |

## Modified files

**None.** Phase 0 touches no existing file. Nothing imports the new files yet, so no existing widget
can rebuild differently.

## Regression exposure

| Point | Assessment |
|---|---|
| `AuthService.getUserProfile()` | Called, not modified. Its null-on-error contract (§1.12) is depended upon and preserved |
| Name collision | `lib/models/profile_model.dart` was **deleted** in the working tree; `user_profile.dart` is a new name with no importers |
| `models/profile_stats.dart` | Untouched, unrelated (a stats value object) |
| Analyzer | New files could introduce lints under `flutter_lints` |
| Test suite | A new test file cannot affect the other 28 |
| Runtime | **Zero.** Dead code until Phase 1 imports it |

## Rollback

```
rm lib/models/user_profile.dart
rm lib/services/user_profile_service.dart
rm test/user_profile_model_test.dart
```

Nothing else to undo. Zero risk to uncommitted work.

---

# PHASE 1 · Public profile screen

**Class:** 🟢 FE-ONLY · **Risk:** **Medium** (touches `app.dart`, `main.dart`, `profile_role.dart`)

## New files (~16)

`lib/providers/public_profile_provider.dart` · `lib/services/profile_content_service.dart` ·
`lib/screens/profile/public_profile_screen.dart` · `lib/screens/profile/widgets/`:
`public_profile_cover_header.dart`, `public_identity_block.dart`, `rating_inline_row.dart`,
`identity_meta_strip.dart`, `trust_chip_strip.dart`, `stat_triplet_card.dart`, `about_card.dart`,
`contact_card.dart`, `profile_details_card.dart`, `social_links_row.dart`, `social_reach_card.dart`,
`listings_section.dart`, `reviews_section.dart`, `public_profile_skeleton.dart` ·
`lib/core/widgets/glass_circle_icon_button.dart` · `test/public_profile_parity_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/core/constants/app_constants.dart` | **+1 constant** `publicProfileScreen = '/public-profile'` | route names live here by convention; the alternative is a hardcoded string | Low — additive |
| `lib/app.dart` | **+1 `case`** in `onGenerateRoute` | the only place routes are registered | Medium — a malformed `case` can shadow another route or break the fall-through to `HomeScreen` |
| `lib/main.dart` | **+1 provider** registration | `PublicProfileProvider` must be above the screen | Medium — provider-tree order affects the whole app |
| `test/widget_test.dart` | **+1 provider**, mirroring `main.dart` | project convention; the trees must not drift | Low |
| `lib/screens/profile/profile_role.dart` | **+2 functions** `roleSubtitle()`, `roleBadge()` | the public profile needs a role subtitle; a second copy of role logic would be worse | Low — existing `roleColor`/`roleLabel` untouched |
| *(optional)* `lib/screens/profile/widgets/profile_stats_row.dart` | promote `formatCount` to `core/utils/number_format.dart` | prevents two drifting compact-number implementations | **Medium** — `ProfileStatsRow` is live on the existing Profile screen. 🟡 needs approval; default is to defer |

## Regression points

1. **`app.dart` route table** — verify §14.1, §14.2 (unknown-route fall-through) and §14.3.
2. **Provider tree** — an extra `ChangeNotifierProvider` in `main.dart` rebuilds `MultiProvider`'s
   subtree. Verify §16.4, §16.8.
3. **Entry points** — Phase 1 only *adds* tap targets in Search / Property Details / Messages.
   Verify §3, §4.7, §6.7 that host layouts are unchanged.
4. **`profile_role.dart`** — used by `ProfileIdentityBlock` on the live Profile screen. Verify §10.1.
5. **`formatCount` promotion (if approved)** — verify §10.3 explicitly.
6. **Nav index** — the public profile is a *pushed* screen and must **not** call
   `NavigationProvider.setIndex()`. Verify §14.4/§14.5: returning to Profile still shows index 3.
7. **Memory** — `PhotoView` + a full-resolution cover on a low-end device. Watch for jank on §16.7.

## Rollback

```
rm lib/screens/profile/public_profile_screen.dart
rm lib/screens/profile/widgets/{public_profile_cover_header,public_identity_block,rating_inline_row,identity_meta_strip,trust_chip_strip,stat_triplet_card,about_card,contact_card,profile_details_card,social_links_row,social_reach_card,listings_section,reviews_section,public_profile_skeleton}.dart
rm lib/providers/public_profile_provider.dart
rm lib/services/profile_content_service.dart
rm lib/core/widgets/glass_circle_icon_button.dart
rm test/public_profile_parity_test.dart
```

Then revert by hand: the `case` in `app.dart`, the provider in `main.dart` + `test/widget_test.dart`,
the constant in `app_constants.dart`, the two functions in `profile_role.dart`, and (if taken) the
`formatCount` promotion. **Six small hunks, each a contiguous addition** — keep the Impact Report's
line references so this is mechanical.

---

# PHASE 2 · Profile-view recording

**Class:** 🟢 FE-ONLY · **Risk:** **Low–Medium**

## New files

None. *(Optionally `test/profile_view_recording_test.dart`.)*

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/services/profile_view_service.dart` | **+1 method** `recordView()`; update the now-stale comment saying recording is "deliberately not implemented" | the RPC belongs beside `getCount()`; a second service for one method would fragment the module | **Medium** — `getCount()` feeds the live Profile screen's stat tile |
| `lib/providers/public_profile_provider.dart` | call `recordView` once per load | new file from Phase 1 | Low |

## Regression points

1. **`getCount()` must be byte-identical.** It backs §10.3. Do not reformat, re-order or "tidy" it.
2. **Fire-and-forget** — `recordView` must never be awaited on the render path, or a slow RPC stalls
   first paint.
3. **Self/anon no-op** — a self-view call is wasted work (the RPC no-ops server-side anyway).
4. **`shared_preferences` guard** — must be removed on error so a later visit retries. A permanently
   set key silently stops all recording for that pair.
5. **Notifications** — the RPC inserts the `profile_view` notification itself. Verify §11.
6. **Refresh** — pull-to-refresh must not re-fire the RPC (§5.1).

## Rollback

Delete the `recordView` method and restore the original comment; remove the provider call. One hunk
in one existing file plus one line in a Phase-1 file.

---

# PHASE 3 · Edit Profile screen

**Class:** 🟢 FE-ONLY + 🟡 A-1 · **Risk:** **Medium–High** (A-1 is the first real behaviour change)

## New files (~6)

`lib/screens/profile/edit_profile_screen.dart` · `lib/providers/edit_profile_provider.dart` ·
`lib/services/profile_write_service.dart` · `lib/core/validation/profile_validators.dart` ·
`lib/core/constants/profile_options.dart` · `test/edit_profile_parity_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/core/constants/app_constants.dart` | +1 constant | convention | Low |
| `lib/app.dart` | +1 `case` | route registration | Medium |
| `lib/main.dart` + `test/widget_test.dart` | +1 provider each | convention | Medium |
| `lib/screens/profile/profile_screen.dart` | **🟡 A-1** — `_editProfile()` repointed from the registration wizards to the new screen | today "Edit Profile" *restarts registration* for 3 of 4 roles. Without this the new screen is unreachable for exactly the roles that need it | **High** — changes existing navigation for builder/broker/influencer |

## Explicitly NOT modified

`services/profile_service.dart` (R1, R2 defects stay) · `providers/auth_provider.dart`
(`updateProfile` in-memory-only stays) · `screens/profile/actions/edit_profile_dialog.dart`
(R5 stays) · `core/utils/profile_completion.dart` (read-only).

## Regression points

1. **A-1 is the sharp edge.** First-time completion must still reach the wizards via
   `splash_screen`, `auth_post_login`, `profile_completion_coordinator` and `rbac_service` — four
   independent callers of those routes. Verify §8 and §9.6 in full.
2. **Trigger-guarded columns** — `user_role`, `is_blocked`, `approval_status`, `user_type` must be
   **absent from the payload**. `can_update_profile_fields()` reverts them *silently*, so including
   them produces a save that appears to succeed and does nothing.
3. **`social_media` merge** — a non-merging write destroys keys the portal owns. The single highest-
   consequence bug available in this migration. Test explicitly.
4. **Paired columns** — omitting either half of `website`/`website_url`,
   `bio`/`company_description`, `years_experience`/`years_of_experience`,
   `rera_number`/`license_number`, `city`/`work_city` desynchronises Flutter from the portal.
5. **Form theming** — the edit form must use ordinary `InputDecoration` so `AppTheme`'s
   `inputDecorationTheme` applies. Any borderless field needs the six-slot + `filled: false` recipe.
   Verify §13.2, §13.3.
6. **Completion %** — must be unchanged for the same row after a save (§8.5).
7. **`AuthProvider.refreshProfile()`** after save, or the UI shows stale values (§1.9).
8. **Dropdown values** — copied verbatim from `EditProfile.tsx`. An invented value writes garbage
   the portal cannot read. Same failure mode `listing_constants_parity_test` exists to prevent.

## Rollback

Delete the six new files; revert the `case`, the two provider entries, the constant. **Then restore
`_editProfile()`'s original `switch`** — capture it verbatim in the Impact Report before editing.

If A-1 is rejected, Phase 3 ships with Option B (a new "Edit details" row in the Manage list) and
`profile_screen.dart` is not touched at all, dropping this phase to **Medium**.

---

# PHASE 4 · Avatar + cover upload

**Class:** 🟢 FE-ONLY + 🟡 A-2 · **Risk:** **Medium**

## New files (~4)

`lib/services/profile_media_service.dart` ·
`lib/screens/profile/actions/{avatar_picker_sheet,cover_picker_sheet}.dart` ·
`test/profile_media_path_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/screens/profile/widgets/profile_cover_header.dart` | **🟡 A-2** — render `background_image_url` when present; owner-only camera affordance; delete the now-false comment at lines 10–13 | the cover is hard-coded to a gradient; an uploaded cover cannot display without this | **Medium** — live on the existing Profile screen |
| `lib/screens/profile/edit_profile_screen.dart` | document-upload rows | Phase-3 file | Low |

## Explicitly NOT modified

`services/profile_service.dart` — the `'placeholder_profile.jpg'` write (R1) stays. The new upload
path is self-contained. **If it looks tempting to fix while nearby, stop and report.**

## Regression points

1. **§10.2** — cover 172 / avatar 88 / overhang 42 / 28 dp bottom radii / verified tick / menu + bell
   must all survive. The gradient stays the fallback for users with no cover.
2. **Bucket + path correctness** — `avatars` for avatars and documents, `property-media` for covers,
   first path segment `auth.uid()`. A wrong path fails the storage policy with an opaque error.
3. **No `PropertyService` change** — the wizard's `property-media` upload (§5.5) must be untouched.
4. **No new package** — cropping is out of scope precisely because `image_cropper` would breach §C.
5. **`image_picker` permissions** — already configured for the wizard; verify no manifest change is
   needed (if it is, that is out of scope → report).
6. **`refreshProfile()`** after upload so the avatar updates everywhere.

## Rollback

Delete the new files; revert the `profile_cover_header.dart` hunk (capture the original 240 lines in
the Impact Report first — it is the only Phase-4 edit to live code).

---

# PHASE 5 · Ratings write path

**Class:** 🟢 FE-ONLY · **Risk:** **Medium**

## New files (~4)

`lib/screens/profile/actions/rating_sheet.dart` ·
`lib/screens/profile/widgets/{user_ratings_list,rating_summary_card}.dart` ·
`test/ratings_service_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/services/ratings_service.dart` | **+5 methods** (`fetchMyRating`, `submitRating`, `updateRating`, `fetchReviews`, `getCategorisedRatings`) | ratings queries belong together; the private `_fetchRatings` is reused | **Medium** — `getRatingSummary()` feeds the live Profile screen |
| `lib/providers/public_profile_provider.dart` | hold `myRating`, refresh after submit | Phase-1 file | Low |
| `lib/screens/profile/public_profile_screen.dart` | review CTA | Phase-1 file | Low |

## Regression points

1. **`getRatingSummary()` unchanged** — backs §10.3's Reviews tile. Its 1-dp rounding
   (`toStringAsFixed(1)`) and its `(0, 0)`-on-empty contract must not shift.
2. **`_fetchRatings` reuse** — if `getCategorisedRatings` reuses it, do not change its projection;
   the histogram needs the same rows.
3. **Insert vs update** — wrong branch throws a unique violation. `23505` = "Already rated".
4. **RLS shape** — `rater_id` must equal `auth.uid()` and must not equal `rated_user_id`; the UI must
   never offer self-rating.
5. **Histogram derived in the provider**, not in `build` (§14 performance).

## Rollback

Delete the new files; delete the five appended methods (one contiguous block); revert the two
Phase-1 file edits.

---

# PHASE 6 · Network actions

**Class:** 🟢 FE-ONLY · **Risk:** **High** — the riskiest phase in the migration

## New files (~2)

`lib/screens/profile/widgets/connect_action_button.dart` · `test/network_actions_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/services/network_service.dart` | **+4 methods** (`getConnectionStatus`, `sendConnectionRequest`, `cancelRequest`, `acceptRequest`) | connection logic belongs with the connection queries; `getAcceptedCount` and the KPI methods are reused by the hub | **High** — this file backs the entire Network module (§7) |
| `lib/providers/public_profile_provider.dart` + `public_profile_screen.dart` | wire the 4-state button | Phase-1 files | Low |

## Why High

`network_service.dart` is consumed by `NetworkHubProvider`, `NetworkSectionProvider`,
`ProfileProvider` and the four Network leaf screens. It is the one file in this migration whose
breakage takes down a module that has nothing to do with profiles — and that module has four
dedicated test files, so breakage will be loud, but it will also be broad.

## Regression points

1. **§7 in full.** All four Network leaf screens, the hub KPIs, accept/decline already in the hub.
2. **`getAcceptedCount()` byte-identical** — feeds §7.3 *and* §10.3.
3. **Upsert, not insert** — `onConflict: 'builder_id,member_id'`. An `insert` breaks re-connection
   after removal with a unique violation. This is why the portal upserts.
4. **Direction** — recipient is `builder_id`, sender is `member_id`. Reversed, the RLS check passes
   (both sides are permitted) but the *semantics* invert and the recipient sees nothing.
5. **Cancel deletes from both tables** where `status = 'pending'` — legacy invitations otherwise
   resurrect a cancelled request.
6. **Notification insert may fail** and must not fail the connection (portal parity, §11).
7. **Double-submit** — disable the button in flight, or duplicate requests/notifications.
8. **Optimistic state must revert** on failure.

## Rollback

Delete the new files; delete the four appended methods; revert the two Phase-1 file edits.
**Before editing, copy `network_service.dart` verbatim into the Impact Report** — given four
dependent screens, an exact restore matters more here than anywhere else.

---

# PHASE 7 · Settings, views list, account deletion

**Class:** 🟢 FE-ONLY + 🟡 A-4, A-5 · **Risk:** **Medium**

## New files (~4)

`lib/screens/profile/profile_views_screen.dart` · `lib/providers/profile_views_provider.dart` ·
`lib/screens/profile/account_deletion_screen.dart` · `test/profile_views_test.dart`

## Modified files

| File | Change | Why | Risk |
|---|---|---|---|
| `lib/services/profile_view_service.dart` | **+1 method** `fetchViewers()` | belongs beside `getCount()`/`recordView()` | Medium |
| `lib/screens/profile/widgets/profile_stats_row.dart` | **+1 optional** `onProfileViewsTap` | makes the tile tappable; optional so existing callers are unaffected | Low–Medium — live widget |
| `lib/screens/profile/actions/settings_sheet.dart` | **🟡 A-4** — persist `comments_enabled` + `work_city` | five toggles are silent no-ops that claim to save | **Medium** — reachable from 3 entry points (§12.4) |
| `lib/voice_agent/tools/profile_tools.dart` | **🟡 A-5** — point `delete_account` at the new screen | the tool currently has no destination | Medium — edits a registered voice tool |
| `app_constants.dart`, `app.dart`, `main.dart`, `test/widget_test.dart` | +2 constants, +2 `case`s, +1 provider ×2 | routing/provider convention | Medium |

## Regression points

1. **§12.1–12.4** — the settings sheet from Profile, Drawer **and** More sheet.
2. **§14.10** — provider trees in sync.
3. **No PostgREST embed** on `profile_views` → `profiles`; the two-query pattern is required.
4. **Realtime channel disposal** — leak on `dispose()` degrades the whole app over a session.
5. **§16.11** — the voice tool must still *register*; a malformed edit breaks
   `_registerVoiceAgentTools()` and takes the voice agent down at boot.
6. **`delete_account` naming** — the flow files a *request*; it does not delete. Do not let the tool
   description overpromise.

## Rollback

Delete the four new files; revert the appended method, the optional parameter, the settings-sheet
persistence, the voice-tool destination, and the routing/provider entries. **Seven hunks — the
widest rollback surface of any phase.** Consider splitting into 7a (views list) and 7b (settings +
deletion) so each has a narrower blast radius.

---

# PHASE 8 · Polish

**Class:** 🟡 itemised · **Risk:** **Low–Medium per item** — approve individually

| Item | Files | Risk | Regression | Rollback |
|---|---|---|---|---|
| **P8-1** Meta follower tiles | Phase-1 files only | Low | none — the five columns are granted to `anon` (`20270312000000:76-79`), so no auth branch is needed | revert one section |
| **P8-2** Visiting-card PNG | new `profile_share_card_painter.dart` + `share_profile_sheet.dart` edit | Medium | §10.10 — share sheet is live on the existing Profile screen | delete painter, revert sheet |
| **P8-3** `save-visiting-card` invoke | `profile_media_service.dart` | Medium | writes to storage via service role; **needs explicit approval** | remove the call |
| **P8-4** Verified-badge condition | `profile_cover_header.dart` | Medium | §10.2; changes who shows verified on their **own** profile | revert one condition |
| **P8-5** Delete 3 dead files | `profile_completion/{builder,broker,influencer}_profile_screen.dart` (1 134 lines) | Low | verified unreferenced — but deletion is irreversible without a commit | **requires the §A safety commit first** |

> P8-5 is the one action in this plan that cannot be file-level rolled back. Do not run it until a
> safety commit exists.

---

# §D · Risk summary

| Phase | Risk | New | Modified | Existing-behaviour changes |
|---|---|---|---|---|
| 0 | **Low** | 3 | **0** | none |
| 1 | Medium | ~16 | 5 (+1 optional) | none (additive) |
| 2 | Low–Medium | 0–1 | 2 | none |
| 3 | **Medium–High** | 6 | 5 | **1** (A-1 navigation) |
| 4 | Medium | 4 | 2 | **1** (A-2 cover render) |
| 5 | Medium | 4 | 3 | none |
| 6 | **High** | 2 | 3 | none (but highest blast radius) |
| 7 | Medium | 4 | 8 | **2** (A-4, A-5) |
| 8 | Low–Medium | 1–2 | 2–4 | **1** (P8-4) + 1 deletion |

**Most dangerous single edits, ranked:**
1. `network_service.dart` (Phase 6) — four dependent screens
2. `profile_screen.dart` `_editProfile()` (Phase 3, A-1) — four independent wizard callers
3. `settings_sheet.dart` (Phase 7, A-4) — three entry points
4. `profile_cover_header.dart` (Phase 4, A-2 / Phase 8, P8-4) — live own-profile header
5. `app.dart` / `main.dart` (Phases 1, 3, 7) — app-wide, but loudly guarded by `widget_test`

---

# §E · Impact Report template

One per phase at `docs/impact-reports/PHASE_N_IMPACT_REPORT.md`.

```markdown
# Phase N Impact Report — <title>
Date · Phase class · Risk

## 1. Files created          (path · LOC · purpose)
## 2. Files modified         (path · hunk lines · what · why · pre-edit content verbatim)
## 3. Files deliberately NOT modified   (and why)
## 4. Backend interaction    (tables/RPCs/buckets READ or WRITTEN — must match the approved plan)
## 5. Verification
   flutter analyze  → baseline N issues → now M issues → delta
   flutter test     → X/Y files passed
   flutter build apk --debug → PASS/FAIL
   git status --short → confirms only declared files changed
## 6. Regression checklist results   (§ items walked · pass/fail · notes)
## 7. Deviations from the plan       (anything done differently, and why)
## 8. Known issues / follow-ups
## 9. Rollback procedure             (exact commands + hunks for THIS phase)
## 10. Approval requested            (what the next phase needs from you)
```
