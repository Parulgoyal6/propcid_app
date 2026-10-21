# Public Profile — Entry Point Audit

Every surface in the Flutter app that displays a user, assessed against R19 (entry-point wiring adds
navigation and nothing else).

**Method.** `grep` for `avatar`/`Avatar` and `displayName`/`display_name` across `lib/screens/` and
`lib/widgets/`, then each hit read to establish: is a user actually shown, is their id reachable,
and does the element already carry a gesture. Findings are cited by file and line so each claim is
checkable.

**Verdict summary — 16 surfaces**

| Verdict | Count |
|---|---|
| ✅ Wired (Stage 2A) | 1 |
| ✅ Safe to wire, no UX decision needed | 1 |
| ⚠️ Needs a UX decision — element sits inside an existing gesture | 2 |
| 🔴 Blocked — no user id reachable | 3 |
| 🔴 Blocked — nothing displayed to tap | 3 |
| ➖ Own profile / not another user | 6 |

---

## The matrix

| # | Screen / widget | Avatar | Name | User ID available | Existing gesture on the element | Safe to add profile nav | Requires UX redesign |
|---|---|:--:|:--:|---|---|:--:|:--:|
| 1 | **Chat thread header** `messaging/chat_thread_screen.dart:270-317` | ✅ | ✅ | ✅ `participantUserId`, threaded from `ConversationParticipant.userId` | **None** — back button only, separate widget | ✅ **WIRED (2A)** | ❌ |
| 2 | **Public Profile reviews list** `profile/widgets/public_profile_content_sections.dart` (`ReviewCard`) | ✅ | ✅ | ✅ `ProfileReview.raterId` | **None** — card is inert | ✅ **YES** | ❌ |
| 3 | **Conversation tile** `messaging/widgets/conversation_tile.dart:41-55` | ✅ | ✅ | ✅ `participant?.userId` | **Whole row** `ScaleTap(onTap)` → opens the thread | ⚠️ **No** | ✅ decision |
| 4 | **New chat sheet row** `messaging/widgets/new_chat_sheet.dart:198-214` | ✅ | ✅ | ✅ `person.userId` | **Whole row** `ScaleTap` → pops with the selected person | ⚠️ **No** | ✅ decision |
| 5 | **Reel info panel** `reels/widgets/reel_info_panel.dart:47-71` | ✅ | ✅ `reel.builderName` | 🔴 **No** — `ReelModel` carries `builderName`, `builderAvatarUrl`, `builderPhone` but **no builder/user id** (`models/reel_model.dart:42-45`) | None on the avatar/name row | 🔴 **No** | model + query |
| 6 | **Property Details — builder name** `property_detail/property_detail_screen.dart:999` | ❌ | ✅ text | ⚠️ **Mismatched** — `PropertyModel.userId` is the *poster*; `builderName` maps to the denormalised `properties.builder_name` (`models/property_model.dart:248`), which is not a foreign key. A broker listing a builder's property makes these different people | None (static text in the *Property Location* card) | 🔴 **No** — would open the wrong profile | ✅ needs a trustworthy owner id |
| 7 | **Property Details — enquiry sheet** `property_detail_screen.dart:1506` | ❌ | ⚠️ hardcoded `'Rajesh Kumar'` | 🔴 No — placeholder literal | n/a | 🔴 **No** | placeholder must be replaced first |
| 8 | **Search results + property cards** `search/search_results_screen.dart`, `widgets/property_card_{compact,horizontal,vertical}.dart` | ❌ | ❌ | ⚠️ `PropertyModel.userId` exists in the model but is never displayed | Card → property detail | 🔴 **No — nothing to tap** | ✅ new UI (R19.2) |
| 9 | **My Networks rows** `network/my_networks_screen.dart:159-162` | ❌ | ❌ | ⚠️ `NetworkMembership.memberId` exists (`models/network_models.dart:54`) but no name/avatar is rendered — the code states the join is unavailable and "inventing a name would be worse than not" | n/a | 🔴 **No — nothing to tap** | ✅ needs a `profiles` join + new UI |
| 10 | **Social leads** `social/social_leads_screen.dart:235` | ❌ | ✅ `lead.displayName` | 🔴 **No** — Meta ad leads are external contacts (name/email/phone), not PropCid users | Row has no profile gesture | 🔴 **No** | n/a — not app users |
| 11 | **Channel tile** `messaging/widgets/channel_tile.dart` | ✅ (group) | ✅ (group) | ➖ n/a — a channel is not a user | Whole row → channel thread | ➖ n/a | ❌ |
| 12 | Home header `home/widgets/home_header.dart` | ✅ | — | ➖ own | — | ➖ own profile | ❌ |
| 13 | Workspace drawer `widgets/workspace_drawer.dart` | ✅ | ✅ | ➖ own | — | ➖ own profile | ❌ |
| 14 | Own Profile screen + cover header `profile/profile_screen.dart`, `widgets/profile_cover_header.dart` | ✅ | ✅ | ➖ own | — | ➖ own profile | ❌ |
| 15 | Article editor `articles/article_editor_screen.dart` | ✅ | — | ➖ own | — | ➖ own profile | ❌ |
| 16 | Registration wizards ×3 `profile_completion/*_registration_screen.dart` | ✅ upload | ✅ input | ➖ own | — | ➖ own profile | ❌ |

Also checked and found to display **no** user: Notifications, Shortlist, Compare, EMI calculator,
Payment, Visits, Subscription/Billing, Filters, Gallery, the four role Dashboards, and the Network
hub/leads/referrals/communication screens.

---

## Reading of the results

### ✅ One surface is safe to wire right now — #2, the reviews list
`ReviewCard` on the Public Profile is inert, carries `raterId`, and lives in a file created in
Stage 1. Wiring it touches **no pre-existing file at all**, so R19 is satisfied trivially. It also
completes a natural loop: read a review → look at who wrote it.

One caveat, R19.4: reviewers are unique per profile (`user_ratings` is unique on
`(rated_user_id, rater_id)`), so avatar Hero tags cannot collide in that list — but the list is
already Hero-less and should stay that way for consistency with Stage 2A.

### ⚠️ Two surfaces need a decision from you, not code — #3 and #4
Both put the avatar inside a whole-row gesture. Making the avatar open a profile means a tap that
today opens a thread (#3) or selects a recipient (#4) would do something else. That is a UX change,
which your constraint excludes by default.

For #4 in particular I'd advise **against** it regardless: the sheet exists to pick someone, and a
tap that navigates away mid-selection fights the screen's purpose.

For #3, the conventional pattern elsewhere (WhatsApp, Slack) is that the row opens the thread and
the *avatar specifically* opens the profile. If you want that, it needs saying explicitly — it is a
deliberate re-pointing, not an addition.

### 🔴 Three surfaces are blocked on missing data — #5, #6, #10
Worth separating from "not yet done", because no amount of frontend work fixes them:

- **#5 Reels** — `ReelModel` has no creator id. Adding one means changing the model and the query
  that populates it. The avatar and name are *right there* and inert, so this is the most
  frustrating near-miss in the app; it is also the clearest case for a small, separately-approved
  model change.
- **#6 Property Details** — the only id available identifies a different person from the name shown.
  Wiring it would confidently open the wrong profile, which is worse than no link. This is the one
  finding in this audit I would most want on the record.
- **#10 Social leads** — not app users at all.

### 🔴 Three surfaces have nothing to tap — #7, #8, #9
Adding an avatar or a name where none exists is new UI, which R19.2 forbids. Each would be a
deliberate design addition:

- **#8 Search / property cards** would need an agent row on the card — plus a resolved owner
  identity, which runs into #6's problem.
- **#9 My Networks** would need a `profiles` join before a name could be shown honestly. The
  existing code comment is explicit that showing an invented name would be worse, and I agree.
- **#7** is placeholder data that should be replaced before anything is built on it.

---

## Recommendation

**Stage 2B: wire #2 only.** It is the sole remaining surface that satisfies R19 without a UX
decision, and it modifies no pre-existing file.

**Before Stage 2B, a device pass.** Stage 1 and 2A are both unverified on hardware (Stage 2A has no
automated coverage at all — see its Impact Report §5.2). The Public Profile is now reachable from a
real chat header, so this is the first moment the screen can actually be seen. Specific things to
look at:

1. The avatar's `Positioned(top: -46)` overhang inside `Stack(clipBehavior: Clip.none)` — does it
   clip on any device?
2. The `SliverAppBar` collapse: does the white bar and pinned title cross-fade cleanly at 0.55/0.75?
3. `IntrinsicHeight` inside the stat card with 2 vs 3 tiles.
4. The locked-contact blur, and the unlock cross-fade if a connected thread is available.
5. Text scale at 1.3 — the meta strip stacking and the `DetailRow` Row→Column switch.

**Then, as separate decisions:** #3 (re-point the conversation-tile avatar?), and #5 (add a creator
id to `ReelModel`?). I would not touch #4, #6, #7, #8 or #9 without a design conversation first.
