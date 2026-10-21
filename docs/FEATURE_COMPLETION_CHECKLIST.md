# User Profile — Feature Completion Checklist

React portal (functional reference) vs. the current Flutter implementation.

**Legend**

| | Meaning |
|---|---|
| ✅ | **Implemented** — working in Flutter now |
| 🟡 | **Deferred** — planned, scoped to a named later phase, nothing blocking it |
| 🔴 | **Blocked** — needs data, a model change, or backend work that is out of scope |
| ❌ | **Not Applicable** — a web-only concern, or deliberately dropped by an approved decision |

**As of:** end of Phase 1 (Stage 1 + 2A + 2B) + layout validation.
Analyze 447 / tests 668 pass, 1 pre-existing failure / debug APK builds.

**Totals:** ✅ 44 · 🟡 38 · 🔴 7 · ❌ 17 — **106 line items**

---

## 1 · Public profile page

| # | Feature | Portal reference | Status | Notes |
|---|---|---|:--:|---|
| 1.1 | Public profile screen | `UserProfile.tsx` | ✅ | `public_profile_screen.dart`, 12 sections |
| 1.2 | Route registration | `/profile/:role/:slug/:userId` ×6 | ✅ | `AppConstants.publicProfileScreen`, args `{userId, avatarHeroTag?, depth?}` |
| 1.3 | Canonical URL self-heal | `UserProfile.tsx:367-380` | ❌ | URL rewriting is a browser concern; there is no address bar |
| 1.4 | Deep link `/profile/{role}/{slug}/{id}` | AndroidManifest | 🔴 | Needs a manifest + `Info.plist` intent filter — platform config, out of scope (R16) |
| 1.5 | Auth-dependent column list | `UserProfile.tsx:328-340` | ✅ | `UserProfileService.publicColumns` / `authenticatedColumns`, asserted byte-identical in test |
| 1.6 | Own-profile read path | `select('*')` | ✅ | Delegates to `AuthService.getUserProfile` |
| 1.7 | Profile-not-found state | — | ✅ | Distinct from a load failure |
| 1.8 | Load-failure + retry | — | ✅ | Per-section retry; identity failure is full-screen |
| 1.9 | Pull to refresh | ❌ web | ✅ | Mobile addition |
| 1.10 | SEO meta tags | `<SEO />` | ❌ | Web-only |
| 1.11 | i18n (`t()` on every string) | `react-i18next` | ❌ | App ships no i18n layer; every screen inlines English |

## 2 · Identity & header

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 2.1 | Cover image from `background_image_url` | ✅ | Plus the documented `publicColumns` addition — the portal omits the column and never shows a visitor's cover |
| 2.2 | Cover fallback | ✅ | `heroGradient`; the portal's hardcoded Unsplash URL deliberately dropped |
| 2.3 | Collapsing header + crossfading title | ✅ | Mobile enhancement; 0.55/0.75 thresholds |
| 2.4 | Cover parallax on overscroll | ✅ | `StretchMode.zoomBackground` |
| 2.5 | Avatar, 88 dp, 42 dp overhang | ✅ | Geometry asserted by test |
| 2.6 | Verified badge | ✅ | Portal condition: `verification_status=='verified' \|\| license_number \|\| rera_number` |
| 2.7 | Full-screen avatar viewer | ✅ | `photo_view`; mobile addition |
| 2.8 | Display name fallback chain | ✅ | `company_name \|\| agency_name \|\| display_name` |
| 2.9 | Forced-lowercase name | ❌ | A CSS quirk, not design intent |
| 2.10 | Role badge + subtitle | ✅ | `roleBadge()` / `roleSubtitle()`, re-exporting the existing helpers |
| 2.11 | `@username`, omitted when absent | ✅ | Never a fabricated placeholder |
| 2.12 | Inline rating row | ✅ | Single semantics label, not five star icons |
| 2.13 | Meta strip (city · experience · specialisation) | ✅ | Stacks from ~1.16× text scale |
| 2.14 | Logout button in the profile header | ❌ | Nonsensical on someone else's profile |
| 2.15 | Avatar `Hero` flight from source | 🟡 | Screen accepts `avatarHeroTag`; nothing supplies one. Deliberately omitted from Stage 2A |

## 3 · Trust & stats

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 3.1 | Active listings / projects count | ✅ | Label switches for builders |
| 3.2 | Connections count | ✅ | Hidden for `individual`, per portal |
| 3.3 | Rating tile | ✅ | Em dash when unrated, never `0.0` |
| 3.4 | Compact number format (2.3K / 1.2M) | ✅ | `formatCompactCount`, parity-tested against the live `ProfileStatsRow` |
| 3.5 | Meta follower tiles (IG followers/following, FB) | ✅ | All five columns granted to `anon` |
| 3.6 | "Synced N ago" | ✅ | From `social_followers_synced_at` |
| 3.7 | IG media count | 🟡 | Column read and modelled; no tile designed for it |
| 3.8 | Trust chip strip (Verified · RERA · Member since · Company) | ✅ | Every chip data-backed |
| 3.9 | 4 static "Trust Badges" tiles | ❌ | Hardcoded marketing copy with no data behind it |
| 3.10 | Profile-views count on a public profile | ❌ | Private to the owner; not on the public page in the portal either |

## 4 · About, contact, details

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 4.1 | Bio with `bio \|\| company_description` | ✅ | |
| 4.2 | Read more / less | ✅ | `TextPainter`-measured, so it only appears when text truly overflows |
| 4.3 | Contact gate (connected or self) | ✅ | Portal rule verbatim |
| 4.4 | Locked state | ✅ | Blurred **empty** bars — real values never enter the widget tree; asserted by test |
| 4.5 | Unlock cross-fade | ✅ | 300 ms fade + size, blur 4→0 |
| 4.6 | Address always public | ✅ | |
| 4.7 | Tap-to-call / mail / directions | ✅ | Mobile addition |
| 4.8 | Business Details card | ✅ | Merged into one grouped Details card |
| 4.9 | Personal Details (non-builder) | ✅ | Gender, DOB |
| 4.10 | Influencer stats card | ✅ | Platform, category, audience, followers, base pricing |
| 4.11 | Builder details card | ✅ | Project types, areas of expertise, company type |
| 4.12 | Broker insights card | ✅ | Type, commission, price range, languages |
| 4.13 | Five separate sidebar cards | ❌ | Merged deliberately — five boxes of label/value pairs is poor on a phone |
| 4.14 | Progressive disclosure | ✅ | First 5 rows, then "Show all details" |
| 4.15 | Chip lists instead of comma-joined strings | ✅ | |
| 4.16 | Website link normalisation | ✅ | Adds `https://` when the stored value has no scheme |
| 4.17 | Social links row | ✅ | 7 platforms, brand colours, both key spellings read |
| 4.18 | WhatsApp / Telegram shorthand normalisation | ✅ | `wa.me/{digits}`, `t.me/{handle}` |

## 5 · Listings & reviews

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 5.1 | Properties, `status in ('active','sold')` | ✅ | Portal filter verbatim |
| 5.2 | Builder projects, `status='active'` | ✅ | |
| 5.3 | Visitor sees approved projects only | ✅ | Owner sees pending too |
| 5.4 | Sold overlay + blur | 🟡 | Flutter has its own sold treatment via `PropertyCardCompact`; the portal's blur is not reproduced |
| 5.5 | First 4 inline + "View all" | ✅ | Replaces numbered pagination |
| 5.6 | Numbered pagination (6/page) | ❌ | Mobile uses "View all" |
| 5.7 | `UserListingsScreen` (the View-all target) | 🟡 | Button hidden until it exists — no dead end |
| 5.8 | Listing → property detail | ✅ | |
| 5.9 | Project → project detail | 🔴 | **No project-detail route exists in the app.** Tapping shows a SnackBar rather than falling through to Home |
| 5.10 | Influencer videos tab | 🟡 | Portal fetches `influencer_videos`; not designed into the mobile screen |
| 5.11 | Status / stories | 🟡 | Portal fetches `status`; no mobile design |
| 5.12 | Rating summary (avg, /5, stars, count) | ✅ | |
| 5.13 | Customer vs broker vs total split | ✅ | Portal rule: non-broker rater = customer |
| 5.14 | Builder shows customer average | ✅ | |
| 5.15 | Broker Trust Score (builders) | ✅ | Only when a broker has rated |
| 5.16 | 5-bar rating distribution | ✅ | **Beyond the portal** — animated, folded from rows already fetched |
| 5.17 | Review cards (author, role, time, stars, text) | ✅ | First 3 inline |
| 5.18 | "Anonymous" fallback for unresolved authors | ✅ | |
| 5.19 | Review author → their profile | ✅ | **Stage 2B**; inert for unresolved authors; chain capped at 3 |
| 5.20 | `UserReviewsScreen` ("See all") | 🟡 | Button hidden until it exists |
| 5.21 | Write / update a review | 🟡 | **Phase 5** — `RatingsService` is read-only today |
| 5.22 | `UserRatingsDisplay` filter by rater type | 🟡 | Belongs with the reviews screen |

## 6 · Actions

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 6.1 | Sticky action bar | ✅ | 72 dp, property-detail geometry |
| 6.2 | 4-state connect button rendering | ✅ | Morphs over 300 ms |
| 6.3 | Connection status **read** | ✅ | Two-table lookup, `ProfileConnectionService` |
| 6.4 | Send connection request | 🟡 | **Phase 6** — `onConnect: null`, renders disabled |
| 6.5 | Cancel a pending request | 🟡 | Phase 6 |
| 6.6 | Accept an incoming request | 🟡 | Phase 6 |
| 6.7 | `builder_network_addition` notification | 🟡 | Phase 6 |
| 6.8 | Message → chat thread | ✅ | Reuses `MessagingService.startConversation` + existing `ChatThreadScreen` |
| 6.9 | Share profile | ✅ | Existing share sheet |
| 6.10 | Copy link / QR | ✅ | Existing sheets, via the overflow menu |
| 6.11 | Visiting-card PNG + `save-visiting-card` | 🟡 | **Phase 8 (P8-2/P8-3)**; P8-3 needs explicit approval |
| 6.12 | Edit Profile on a self view | 🟡 | **Phase 3** — self view shows Share alone rather than a dead end |
| 6.13 | Sign-in prompt for anonymous viewers | ✅ | |
| 6.14 | Report / block a user | ❌ | No such flow or backend exists in the portal either |
| 6.15 | 10-second anonymous login nag | ❌ | Approved decision D2 |
| 6.16 | 30-minute `tempAuth` window | ❌ | Approved decision D2 |

## 7 · Profile views

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 7.1 | Unique-viewer count | ✅ | `ProfileViewService.getCount`, on the own-profile screen |
| 7.2 | **Record a view** (`record_profile_view` RPC) | 🟡 | **Phase 2 — in progress now** |
| 7.3 | Viewer list screen | 🟡 | Phase 7 |
| 7.4 | Realtime list updates | 🟡 | Phase 7 |
| 7.5 | "Viewed N times" badge | 🟡 | Phase 7 |
| 7.6 | `profile_view` notification | ✅ | The RPC inserts it server-side; no client work |

## 8 · Edit profile

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 8.1 | Edit screen | 🟡 | **Phase 3** |
| 8.2 | Basic Information section | 🟡 | Phase 3 |
| 8.3 | Role-conditional sections (builder / broker / influencer / individual) | 🟡 | Phase 3 |
| 8.4 | `social_media` merge-first write | 🟡 | Phase 3 — highest-consequence item in the migration |
| 8.5 | Paired-column writes (×5) | 🟡 | Phase 3 |
| 8.6 | Omit trigger-guarded columns | 🟡 | Phase 3 — `can_update_profile_fields()` reverts them *silently* |
| 8.7 | Role immutability | 🟡 | Phase 3 — enforced by the DB trigger, mirrored in the UI |
| 8.8 | Validation (phone ≥10, pincode 6, GST 15, PAN 10, email) | 🟡 | Phase 3 |
| 8.9 | Dropdown option sets copied verbatim | 🟡 | Phase 3 — `CLAUDE.md`: never invent values |
| 8.10 | `user_preferences` city upsert | 🟡 | Phase 3 |
| 8.11 | Country-code selector | 🟡 | Phase 3 |
| 8.12 | Existing name/email dialog | 🔴 | Reports a save that never persists (defect R5). Superseded by Phase 3, deliberately **not** repaired |

## 9 · Media upload

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 9.1 | Avatar upload → `avatars` bucket | 🟡 | **Phase 4** |
| 9.2 | Cover upload → `property-media` | 🟡 | Phase 4 |
| 9.3 | Document uploads (RERA, GST, PAN, registration, Aadhaar, logo) | 🟡 | Phase 4 |
| 9.4 | Crop / zoom / rotate | 🔴 | Needs `image_cropper` — a new package plus native config (R14) |
| 9.5 | Pre-upload compression | 🟡 | Phase 4, via `image_picker` sizing — the approach the wizard already documents |
| 9.6 | Owner-only cover camera affordance | 🟡 | Phase 4 (🟡 A-2) |
| 9.7 | Registration wizard writes a placeholder avatar URL | 🔴 | Defect R1: `'placeholder_profile.jpg'` written to `avatar_url`. Existing rows need a data fix — backend work |

## 10 · Settings & account

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 10.1 | Settings sheet exists | ✅ | Pre-existing, three entry points |
| 10.2 | `comments_enabled` persisted | 🟡 | Phase 7 (🟡 A-4) — currently a silent no-op |
| 10.3 | `work_city` persisted | 🟡 | Phase 7 (🟡 A-4) |
| 10.4 | Social URLs in settings | 🟡 | Phase 7 — overlaps Phase 3's edit form |
| 10.5 | Dark mode toggle | ❌ | App ships light-only (`AppTheme.lightTheme`, no `darkTheme`) |
| 10.6 | Account-deletion request | 🟡 | Phase 7 |
| 10.7 | `delete_account` voice tool destination | 🟡 | Phase 7 (🟡 A-5) — tool registered, points nowhere |
| 10.8 | Profile dropdown / sheet menu | ✅ | Covered by the existing Workspace Drawer + More sheet |
| 10.9 | Subscription & Billing entry | ✅ | Pre-existing |

## 11 · Profile completion

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 11.1 | Completion % calculation | ✅ | `calculateProfileCompletion` — exact port, all fallbacks and the `@`-in-name rule |
| 11.2 | Completion card on own profile | ✅ | Pre-existing |
| 11.3 | Completion tile → edit screen | 🟡 | Phase 3 supplies the destination |
| 11.4 | Post-signup role gate | ✅ | `profile_completion_coordinator` + `rbac_service` |
| 11.5 | Role registration wizards ×3 | ✅ | Pre-existing, 7 steps each |
| 11.6 | localStorage draft recovery (7-day TTL) | 🟡 | Portal has it; wizards do not |
| 11.7 | Wizards persist all collected fields | 🔴 | Defect R2: ~17 of ~30 dropped, incl. **all** `social_media` for builder/broker. Modifies existing write logic — out of bounds (R5) |

## 12 · Own-profile surfaces (adjacent, pre-existing)

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 12.1 | Own profile screen | ✅ | Pre-existing |
| 12.2 | Stats row (Followers / Reviews / Profile Views) | ✅ | Pre-existing |
| 12.3 | My Content tabs | ✅ | Pre-existing |
| 12.4 | Create Content grid | ✅ | Pre-existing |
| 12.5 | Manage list + Workspace Drawer + More sheet | ✅ | Pre-existing |
| 12.6 | Role dashboards ×4 | ✅ | Pre-existing |
| 12.7 | Individual / Seller "walls" | ❌ | A web feed layout; the app has Reels + Social hub instead |
| 12.8 | `BrokerProfileManager` | ❌ | Superseded by the broker dashboard |
| 12.9 | `BuilderRatingsTestimonials` | 🟡 | Testimonial authoring; not scoped |
| 12.10 | `ActivitySummaryCard` / `IndividualUserActivity` | ✅ | Covered by My Content + dashboards |
| 12.11 | `UserSelector` | ✅ | `new_chat_sheet` covers the same need |
| 12.12 | `UserTypeSelector` | ✅ | Covered by the registration flow |
| 12.13 | `SocialProfileMobileNav` (5-slot) | ❌ | App has its own 64 dp `BottomNavBar` (approved decision Q9) |
| 12.14 | `SocialProfileMobileProfileView` tile grid | ❌ | Superseded by the redesigned own-profile screen |

## 13 · Entry points into the public profile

| # | From | Status | Notes |
|---|---|:--:|---|
| 13.1 | Chat thread header | ✅ | **Stage 2A** |
| 13.2 | Review author | ✅ | **Stage 2B** |
| 13.3 | Conversation tile avatar | 🟡 | Needs a UX decision — the avatar sits inside the row's existing tap |
| 13.4 | New-chat sheet row | ❌ | The sheet's purpose is selection; navigating away fights it |
| 13.5 | Reels creator | 🔴 | `ReelModel` has `builderName`/`builderAvatarUrl`/`builderPhone` but **no id** |
| 13.6 | Property Details owner | 🔴 | `builder_name` is denormalised text with no FK; the only id is the *poster*. Would open the wrong person |
| 13.7 | Search results / property cards | 🔴 | No avatar or name rendered at all — adding one is new UI (R19.2) |
| 13.8 | My Networks rows | 🔴 | No name or avatar rendered; the code notes the join is unavailable |
| 13.9 | Social leads | ❌ | Meta ad leads are external contacts, not app users |
| 13.10 | Notifications actor | 🟡 | No actor avatar rendered today |

## 14 · Cross-cutting

| # | Feature | Status | Notes |
|---|---|:--:|---|
| 14.1 | Skeleton loading, zero layout shift | ✅ | Full-layout, box-for-box |
| 14.2 | Per-section independent load/failure | ✅ | Four independent flags |
| 14.3 | Em dash on failure, never `0` | ✅ | |
| 14.4 | Empty states (5 variants) | ✅ | Via the shared `EmptyStateView` |
| 14.5 | Entrance stagger (fadeIn + slideY) | ✅ | 400 ms, 50 ms steps, capped at 400 |
| 14.6 | Reduce-motion honoured | ✅ | `MediaQuery.disableAnimationsOf` |
| 14.7 | Press feedback on every target | ✅ | `ScaleTap` 0.96 / 120 ms |
| 14.8 | Semantics on every element | ✅ | Single labels for star rows and stat tiles |
| 14.9 | 44 dp minimum touch targets | ✅ | Glass buttons padded from 38 → 44 |
| 14.10 | Text scale to 130% | ✅ | Verified; four overflow bugs found and fixed |
| 14.11 | 320 / 390 / 430 dp widths | ✅ | Verified |
| 14.12 | Tablet ≥600 dp (max-width 560, centred) | 🟡 | Specified, not implemented |
| 14.13 | Landscape adaptation | 🟡 | Specified, not implemented |
| 14.14 | `RepaintBoundary` on the cover | ✅ | |
| 14.15 | `memCacheWidth` on the cover | ✅ | |
| 14.16 | Scroll-driven header via `ValueNotifier` | ✅ | Not `setState` per tick |
| 14.17 | Provider-side derivation | ✅ | Histogram, formatting, trust chips |
| 14.18 | No nested vertical scrollables | ✅ | One axis; only the chip strip scrolls horizontally |
| 14.19 | **Device validation on Android** | 🟡 | **Release requirement** (V1). Layout verified by harness; performance entirely unverified |
| 14.20 | Frame-timing / jank measurement | 🔴 | Requires hardware |

---

## Blocked items — the full list (7)

Each needs something outside this workstream's remit.

| Ref | Item | What would unblock it |
|---|---|---|
| 5.9 | Project rows do not navigate | A project-detail screen + route |
| 8.12 | Name/email dialog reports a false save | Approval to delete it (Phase 3 supersedes the path) |
| 9.4 | Avatar crop / zoom / rotate | A new package (`image_cropper`) + native config |
| 9.7 | Placeholder avatar URL in wizards | Approval to edit `ProfileService` **and** a data fix for existing rows |
| 11.7 | Wizards drop ~17 collected fields | Approval to edit `ProfileService` |
| 13.5 | Reels creator | A creator id on `ReelModel` + its query |
| 13.6 | Property Details owner | A trustworthy owner identity (not `builder_name`) |
| 14.20 | Performance measurement | An Android device |

**The two highest-value:** 11.7 and 9.7. Until fixed, Phase 3's edit screen will show fields empty
for users who filled them in during registration, and completion percentages will under-report.

## Deferred items by phase

| Phase | Items | Count |
|---|---|---|
| **2** — view recording | 7.2 | 1 |
| **3** — edit profile | 8.1–8.11, 11.3, 6.12 | 13 |
| **4** — media upload | 9.1–9.3, 9.5, 9.6 | 5 |
| **5** — ratings write | 5.21, 5.22 | 2 |
| **6** — network actions | 6.4–6.7 | 4 |
| **7** — settings / views / deletion | 7.3–7.5, 10.2–10.4, 10.6, 10.7 | 8 |
| **8** — polish | 2.15, 3.7, 6.11 | 3 |
| **Stage 2C+** — entry points | 13.3, 13.10 | 2 |
| Unscoped | 5.4, 5.7, 5.10, 5.11, 5.20, 11.6, 12.9, 14.12, 14.13, 14.19 | 10 |
