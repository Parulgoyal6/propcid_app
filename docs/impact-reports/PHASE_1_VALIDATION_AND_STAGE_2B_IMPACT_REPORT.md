# Phase 1 — Layout Validation + Stage 2B (Reviews list)

**Date:** 2026-08-05
**Status:** complete, verified, awaiting approval

---

# PART 1 · Device validation — what was asked, and what was possible

## 1.1 Real device validation could not be performed

| Check | Result |
|---|---|
| `flutter devices` | Windows (desktop), Chrome (web), Edge (web) — **no Android or iOS device** |
| `flutter emulators` | *"No emulators available."* |
| `adb` | not on PATH |

Even on the desktop/web targets the screen is unreachable: the approved entry point is the Chat
Thread header, which requires a signed-in Supabase session and an existing conversation. I have no
credentials and will not attempt to obtain any. Several declared plugins
(`google_maps_flutter`, `geolocator`, `speech_to_text`, `flutter_sound`) also have no Windows
implementation, so a desktop run is not representative even if auth were solved.

**I did not perform device validation, and nothing below should be read as if I had.**

## 1.2 What I did instead

A new test file — `test/public_profile_device_validation_test.dart`, **39 tests** — renders the real
widgets at three device widths (320 / 390 / 430 dp) and at 100% and 130% text scale, using the
project's existing geometry-based overflow detector plus a creator-aware variant that names the
offending widget.

To make the screen renderable at all I added one test seam to
`lib/screens/profile/public_profile_screen.dart` — a `@visibleForTesting PublicProfileScreen.providerOverride`.
That file was created in Stage 1 and is **not a pre-existing screen**, so it is inside the approved
boundary. Without it the provider constructs services that require a live Supabase client, and none
of the layout that exists only on this screen — the avatar overhang, the sliver collapse, the sticky
bar — could be exercised.

## 1.3 Coverage against your list

| # | Item | Covered | How |
|---|---|:--:|---|
| 1 | Cover image | ✅ | gradient fallback asserted when null; populated URL renders without exception |
| 2 | Avatar overlap | ✅ | measured: 88 dp square, left inset 20, **crosses** the 172 dp cover edge, 42 dp below it, fully on screen; name begins below the avatar |
| 3 | Sliver collapse | ✅ | dragged through 5 offsets (40→600), asserting no exception and no overflow at each |
| 4 | Sticky action bar | ✅ | all four connect states at 320 dp; self view; signed-out view |
| 5 | Locked contact card | ✅ | **asserts the phone and email strings exist nowhere in the tree while locked**, and both render when unlocked; address public in both |
| 6 | Long names | ✅ | 70-char company + 48-char display name + long specialisations at 320 dp, stepped frame-by-frame |
| 7 | Different user roles | ✅ | builder / broker / influencer / individual × 3 widths = 12 cases |
| 8 | Empty states | ✅ | no listings, no projects (wording differs), no reviews, missing profile, content failure → retry not empty |
| 9 | Text scale 130% | ✅ | broker + influencer full screen at 320 dp; sticky bar separately |
| 10 | Navigation back stack | ⚠️ partial | push → pop returns to origin, asserted. Real gesture-driven back, predictive back and deep chains need hardware |
| 11 | **Performance** | ❌ **not covered** | frame timings, jank, scroll smoothness and image decode cost cannot be measured in a widget test |

## 1.4 Issues found — four real bugs, all fixed

Every one was found by the harness, not by inspection. All four are in Stage 1 code I wrote.

### Bug 1 — `_MetaCell` overflowed by 133 px
`public_profile_identity.dart` · the identity meta strip.
`Wrap` hands each child its own maxWidth, so the unconstrained `Text` inside `_MetaCell`'s Row
overflowed whenever two specialisations were present (490.8 dp of children in 358 dp at 390 dp
width). **Fix:** `Flexible` + `maxLines: 1` + ellipsis.

### Bug 2 — rating summary overflowed its fixed 96 dp column
`public_profile_content_sections.dart` · `RatingSummaryCard`.
A 32 dp numeral in a hard-coded 96 dp box. Real Poppins reaches ~93 of the 96 at 1.3× text scale —
already marginal — and the test environment's fallback font (one em per glyph) blows straight past
it. **Fix:** `FittedBox(scaleDown)`, the same guard `MetricCard` already documents for the same
reason.

### Bug 3 — skeleton chip row overflowed by 20 px at 320 dp
`public_profile_skeleton.dart` · `_ChipRowSkeleton`.
The hardest one to find: the offending `RenderFlex` reported as **DISPOSED / DEFUNCT**, because it
belonged to the skeleton after it had been swapped out. Three fixed placeholder pills total
92 + 8 + 120 + 8 + 80 = **308 dp** against 288 dp available — exactly the 20 px reported. It painted
Flutter's hatching over the loading state on any 320 dp device. **Fix:** the placeholder now scrolls
horizontally like the real `TrustChipStrip` it stands in for.

### Bug 4 — two stacking thresholds were off by a hair, at exactly 1.3×
`public_profile_info_cards.dart` (`_DetailRowView`) and `public_profile_identity.dart`
(`IdentityMetaStrip`).
Both used a strict `>` against a scaled value that lands **exactly** on the boundary at 1.3×:
`scale(13) > 17` yields 16.9, and `scale(12) > 15.6` yields 15.6. So the single text scale the spec
promised to support was the one scale that did **not** stack — and `_DetailRowView`'s Row overflowed
by 57 dp at 320 dp. **Fix:** thresholds lowered to stack from ~1.16×, plus `Flexible` on the label as
a belt-and-braces guard so the Row cannot overflow even below the stacking point. A third instance —
the "Show all details" disclosure Row — overflowed by 28 dp at 1.3× and got the same `Flexible`
treatment.

> Bug 4 is the one I would flag hardest: the code *looked* correct and the comment *claimed* 1.3×
> support. Only rendering at exactly 1.3× exposed it.

## 1.5 One error of mine in the test, corrected
My first avatar assertion used `find.text(companyName)`, which is ambiguous — the company name
legitimately renders twice, as the identity heading and as the "company" trust chip. Scoped to
`find.descendant(of: PublicIdentityBlock)`.

## 1.6 Still requires a human on hardware

1. **Performance** — frame timings during the sliver collapse, cover image decode on a low-end
   device, scroll smoothness with a long listings list.
2. **The locked→unlocked blur transition** — needs a genuinely connected thread; correctness is
   asserted, the *feel* of the 300 ms cross-fade is not.
3. **`photo_view` full-screen avatar** — gesture-driven zoom and swipe-to-dismiss.
4. **Predictive back / edge-swipe** on Android 14+ and iOS.
5. **Real cover photos** — a very light image behind the white glass buttons before the scrim
   engages.
6. **Safe-area behaviour** on a notched device: the cover bleeds under the status bar, which the test
   view (inset 0) cannot represent.
7. **`Hero`-less transition feel** from the chat header.

---

# PART 2 · Stage 2B — Reviews list

## 2.1 Files modified — 2, both created in Stage 1

| File | Change |
|---|---|
| `lib/screens/profile/widgets/public_profile_content_sections.dart` | `ReviewCard` gains optional `onTap`; `ProfileReviewsSection` gains optional `onReviewerTap`; the card is wrapped in `Semantics` + `ScaleTap` **only when a handler is supplied** |
| `lib/screens/profile/public_profile_screen.dart` | `_openReviewerProfile`, `_profileDepth`, `_kMaxProfileDepth`; passes `onReviewerTap` |

**No pre-existing screen was touched.** `app.dart`, `app_constants.dart`,
`chat_thread_screen.dart` and `messages_list_screen.dart` are all unchanged since Stage 2A.

## 2.2 Behaviour

Tapping a review card opens that author's public profile. Three guards:

- **Unresolved authors are inert.** An empty `raterId` — the "Anonymous" case — builds no
  `GestureDetector` at all, so there is no tap that does nothing.
- **Never re-opens the current profile.** `user_ratings` forbids self-rating so this cannot occur
  today, but the check is free and protects against that changing.
- **Chain depth capped at 3.** Reviewer → their reviewers → theirs again is legitimate; an unbounded
  chain leaves users unable to find their way back. Beyond the cap, a SnackBar suggests going back.

The depth rides in the route arguments rather than being measured from the navigator: Flutter exposes
no way to enumerate the stack. `popUntil` with an always-true predicate only inspects the topmost
route, so counting with it silently returns 1 — I wrote that first and caught it before running.
The value flows through `app.dart`'s existing `settings: settings` forwarding, so **no change to the
route registration was needed**.

## 2.3 Stage 2B coverage — 4 tests

| Test | Asserts |
|---|---|
| a resolved author is tappable | `ScaleTap` present, no overflow |
| no handler leaves the card inert | **no `ScaleTap` constructed** — byte-identical to the pre-2B card |
| an unresolved author gets no tap target | no gesture, handler never fires |
| tapping invokes the handler once | correct `raterId` delivered |

---

# PART 3 · Verification

| Gate | Baseline | Stage 2A | Now | Result |
|---|---|---|---|---|
| `flutter analyze` | 447 (0 err) | 447 | **447** | ✅ 0 new — **no issues in any new or modified file** |
| `flutter test` | 540 / 1 fail | 629 / 1 | **668 / 1** | ✅ **+39, no new failures** |
| `flutter build apk --debug` | — | ✓ | **✓ built** | ✅ PASS |
| `git status --short` | 69 M | 69 M | **69 M**, +1 new file | ✅ only the declared test file added |

The single failure is still `phase8_social_test.dart` → "windows are relative to now", the
pre-existing time-bomb left unchanged per D6.

> During this work I briefly introduced a 448th issue — my test file used the deprecated
> `renderViewElement` that the shared helper still uses. A new file must not add a new issue, so it
> now uses `rootElement`. Back to 447.

## Regression checklist

| Item | Result |
|---|---|
| §6 Messages | ✅ untouched since Stage 2A |
| §10 own Profile screen | ✅ untouched |
| §13 theme tokens | ✅ unchanged |
| §14 navigation | ✅ no route table change; depth rides in existing args |
| §16.1–16.3, 16.9, 16.10, 16.12 | ✅ |
| §16.4–16.7, 16.11 (runtime) | ⚠️ still unexercised — no device |

---

# PART 4 · Rollback

**Validation:** `rm test/public_profile_device_validation_test.dart`, and revert the
`providerOverride` seam in `public_profile_screen.dart`.

**The four bug fixes** are in `public_profile_identity.dart` (×3: `_MetaCell` Flexible, the
`RatingInlineRow` Flexible, the meta-strip threshold), `public_profile_content_sections.dart`
(FittedBox), `public_profile_info_cards.dart` (×2: disclosure Flexible, `_DetailRowView` threshold +
Flexible) and `public_profile_skeleton.dart` (scrollable chip row). **I would not revert these** —
each fixes a visible overflow.

**Stage 2B:** revert `onTap`/`onReviewerTap` in `public_profile_content_sections.dart` and the three
members in `public_profile_screen.dart`.

Every file involved was created in Stage 1 or 2B. **No pre-existing file needs reverting.**
Do not use git — the tree still holds ~180 uncommitted paths.

---

# PART 5 · Approval requested

Validation and Stage 2B are complete. **Stopping.**

What I need from you:

- **V1 — Device validation is outstanding and I cannot do it.** It needs someone with a device and
  an account. §1.6 lists the seven items, ordered. Performance in particular is entirely unverified.
- **V2 — Was the `providerOverride` test seam acceptable?** It is `@visibleForTesting`, in a Stage 1
  file, and nothing in production passes it — but it is a production-file change made to enable
  testing, so I want it on the record rather than assumed.
- **V3 — The four bug fixes** are behaviour changes to Stage 1 code, made under "fix only issues
  found during validation". Please confirm you consider overflow fixes to be in scope.
- **V4 — Next?** The audit's remaining candidates all still need your decisions: the
  conversation-tile avatar (#3, a UX re-point), and a creator id on `ReelModel` (#5, a model change).
  Phases 2–7 of the migration plan are also still unstarted.
