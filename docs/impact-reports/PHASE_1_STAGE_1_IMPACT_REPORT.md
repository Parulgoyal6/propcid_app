# Phase 1 · Stage 1 Impact Report — Public Profile screen

**Date:** 2026-08-05
**Phase class:** 🟢 FE-ONLY
**Risk:** Medium (two additive edits to app-wide files)
**Status:** complete, verified, awaiting approval

Scope as approved: the screen, provider, services, widgets and route only. **No entry
point is wired** — Search, Property Details, Messages, Network and Reviews are untouched and
come in Stage 2, one screen at a time.

---

## 1 · Files created — 17 files, 5 479 lines

### Core / shared (2)
| Path | LOC | Purpose |
|---|---|---|
| `lib/core/utils/number_format.dart` | 54 | `formatCompactCount` (2.3K / 1.2M) and `formatRating` (1 dp or em dash) |
| `lib/core/widgets/glass_circle_icon_button.dart` | 120 | Frosted 38 dp circular action, cross-fading to a solid glyph as the bar pins |

### Models (1)
| Path | LOC | Purpose |
|---|---|---|
| `lib/models/profile_review.dart` | 240 | `RatingSummary`, `ProfileReview`, `RatingBreakdown` — the customer/broker/total split and the 5-star histogram, all folded from one fetch |

### Services (2)
| Path | LOC | Purpose |
|---|---|---|
| `lib/services/profile_connection_service.dart` | 126 | **Read-only** companion: two-table connection-status lookup |
| `lib/services/profile_content_service.dart` | 166 | Listings / projects / ratings with the portal's exact filters |

### Provider (1)
| Path | LOC | Purpose |
|---|---|---|
| `lib/providers/public_profile_provider.dart` | 286 | Four independently-loading sections; screen-scoped |

### Screen + widgets (9)
| Path | LOC |
|---|---|
| `lib/screens/profile/public_profile_screen.dart` | 758 |
| `lib/screens/profile/public_profile_role.dart` | 71 |
| `lib/screens/profile/widgets/public_profile_cover_header.dart` | 336 |
| `lib/screens/profile/widgets/public_profile_identity.dart` | 544 |
| `lib/screens/profile/widgets/public_profile_stats.dart` | 255 |
| `lib/screens/profile/widgets/public_profile_info_cards.dart` | 865 |
| `lib/screens/profile/widgets/public_profile_content_sections.dart` | 772 |
| `lib/screens/profile/widgets/public_profile_sticky_bar.dart` | 286 |
| `lib/screens/profile/widgets/public_profile_skeleton.dart` | 154 |

### Tests (2)
| Path | LOC | Tests |
|---|---|---|
| `test/number_format_test.dart` | 140 | 22 — incl. **12 live-widget parity assertions** against `ProfileStatsRow` |
| `test/public_profile_parity_test.dart` | 306 | 24 — contact gate, role branches, rating split, histogram, review fallbacks |

## 2 · Files modified — 2, exactly as approved

### `lib/core/constants/app_constants.dart` — +5 lines (one constant + doc)

```dart
  /// Any user's public profile, pushed with `{'userId': ...}` and optionally
  /// `{'avatarHeroTag': ...}` so the tapped avatar can fly into place.
  ///
  /// Distinct from [profileScreen], which is the signed-in user's own profile tab.
  static const String publicProfileScreen = '/public-profile';
```

Inserted immediately above `myNetworksScreen` (now line 135). **Nothing existing edited.**
*Pre-edit state:* the file had no `publicProfileScreen` symbol; verified free across `lib/` and `test/`.

### `lib/app.dart` — +2 hunks

**(a) import, after `profile_screen.dart`:**
```dart
import 'screens/profile/public_profile_screen.dart';
```
*Pre-edit line 18 read:* `import 'screens/profile/profile_screen.dart';` and nothing followed it on line 19.

**(b) one `case`, inserted between `case '/profile':` and `case AppConstants.articleEditorScreen:` (now lines 100–110):**
```dart
          case AppConstants.publicProfileScreen:
            final profileArgs = settings.arguments as Map<String, dynamic>?;
            return PremiumPageRoute(
              settings: settings,
              builder: (context) => PublicProfileScreen(
                userId: profileArgs?['userId'] as String? ?? '',
                avatarHeroTag: profileArgs?['avatarHeroTag'] as String?,
              ),
            );
```
*Pre-edit state:* `case '/profile':`'s closing `);` was immediately followed by
`case AppConstants.articleEditorScreen:`. No existing case, and the default
fall-through to `HomeScreen`, was altered.

A blank/missing `userId` deliberately still resolves — the screen shows its
"Profile not available" state rather than falling through to Home, which would look like a
navigation bug.

> Both files were **already modified** in the working tree before this phase (they are 2 of the
> 69 pre-existing `M` entries), so the modified-file count is unchanged at 69. Rollback must
> therefore remove *these hunks specifically*, not revert the files.

## 3 · Files deliberately NOT modified

| File | Why | What was done instead |
|---|---|---|
| `lib/main.dart`, `test/widget_test.dart` | Approved exclusion | Provider is screen-scoped, following `ProfileScreen` |
| `lib/screens/profile/profile_role.dart` | Approved exclusion | `public_profile_role.dart` **exports** `roleColor`/`roleLabel` from it — one definition, no copy |
| `lib/screens/profile/widgets/profile_stats_row.dart` | D4 (would move a method and change its caller) | New `number_format.dart`, with a live-widget parity test |
| `lib/services/network_service.dart` | D4 + not in approved scope | `getAcceptedCount()` is **called** unchanged; the status read went to a companion service |
| `lib/services/ratings_service.dart` | D4 | Ratings fetched by `ProfileContentService`; `getRatingSummary()` untouched and still the own-profile path |
| `lib/services/property_service.dart`, `builder_project_service.dart` | D4 | Their **model factories** are reused; the queries are new because neither applies the portal's status filters |
| `lib/services/messaging_service.dart` | D1 | `startConversation()` called unchanged |
| `lib/screens/profile/widgets/profile_cover_header.dart` | Not in scope | New SliverAppBar header borrows its geometry (172/88/42/28) without touching it |
| `lib/services/profile_service.dart` | R1/R2 defects out of bounds | Untouched |

## 4 · Backend interaction — reads only

| Query | Table / columns | Permission |
|---|---|---|
| Identity (self) | `AuthService.getUserProfile` → `profiles.select()` | existing own-profile read |
| Identity (other) | `profiles` — Phase 0's two column lists | `anon` / `authenticated` grants |
| Rater names | `profiles` — 5 summary columns | in the `anon` grant |
| Listings | `properties` — `status in ('active','sold')`, `created_at desc` | as the portal reads |
| Projects | `builder_projects` — `status='active'` (+ `approval_status='approved'` for visitors) | as the portal reads |
| Ratings | `user_ratings` — `id, rating, review, created_at, rater_id` | `SELECT USING (true)` |
| Connection | `builder_networks`, `builder_network_invitations` | symmetric `FOR ALL`/SELECT policies |
| Connections count | `NetworkService.getAcceptedCount()` | unchanged existing call |
| Message | `start_conversation` RPC via `MessagingService` | unchanged existing call |

**No writes. No schema, RLS, RPC, function, bucket, migration, manifest, pubspec or theme-token
change.** No new package: `photo_view`, `url_launcher`, `shimmer`, `flutter_animate`,
`cached_network_image` and `share_plus` were all already declared.

## 5 · Verification

| Gate | Baseline | Phase 0 | Stage 1 | Result |
|---|---|---|---|---|
| `flutter analyze` | 447 (0 err) | 447 | **447** | ✅ **0 new**; grep for every new/modified filename returns **no issues** |
| `flutter test` | 540 / 1 fail | 583 / 1 | **629 / 1** | ✅ **+46, no new failures** |
| `flutter build apk --debug` | — | ✓ | **✓ built** | ✅ PASS |
| `git status --short` | 69 M | 69 M | **69 M**, +10 new entries | ✅ only declared files |

Artefacts: `phase1-analyze.txt`, `phase1-status.txt`.

The 7 new widget files do not appear individually in `git status` because
`?? lib/screens/profile/widgets/` was already an untracked **directory** entry at baseline —
git collapses new files inside it. All 7 verified present on disk.

The single failure remains `phase8_social_test.dart` → "windows are relative to now", the
pre-existing time-bomb diagnosed in the Regression Checklist §0. Unchanged, untouched.

### Regression checklist — Phase 1 scope (§18)

| Item | Result |
|---|---|
| §14.1 every existing route resolves | ✅ additive `case`; no existing case or string altered |
| §14.2 unknown route → `HomeScreen` | ✅ default untouched |
| §14.3 `PremiumPageRoute` 350 ms | ✅ reused, not modified |
| §14.4/14.5 bottom nav + `NavigationProvider` | ✅ screen never calls `setIndex()` — it is pushed, not a tab |
| §14.10 provider trees in sync | ✅ neither touched |
| §10.x own Profile screen | ✅ untouched; `profile_role.dart` exported, not edited |
| §10.3 `ProfileStatsRow` | ✅ untouched **and** now covered by 12 parity assertions |
| §3/§4/§6 entry-point hosts | ✅ untouched by design (Stage 2) |
| §13 theme tokens | ✅ no token file edited; no new tokens |
| §16.1–16.3, 16.9, 16.10, 16.12 | ✅ |
| §16.4–16.7, 16.11 (runtime) | ⚠️ **not exercised** — see §6.1 |

## 6 · Deviations and open items

### 6.1 The screen has no entry point — verification is static
This was the approved Stage 1/2 split, and the consequence is that the screen has **not been
run on a device**. Analyze, the widget-level parity tests and the build all pass, but no
human has seen it render. Layout risks that only appear at runtime — the avatar's
`Positioned(top: -46)` overhang inside a `Stack(clipBehavior: Clip.none)`, the
`SliverAppBar` collapse maths, `IntrinsicHeight` inside the stat card — are unverified.

Recommended first Stage 2 action: wire **one** low-risk entry point (a Search result card),
then walk §16.4–16.7 and §16.11 on a device before wiring the rest.

### 6.2 Inert-by-design controls
Rendered in their correct state, with `onTap: null` so they read as disabled rather than
offering an affordance that silently does nothing:
- **Connect / Accept / Cancel** — Phase 6 owns the writes.
- **Write a review** — Phase 5 owns the sheet.
- **View all listings / See all reviews** — the list screens are Stage 2; the buttons are
  *hidden*, not disabled, so there is no dead end.
- **Edit Profile on a self-view** — Phase 3 owns the edit screen, so a self-view shows
  Share alone rather than a button leading nowhere.

### 6.3 Builder project rows do not navigate
There is no project-detail route in this app. Tapping a project shows a `SnackBar` with its
title instead of pushing a route that would fall through to Home. Wiring belongs with
whichever phase introduces that screen. **Flagging rather than inventing a destination.**

### 6.4 `ProfileContentService` re-queries rather than reusing two services
`PropertyService.getPropertiesByUser()` applies no status filter and `PropertyModel` carries no
`status` field, so its result cannot be narrowed to `status in ('active','sold')` afterwards —
a profile would show strangers your drafts. `BuilderProjectService.getProjects()` likewise
applies neither `status='active'` nor the visitor-only `approval_status='approved'`, and
`BuilderProjectModel` has no `approval_status` to filter on. Both were inspected first; the
model factories are reused, only the queries are new.

### 6.5 `SectionHeader` carries its own padding
It bakes in `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`. The Listings and Reviews
sections are therefore placed with **no** outer horizontal padding and pad their own bodies —
otherwise the header would sit at 32 dp while content sat at 16.

### 6.6 Two of my own errors, corrected during the build
Recorded because they are the kind of thing that would otherwise resurface:
- `formatRating(4.55)` was asserted as `'4.6'`. It is `'4.5'` — 4.55 is not exactly
  representable in binary. **My expectation was wrong, not the code.** The test now uses
  unambiguous values and documents why exact halves are not pinned.
- `SizeTransition.axisAlignment` is deprecated in this SDK and would have added a *new*
  analyzer issue, breaching the no-new-issues gate. Replaced with `alignment`.

### 6.7 Accessibility contrast note carried forward
The connected state uses a **tinted fill with a green label**, not white-on-green: white on
`AppColors.success` is 2.3:1 and fails WCAG AA. Documented in the widget.

## 7 · Known issues / follow-ups

| # | Item |
|---|---|
| 1 | Screen unverified on a device (§6.1) — highest-priority follow-up |
| 2 | Project rows have no destination (§6.3) |
| 3 | `phase8_social_test.dart` time-bomb still failing by decision (D6) |
| 4 | No safety commit exists — 69 modified / 4 deleted / 113 untracked, all uncommitted. You have said the commit comes when the feature is stable; until then rollback is file-level only |
| 5 | `PublicProfileScreen` accepts `avatarHeroTag` but nothing supplies one until Stage 2 |

## 8 · Rollback

```bash
# New files (17)
rm lib/core/utils/number_format.dart
rm lib/core/widgets/glass_circle_icon_button.dart
rm lib/models/profile_review.dart
rm lib/providers/public_profile_provider.dart
rm lib/services/profile_connection_service.dart
rm lib/services/profile_content_service.dart
rm lib/screens/profile/public_profile_screen.dart
rm lib/screens/profile/public_profile_role.dart
rm lib/screens/profile/widgets/public_profile_cover_header.dart
rm lib/screens/profile/widgets/public_profile_identity.dart
rm lib/screens/profile/widgets/public_profile_stats.dart
rm lib/screens/profile/widgets/public_profile_info_cards.dart
rm lib/screens/profile/widgets/public_profile_content_sections.dart
rm lib/screens/profile/widgets/public_profile_sticky_bar.dart
rm lib/screens/profile/widgets/public_profile_skeleton.dart
rm test/number_format_test.dart
rm test/public_profile_parity_test.dart
```

Then remove the three hunks quoted verbatim in §2: the constant in `app_constants.dart`, and
the import + `case` in `app.dart`.

**Do not use git.** Both edited files were already dirty before this phase, so
`git checkout lib/app.dart` would discard pre-existing uncommitted work along with my hunk.

## 9 · Approval requested

Stage 1 is complete and verified. **Stopping — Stage 2 will not begin automatically.**

For Stage 2 I need:

- **E1** Which entry point first? I recommend **Search result cards** — highest traffic, and
  a card avatar is the cleanest Hero source. Alternatives: Property Details agent card, or the
  Messages thread header.
- **E2** Confirm each entry point is its own approval (one existing screen edited per step),
  as agreed.
- **E3** Should Stage 2 also add the `UserListingsScreen` / `UserReviewsScreen` list screens so
  "View all" / "See all" stop being hidden, or defer those to a later step?
- **E4** Before or after Stage 2's first wiring, do you want a device pass on §16.4–16.7 and
  §16.11? I recommend **immediately after the first entry point**, so the screen is reachable
  and any layout issue surfaces before it is wired in eight places.
