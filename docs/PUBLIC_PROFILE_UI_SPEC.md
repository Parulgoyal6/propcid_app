# PropCid — Public User Profile
## Product & UI Specification (mobile-native redesign)

**Screen:** `PublicProfileScreen` — the profile of *any* user, opened by any authenticated user from
Search, Property Details, Messages, Connections, Reviews, Reels, Articles, or any avatar/name tap.

**Design authority:** the existing Flutter app. Every colour, type ramp, radius, shadow, spacing
value, animation duration and component below is taken from
`core/theme/app_colors.dart`, `core/theme/app_text_styles.dart`, `core/constants/app_constants.dart`
and the existing widget library. **No new design tokens are introduced.**

**Functional authority:** the React portal (`pages/UserProfile.tsx`) — behaviour and data only. The
desktop layout is explicitly *not* reproduced.

**Constraints honoured:** no code, no file changes, no backend/Supabase/API/schema/RLS/migration
work. Every field rendered here is already readable by the Phase 0/1 read paths approved earlier.

---

# 1 · Design system reference (the contract)

## 1.1 Colour

| Token | Value | Used here for |
|---|---|---|
| `AppColors.background` | `#F4F4F8` | screen canvas |
| `AppColors.cardBackground` / `surface` | `#FFFFFF` | every card, app bar when collapsed, sticky bar |
| `AppColors.primary` | `#5B50E8` | CTAs, active icons, links, rating bars |
| `AppColors.primaryLight` | `#EEEDFE` | icon boxes, avatar fallback, segmented track, chip fills |
| `AppColors.primaryPressed` | `#3D35B8` | pressed CTA |
| `AppColors.textPrimary` | `#1A1A2E` | names, values, headings |
| `AppColors.textSecondary` | `#6B7280` | body copy, labels, meta |
| `AppColors.textHint` | `#9CA3AF` | uppercase section labels, chevrons, disabled |
| `AppColors.hairline` | `#EDEDF2` | dividers, card borders, sticky-bar top rule |
| `AppColors.hairlineStrong` | `#F0F0F4` | stat-card vertical dividers |
| `AppColors.surfaceMuted` | `#F9F9FB` | inset rows (detail rows, locked contact plate) |
| `AppColors.verifiedBadge` | `#10B981` | verified tick + chip |
| `AppColors.success` / `warning` / `error` | `#22C55E` / `#F97316` / `#EF4444` | connected / pending / destructive |
| `AppColors.heroGradient` | `#3D35B8 → #5B50E8 → #7C72F0`, TL→BR | cover fallback |
| `AppColors.surfaceCardShadow` | `0 2 10 rgba(26,26,46,.05)` | all cards |
| `AppColors.raisedPillShadow` | `0 2 6 rgba(26,26,46,.10)` | selected segmented pill |
| `AppColors.primaryActionShadow` | `0 4 12 rgba(91,80,232,.28)` | primary CTA |

Role tints come from the existing `screens/profile/profile_role.dart`: builder `Colors.indigo`,
broker `Colors.teal`, influencer `#9333EA`, else `Colors.grey`.

## 1.2 Typography — Poppins via `google_fonts`, through `AppTextStyles` only

| Style | Size / weight | Applied to |
|---|---|---|
| `heading1` | 24 / w700 | (unused here — too large for mobile profile) |
| `heading2` | 18 / w600 | display name (`copyWith(fontSize: 20, height: 1.15)`), rating headline |
| `heading3` | 16 / w600 | card titles (`copyWith(fontSize: 14.5, w700)`), stat values (`16, w700`) |
| `body` | 14 / w400 | bio, detail values, review text (`height: 1.5`) |
| `caption` | 12 / w400 `#6B7280` | meta strip, labels, timestamps |
| `button` | 14 / w600 white | CTA labels (`copyWith(fontSize: 13.5)`) |
| `chip` | 12 / w500 | role pill, trust chips, status chips (`11, w600`) |

Uppercase section labels reuse the existing `DashboardSectionLabel`: **11.5 / w600 / `#9CA3AF` /
0.6 letter-spacing**. Card titles reuse `DashboardCardTitle`: **13.5 / w600**.

Poppins' line box is looser than the CSS equivalent — the `MetricCard` precedent pins `height: 1.2`
on numeric values. **Do the same on every stat value and the display name**, or rows will grow.

## 1.3 Spacing — `AppConstants` only

`spacingXS 4 · spacingS 8 · spacingM 12 · spacingL 16 · spacingXL 20 · spacingXXL 24`

- Screen horizontal gutter: **`spacingL` (16)** — matches property detail. (The own-profile screen
  uses `spacingXL` (20); 16 is chosen here because cards carry their own 16 padding and 20+16 pushes
  content too narrow at 360 dp.)
- Card internal padding: **`spacingL` (16)** — the `DashboardCard` default.
- Gap between cards: **`spacingL` (16)**.
- Gap between a section label and its content: **10**.
- Gap between major section groups: **`spacingXXL` (24)**.
- Inside a card, row-to-row: **`spacingM` (12)**; label-to-value: **`spacingXS`/6**.

## 1.4 Radius — `AppConstants` only

`cardRadius 16` (all cards) · `buttonRadius 12` (buttons, segmented track) ·
`chipRadius 8` (status chips) · `imageThumbnailRadius 12` (thumbnails) ·
`segmentedTabItemRadius 9` (selected pill) · `pillRadius 999` (role pill, trust chips, drag handle,
avatar ring) · `10` (icon boxes — the `MetricCard` precedent).

## 1.5 Elevation

Flat design; elevation is expressed as shadow only, never Material `elevation`.

| Layer | Shadow |
|---|---|
| Canvas | none |
| Card / tile | `surfaceCardShadow` |
| Selected segmented pill | `raisedPillShadow` |
| Primary CTA | `primaryActionShadow` |
| Surface button (`AppActionButtonVariant.surface`) | `0 2 8 rgba(26,26,46,.06)` (already in the widget) |
| Sticky bottom bar | **no shadow** — a 0.5 dp `hairline` top border, matching property detail |
| Collapsed app bar | **no shadow** — 1 dp `hairline` bottom border |
| Avatar | 4 dp `background`-coloured ring (the `ProfileCoverHeader` precedent), no shadow |

## 1.6 Icons

Material rounded outline set, consistent with the existing profile module
(`Icons.share_outlined`, `Icons.qr_code_2_rounded`, `Icons.edit_outlined`, `Icons.cloud_off_rounded`,
`Icons.apartment_rounded`). Sizes from `AppConstants`: `iconSizeSmall 16` (inside buttons/rows),
`iconSizeMedium 24` (app bar, avatar fallback), `18` (icon boxes — `MetricCard` precedent),
`iconSizeLarge 28` (unused here).

Icon-in-box: **34 × 34, radius 10, `primaryLight` fill, 18 dp `primary` glyph** — `MetricCard`.
Larger variant for list tiles: **42 × 42** (`AppConstants.manageTileIconBoxSize`).

## 1.7 Motion

| Constant | Value | Applied to |
|---|---|---|
| `microInteractionMs` | 120 | `ScaleTap` press (scale 0.96, `Curves.easeOut`) |
| `animationDurationMs` | 300 | state morphs, cross-fades, unlock reveal |
| `staggerDelayMs` | 50 | section entrance step |
| `staggerListItemDelayMs` | 60 | list-item stagger |
| `pageTransitionMs` | 350 | route push (`PremiumPageRoute`) |

**Section entrance convention (from `profile_screen.dart`):**
`.animate().fadeIn(duration: 400.ms, delay: N.ms)` where `N` steps 100 → 150 → 200 → 250 → 300 …
This spec adds a matching `.slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic)` — justified by
`property_detail_screen`, which already pairs `FadeTransition` with `SlideTransition` on its content
sheet. Stagger caps at **400 ms total**; sections below the fold animate on first build, not on scroll.

---

# 2 · Screen hierarchy, top to bottom

```
PublicProfileScreen  (Scaffold, backgroundColor: AppColors.background)
│
├── body: RefreshIndicator (color: AppColors.primary)
│   └── CustomScrollView  (physics: BouncingScrollPhysics + AlwaysScrollable)
│       │
│       ├── [S1] PublicProfileCoverHeader        ← SliverAppBar, pinned, collapsing
│       │        • cover image / heroGradient · bottom scrim · parallax stretch
│       │        • leading: glass back  · actions: glass share, glass overflow
│       │        • collapsed: white bar, 28 dp avatar + name, hairline bottom rule
│       │
│       ├── [S2] SliverToBoxAdapter  →  identity zone
│       │        • ProfileAvatar (88 dp, overhangs cover by 42 dp, left 20)
│       │        • PublicIdentityBlock  — name + verified · role pill · @handle
│       │        • RatingInlineRow      — 4.6 ★★★★☆ (23 reviews)
│       │        • IdentityMetaStrip    — city · N yrs exp · specialisation
│       │
│       ├── [S3] TrustChipStrip                  ← horizontal scroll, data-backed only
│       │
│       ├── [S4] StatTripletCard                 ← Listings · Connections · Rating
│       │
│       ├── [S5] AboutCard                       ← bio / company_description
│       │
│       ├── [S6] ContactCard                     ← LOCKED or UNLOCKED variant
│       │
│       ├── [S7] ProfileDetailsCard              ← role-conditional, grouped, expandable
│       │
│       ├── [S8] SocialLinksRow                  ← icon pills, tap → external
│       │
│       ├── [S9] SocialReachCard                 ← MetricCardGrid, Meta follower counts
│       │
│       ├── [S10] ListingsSection                ← label + 4 rows + "View all N"
│       │
│       ├── [S11] ReviewsSection                 ← score + distribution + 3 cards + CTA
│       │
│       └── [S12] SliverToBoxAdapter — bottom spacer (sticky bar height + 24)
│
└── bottomNavigationBar: ProfileStickyActionBar   ← 72 dp, hairline top rule, SafeArea
```

**Section visibility rules**

| Section | Shown when |
|---|---|
| S3 Trust strip | at least one data-backed chip resolves |
| S4 Connections tile | `user_type != 'individual'` (portal rule) → card falls back to 2-up |
| S5 About | `effectiveBio` non-empty |
| S6 Contact | always — locked or unlocked |
| S7 Details | role has ≥1 populated field |
| S8 Social links | ≥1 handle present |
| S9 Social reach | ≥1 follower count non-null (no auth gate — columns are granted to `anon`) |
| S10 Listings | always (empty state if none) |
| S11 Reviews | always (empty state if none) |

---

# 3 · Section-by-section specification

## S1 · Cover hero — `PublicProfileCoverHeader` (new, SliverAppBar)

**Geometry** — deliberately reuses `ProfileCoverHeader`'s numbers so the two profile screens are
visibly the same family: cover **172**, avatar **88**, overhang **42**.

- `expandedHeight: 172 + statusBarInset`, `collapsedHeight: kToolbarHeight`, `pinned: true`,
  `stretch: true`, `automaticallyImplyLeading: false`, `elevation: 0`,
  `backgroundColor: Colors.transparent`.
- Bottom corners: `BorderRadius.only(bottomLeft: 28, bottomRight: 28)` when expanded — the exact
  radius `ProfileCoverHeader` uses. Straightens to 0 as it collapses.
- **Background:** `background_image_url` via `CachedNetworkImage` (`BoxFit.cover`,
  `memCacheWidth: screenWidth.round() * devicePixelRatio`), `errorWidget` and null case →
  `AppColors.heroGradient`. **No remote placeholder URL** — the portal's hardcoded Unsplash fallback
  is dropped (§6.1).
- **Scrim:** `LinearGradient(topCenter → bottomCenter, [transparent, 0x001A1A2E → 0x8C1A1A2E])`,
  lower 55 % only. Guarantees glass-button and collapsed-title legibility over any photo.
- **Stretch:** `StretchMode.zoomBackground` — cover scales on overscroll. Free parallax, no cost.

**Top actions** — 38 dp circles, `Colors.white` at 22 % alpha, white 19 dp glyph. Identical to the
existing private `_GlassIconButton`; extract as a **shared `GlassCircleIconButton`** rather than
editing `profile_cover_header.dart`.

- Leading: `Icons.arrow_back_ios_new_rounded` → `Navigator.maybePop()`
- Trailing 1: `Icons.share_outlined` → existing `showShareProfileSheet(...)`
- Trailing 2: `Icons.more_vert_rounded` → sheet: **Copy link** (existing `copyProfileLink`),
  **Show QR** (existing `showProfileQrSheet`). No Report/Block — no backend exists for either (§6.11).

> Accessibility: the visual circle is 38 dp. Wrap each in a transparent 44 × 44 hit area so the
> target meets the 44 dp minimum without changing the design.

**Collapse behaviour** — driven by a `ValueNotifier<double> _collapse` (0 → 1) fed from a
`ScrollController` listener, consumed by one `AnimatedBuilder`. **Never `setState` per scroll tick.**

| `_collapse` | Behaviour |
|---|---|
| 0.00 – 0.55 | cover fully visible; glass buttons; no title |
| 0.55 – 1.00 | app bar fill cross-fades transparent → `cardBackground`; scrim fades out; glass buttons cross-fade to plain `textPrimary` icons on white; bottom `hairline` rule fades in |
| ≥ 0.75 | collapsed title fades + slides in: **28 dp avatar + name** (`heading3.copyWith(fontSize: 15, w700)`, `maxLines: 1`, ellipsis) |

## S2 · Identity zone

**Avatar — `ProfileAvatar` (new, shared)**
88 dp circle, `primaryLight` fill, **4 dp `AppColors.background` ring**, `left: 20`, overhanging the
cover by 42 dp. Fallback = first initial in `heading1.copyWith(fontSize: 30, w700, color: primary)`
(the exact `ProfileCoverHeader` fallback).

- **Verified tick:** 24 dp `primary` circle, 2.5 dp `background` border, 12 dp white `Icons.check`,
  bottom-right. Condition = the portal's: `verification_status == 'verified' || license_number != null || rera_number != null`.
- **`Hero(tag: 'profile_avatar_$userId')`** — flies from the tapped source avatar. `property_detail`
  already establishes Hero as an app convention.
- **Tap → full-screen `PhotoView`** (`photo_view` is already a dependency), black scrim, swipe-down
  to dismiss. Only when `avatar_url != null`.

**`PublicIdentityBlock` (new)** — starts 12 dp below the avatar, gutter 16.

1. `Wrap(spacing: 8, runSpacing: 6)` — **display name** (`displayTitle`, i.e.
   `company_name ?? agency_name ?? display_name`) in `heading2.copyWith(fontSize: 20, w700, height: 1.15)`,
   then the **role pill**: `roleLabel()` in `chip.copyWith(11.5, w600, color: roleColor())` on
   `roleColor().withValues(alpha: 0.12)`, `pillRadius`, padding `10 × 3`.
   `Wrap` (not `Row`) so a long company name never clips — the `ProfileIdentityBlock` precedent.
   **Not lowercased** (§6.8).
2. **Role subtitle** — `caption.copyWith(12.5)`: "Real Estate Builder / Broker / Influencer / Member",
   from a new `roleSubtitle()` appended to `profile_role.dart`.
3. **`@handle`** — `caption.copyWith(13.5, color: textSecondary)`. Row omitted entirely when
   `username` is empty; never a fabricated placeholder (the `ProfileIdentityBlock` rule).
4. **`RatingInlineRow`** — 6 dp gap: value `heading3.copyWith(15, w700)` · five 14 dp stars
   (`Icons.star_rounded` filled `#F59E0B`… **no** — use `AppColors.warning` `#F97316` for filled and
   `hairlineStrong` for empty, since no amber token exists) · `(23 reviews)` in `caption`.
   Hidden entirely when `count == 0`; replaced by "No reviews yet" in `caption`.
5. **`IdentityMetaStrip`** — `Wrap(spacing: 0, runSpacing: 6)` of up to three cells separated by a
   1 × 12 `hairline` vertical rule with 10 dp side padding:
   `Icons.place_outlined` city · `Icons.work_outline_rounded` "N yrs experience" ·
   `Icons.apartment_rounded` first two specialisations. 14 dp `primary` glyphs, `caption` text.
   Each cell renders only if its value exists. **At text scale ≥ 1.3 the strip stacks vertically.**

## S3 · Trust strip — `TrustChipStrip` (new)

Single-line horizontally scrolling row, 16 dp gutter, 8 dp gaps,
`clipBehavior: Clip.none`, no scrollbar. Each chip: `pillRadius`, padding `10 × 6`, 14 dp glyph +
`chip.copyWith(11.5, w600)`.

| Chip | Condition | Colour |
|---|---|---|
| ✓ **Verified** | `verification_status == 'verified'` | `verifiedBadge` on `#10B981` @ 12 % |
| 🛡 **RERA {number}** | `effectiveRera != null` | `primary` on `primaryLight` |
| 📅 **Member since {yyyy}** | `created_at` present (in the anon grant) | `textSecondary` on `surfaceMuted` |
| 🏢 **{company_name}** | non-individual with `company_name` | `primary` on `primaryLight` |

**Every chip is backed by a real column.** The portal's "Quick Response / Always Available",
"Best Deals / Market Expertise" and "Client Focused / Satisfaction First" tiles are hardcoded
marketing copy with no data behind them and are **not reproduced** (§6.2).

## S4 · Primary stats — `StatTripletCard` (new)

One white `cardRadius` card, `surfaceCardShadow`, `padding: symmetric(vertical: spacingL)`, divided
into equal thirds by `VerticalDivider(width: 1, thickness: 1, color: hairlineStrong, indent/endIndent: 2)`.
This is **`ProfileStatsRow`'s exact geometry**, so the public and private profiles read identically.

| Tile | Value | Label |
|---|---|---|
| 1 | builder → `builderProjects.length`, else `properties.length` | `Projects` / `Listings` |
| 2 | accepted `builder_networks` count | `Connections` — **omitted when `user_type == 'individual'`** |
| 3 | `displayRating.avg`, 1 dp, or `—` | `Rating` |

- Values: `heading3.copyWith(16, w700, height: 1.2)`. Labels: `caption.copyWith(11.5)`.
- Compact formatting (`2.3K` / `1.2M`) must come from **one** implementation. `formatCount` currently
  lives as a private static inside `ProfileStatsRow._StatTile`. **Recommendation: promote it to
  `core/utils/number_format.dart` and have both call it** — a small 🟡 additive change that prevents
  two drifting copies. Alternative: duplicate with an explicit cross-reference comment.
- Tapping tile 1 scrolls to S10; tile 3 scrolls to S11. Tile 2 is non-interactive (another user's
  connection list is not a surface this app exposes).

## S5 · About — `AboutCard`

`DashboardCard` (reused) → `DashboardCardTitle('About')` → 10 dp → bio in
`body.copyWith(13.5, height: 1.55, color: textSecondary)`.

`maxLines: 4` collapsed, with a **"Read more" / "Read less"** text button
(`caption.copyWith(12.5, w600, color: primary)`) that only appears when the text actually overflows —
measure with a `TextPainter`, don't guess. Expansion is `AnimatedSize(300 ms, Curves.easeOutCubic)`.

## S6 · Contact — the signature moment

The portal reveals `phone` / `email` only when `networkStatus == 'connected'` or you are the owner,
and otherwise shows an italic hint. **Redesigned into two explicit card states.**

### S6-A · LOCKED

`DashboardCard` → title row `Icons.lock_outline_rounded` (16 dp, `textHint`) + `DashboardCardTitle('Contact')`.

Body: an inset `surfaceMuted` plate, `buttonRadius`, padding 14, containing two **dummy-shaped
skeleton rows** (a 16 dp circle + a 120 × 10 and a 90 × 10 rounded bar in `hairline`) under an
`ImageFiltered(ImageFilter.blur(sigmaX: 4, sigmaY: 4))` — the shape of the information is visible,
the information is not. **No real value is ever placed in the widget tree while locked**, so there is
nothing to leak via inspector, screenshot or accessibility tree.

Beneath: `Icons.lock_outline_rounded` 14 dp + "Connect to view contact details" in
`caption.copyWith(12.5)`, then an `AppActionButton(variant: outline, height: 44, icon: Icons.person_add_alt_1_rounded, label: 'Connect')`
wired to the same handler as the sticky bar.

The address row is **always** visible (portal parity — `office_address ?? city ?? work_city`).

### S6-B · UNLOCKED

Three `ContactActionRow`s separated by 1 dp `hairline` dividers. Each: 34 dp `primaryLight` icon box
(radius 10, 18 dp `primary` glyph) · label in `caption.copyWith(11.5, color: textHint)` above value in
`body.copyWith(13.5, w600)` · trailing 16 dp action glyph. Whole row is a `ScaleTap`.

| Row | Icon | Value | Tap |
|---|---|---|---|
| Phone | `Icons.call_outlined` | `phone ?? mobile_number` | `url_launcher` → `tel:` |
| Email | `Icons.mail_outline_rounded` | `email` | `url_launcher` → `mailto:` |
| Address | `Icons.place_outlined` | `office_address ?? city` | `url_launcher` → maps geo query |

Rows with no value are omitted, not shown empty.

### Unlock transition

When `networkStatus` becomes `connected`, S6 swaps A → B via
`AnimatedSwitcher(duration: 300 ms, switchInCurve: Curves.easeOutCubic)` with a
`FadeTransition` + `SizeTransition`, plus a single `HapticFeedback.mediumImpact()`. The blur
animates 4 → 0 over the same 300 ms. This is the emotional payoff of connecting and is worth the
extra care.

## S7 · Details — `ProfileDetailsCard`

The portal renders **five separate always-expanded sidebar cards** (Business Details, Personal
Details, Influencer Stats, Builder Details, Broker Insights). On mobile that is five near-identical
boxes and a lot of scrolling. **Redesigned into one card with labelled groups.**

`DashboardCard` → `DashboardCardTitle('Details')` → groups, each: a `DashboardSectionLabel`
(uppercase 11.5) then its rows, groups separated by 14 dp + 1 dp `hairline`.

**`DetailRow`** — `Row(spaceBetween)`, label `caption.copyWith(12.5, color: textSecondary)` left,
value `body.copyWith(13, w600)` right, `textAlign: right`, `Flexible` + `maxLines: 2` + ellipsis.
Long values (commission terms) get `maxLines: 2`; tap-to-expand is not needed.

**Chip-list values** (project types, areas of expertise, languages known) render as a `Wrap` of
`primaryLight` pills (`chipRadius`, `11 w500`, padding `8 × 3`) rather than a comma-joined string.

**Group content by role** — exactly the portal's fields:

| Role | Groups |
|---|---|
| builder | *Business* (experience, specialisation, areas of operation, RERA, website) · *Builder profile* (project types, areas of expertise) · *Personal* (gender, DOB) |
| broker | *Business* (…same…) · *Broker insights* (broker type, commission, price range) · *Personal* |
| influencer | *Business* · *Influencer* (platform, category, audience type, base pricing shoutout/video) · *Personal* |
| individual | *Personal* (gender, DOB) only — the portal shows nothing else |

**Progressive disclosure:** first **5 rows** visible; remainder behind
"Show all details ▾" (`caption.copyWith(12.5, w600, primary)` + `Icons.expand_more_rounded`, rotating
180° over 300 ms), revealed with `AnimatedSize`.

Website value is a tap-to-open link in `primary` w600, normalised to `https://` when the stored value
has no scheme (portal parity).

## S8 · Social links — `SocialLinksRow`

Left-aligned `Wrap(spacing: 10, runSpacing: 10)` of 40 dp circular pills, `surfaceMuted` fill,
18 dp glyph in the platform's own brand colour (Facebook `#1877F2`, Instagram `#E4405F`, LinkedIn
`#0A66C2`, YouTube `#FF0000`, WhatsApp `#25D366`, Telegram `#229ED9`, X `#1A1A2E`) — brand colours are
identity, not theme, and are the one permitted exception to the palette. `ScaleTap` → `url_launcher`
`LaunchMode.externalApplication`.

Reads **both** key variants per role (`facebook` / `facebook_page_link`, etc.). WhatsApp normalises to
`https://wa.me/{digits}`; Telegram to `https://t.me/{handle}` when not already a URL — portal parity.

## S9 · Social reach — `SocialReachCard`

**Visible to every viewer, signed in or not.** An earlier revision restricted this section to
signed-in viewers on the belief that the follower columns were missing from the `anon` grant. That was
wrong: migration `20270312000000_social_follower_counts.sql:76-79` grants all five to `anon`
explicitly, so logged-out visitors can see them. No auth gate here.

`DashboardSectionLabel('Social Reach')` → **`MetricCardGrid`** (reused verbatim: 2-col, 10 dp gaps,
112 dp cells) of `MetricCard`s — Instagram followers, Instagram following, Facebook followers.
Values via the same compact formatter. Below, "Synced {relative time}" from
`social_followers_synced_at` in `caption.copyWith(11, color: textHint)`.

Only non-null counts produce a card; the section disappears entirely when none exist.

## S10 · Listings — `ListingsSection`

`SectionHeader` (reused) — title `Projects` for builders else `Listings`, `actionLabel: 'View all'`
when the count exceeds 4.

Body: the **first 4** items as `PropertyCardCompact` (reused) with 12 dp gaps.

> Note for the implementer: `PropertyCardCompact` paints a 0.5 dp bottom border and **no** card
> shadow, so consecutive cards read as a list, not floating cards. That is correct here and matches
> `MyContentSection`. Do not wrap them in `DashboardCard`.

Builders show `builder_projects` (visitor sees `approval_status == 'approved'` only); everyone else
shows `properties` with `status in ('active','sold')`. Sold items keep the app's existing sold
treatment.

Footer when count > 4: full-width `AppActionButton(variant: surface, height: 44, label: 'View all N listings', trailingIcon: Icons.chevron_right_rounded)`
→ pushes a `UserListingsScreen` (a thin `ListView.builder` over the same provider data — no new query).

**Numbered pagination is not reproduced** (§6.3).

## S11 · Reviews — `ReviewsSection`

`SectionHeader(title: 'Reviews', actionLabel: 'See all')` when count > 3.

**`RatingSummaryCard`** — `DashboardCard`, two columns:

- Left (fixed 96 dp): value `heading1.copyWith(32, w700, height: 1.1, color: primary)`, then `/5` in
  `caption`, five 13 dp stars, then "{n} reviews" in `caption.copyWith(11.5)`.
- Right (`Expanded`): five **`RatingDistributionBar`** rows, 5★ → 1★. Each: "5" in
  `caption.copyWith(11)` · 10 dp star · 6 dp-tall track (`hairline`, `pillRadius`) with a `primary`
  fill · count in `caption.copyWith(11, color: textHint)`.
  Fill animates `0 → fraction` with `TweenAnimationBuilder(600 ms, Curves.easeOutCubic)`, staggered
  60 ms per row, **once** on first appearance.
- Builders additionally get a "Broker Trust Score" strip below a 1 dp `hairline`: label in
  `DashboardSectionLabel`, value in `heading3.copyWith(20, w700, color: statusNewLaunch #3B82F6)`,
  and "{n} professional recommendations" in `caption` — portal parity, shown only when
  `brokerRating.count > 0`.

> The distribution requires per-star counts. `RatingsService.getRatingSummary` already fetches every
> rating row, so the histogram is a **client-side fold over data already in hand** — no new query, no
> backend change. Compute it in the provider, not in `build`.

**`ReviewCard`** ×3 — `DashboardCard(padding: 14)`: 36 dp rater avatar · name `body.copyWith(13, w600)` ·
role badge (reuse the role pill at 10.5) · relative time right-aligned in `caption.copyWith(11, textHint)` ·
five 12 dp stars · review text `body.copyWith(13, height: 1.5, color: textSecondary)`, `maxLines: 4`,
ellipsis. 12 dp gaps.

**Footer CTA** — signed in and not self: full-width
`AppActionButton(variant: outline, height: 44, icon: Icons.star_outline_rounded, label: 'Write a review' | 'Update your review')`
→ opens the rating sheet (Phase 5).

## S12 · Sticky action bar — `ProfileStickyActionBar`

`bottomNavigationBar` slot. **72 dp** + `SafeArea(top: false)`, `cardBackground`, 0.5 dp `hairline`
top border, padding `symmetric(horizontal: 16, vertical: 10)` — the exact geometry of
`property_detail_screen`'s bottom bar, the app's established "detail screen with persistent CTA"
pattern.

> `AppConstants.stickyBottomBarHeight` is 64 and `bottomActionBarHeight` is 60, but property detail
> uses a literal 72. Follow **72** for visual consistency with the app's only comparable screen, and
> flag the unused-constant discrepancy separately.

| Viewer | Left (Expanded) | Right (Expanded) |
|---|---|---|
| Other user | **`ConnectActionButton`** (4-state) | `AppActionButton(solid, elevated, icon: Icons.chat_bubble_outline_rounded, 'Message')` |
| Self | `AppActionButton(outline, icon: Icons.edit_outlined, 'Edit Profile')` | `AppActionButton(solid, elevated, icon: Icons.share_outlined, 'Share')` |
| Signed out | full-width `AppActionButton(solid, elevated, 'Sign in to connect')` | — |

**`ConnectActionButton`** — one `AnimatedContainer(300 ms, easeOutCubic)` morphing colour, border,
icon and label across the portal's four states:

| State | Paint | Icon | Label | Tap |
|---|---|---|---|---|
| `none` | solid `primary` + `primaryActionShadow` | `person_add_alt_1_rounded` | Connect | send request |
| `pending_sent` | `warning` @12 % fill, `warning` border/label | `schedule_rounded` | Requested | cancel (confirm sheet) |
| `pending_received` | solid `success` | `check_rounded` | Accept | accept |
| `connected` | `success` @12 % fill, `success` border/label | `how_to_reg_rounded` | Connected | inert |

In-flight: label → 16 dp `CircularProgressIndicator(strokeWidth: 2)`, button disabled, width held
constant so the bar never reflows. Success fires `HapticFeedback.mediumImpact()`; failure shows a
`SnackBar` and reverts optimistically-applied state.

The bar **fades + slides up** on first load (`fadeIn 300 ms` + `slideY(begin: 0.3)`) once the profile
resolves; it is absent during skeleton.

---

# 4 · States

## 4.1 Loading — `PublicProfileSkeleton`

Full-layout skeleton, **not** a spinner and **not** an empty state (the existing rule from
`my_content_section.dart`: "an empty state would wrongly read as 'you have nothing'").

`Shimmer.fromColors(baseColor: Colors.grey[300]!, highlightColor: Colors.grey[100]!)` — the app's
only shimmer recipe, used by `ProfileStatsRow`, `MyContentSection`, `MetricCardGridShimmer`.

Placeholder blocks, each matching its real counterpart's **exact** box so nothing shifts on load:
cover 172 · avatar 88 circle · name 180 × 18 · handle 110 × 12 · meta 220 × 12 ·
trust chips 3 × (90 × 28 pill) · stat card 88 tall · about card 110 tall ·
contact card 140 tall · two listing rows 95 tall (the `_ContentShimmer` height).

**Per-section independence** — the provider carries a separate loading flag per query (the
`ProfileProvider` pattern). Identity resolves first and renders immediately; stats, listings and
reviews each shimmer in place until their own future completes. One slow query never blanks the screen.

Stat values shimmer as a **34 × 16** box (the exact `_StatTile` loading box), never as `0`.

## 4.2 Empty

All via the existing **`EmptyStateView`** — `primaryLight` circle, `primary` glyph, bold title, muted
1.5-height message, optional CTA.

| Case | icon | title | message | action |
|---|---|---|---|---|
| No listings | `Icons.apartment_rounded` | No listings yet | "{Name} hasn't posted any properties." | — |
| No projects | `Icons.domain_rounded` | No projects yet | "{Name} hasn't published any projects." | — |
| No reviews | `Icons.star_outline_rounded` | No reviews yet | "Be the first to review {Name}." | Write a review |
| No bio | — | *card omitted entirely* | — | — |

`iconCircleSize: 56`, `titleFontSize: 14.5` — the in-card values `MyContentSection` uses.

## 4.3 Error

**Whole-profile failure** (identity query failed) — centred `EmptyStateView`
(`Icons.cloud_off_rounded`, "Couldn't load this profile", "Check your connection and try again.",
action "Retry"). Cover collapses to `heroGradient`; back button remains functional.

**Profile not found** (no row / invalid id) — `Icons.person_off_outlined`, "Profile not available",
"This profile may have been removed.", action "Go back".

**Section failure** — inline `EmptyStateView(Icons.cloud_off_rounded, …, actionLabel: 'Retry')`
scoped to that section, exactly as `MyContentSection` already does. Other sections stay live.

**Failed stat** — `—`, never `0`. The existing `hasFailed` convention: "a failure is never mistaken
for an empty profile."

**Action failure** — `SnackBar` with the message; optimistic state reverted.

**Anonymous PII guard** — the contact card renders LOCKED for signed-out viewers without ever
requesting `phone`/`email`/`mobile_number`. Requesting them anonymously *errors* under the current
grant, so this is a correctness requirement, not a UX choice.

---

# 5 · Behaviour

## 5.1 Scroll

- Single `CustomScrollView`; **no nested scrollables** except S3's horizontal chip strip. Inline
  lists are capped and laid out as columns, so there is exactly one vertical scroll axis.
- `physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())` — the `profile_screen`
  convention, so `RefreshIndicator` works even when content is short.
- **Sticky:** only the app bar (`pinned: true`) and the bottom action bar. Section headers are *not*
  sticky — nothing in this app uses `SliverPersistentHeader`, and introducing it here would be
  off-system.
- **Pull to refresh:** `RefreshIndicator(color: AppColors.primary)` → provider `refresh()`, re-running
  every query. Does **not** re-fire `record_profile_view` (the session guard suppresses it).
- **Programmatic scroll:** stat tiles 1 and 3 animate to S10/S11 via `GlobalKey` +
  `Scrollable.ensureVisible(duration: 400 ms, curve: Curves.easeOutCubic, alignment: 0.1)`.
- Scroll position is preserved across the listings/reviews push-and-pop by the default
  `PageStorageKey` behaviour; give the `CustomScrollView` an explicit key if it proves lossy.

## 5.2 Interactions

| Target | Gesture | Result |
|---|---|---|
| Back | tap | pop |
| Cover | — | inert (no editing on someone else's profile) |
| Avatar | tap | full-screen `PhotoView`, swipe-down dismiss |
| Verified tick | tap | tooltip/sheet explaining verification |
| Rating row / Rating tile | tap | scroll to S11 |
| Listings tile | tap | scroll to S10 |
| Trust chip | tap | inert (informational) |
| Read more / Show all details | tap | `AnimatedSize` expand, chevron rotates 180° |
| Contact row (unlocked) | tap | `tel:` / `mailto:` / maps |
| Contact card (locked) | tap Connect | same handler as sticky bar |
| Social pill | tap | external browser |
| Listing row | tap | `propertyDetailScreen` |
| View all listings | tap | `UserListingsScreen` |
| Review card | tap | inert |
| See all reviews | tap | `UserReviewsScreen` |
| Write a review | tap | rating sheet |
| Connect | tap | state machine; haptic on success |
| Requested | tap | confirmation sheet before cancelling |
| Message | tap | `chatThreadScreen` with `{userId}` |
| Share / overflow | tap | existing share sheet / QR sheet / copy link |

Every tappable surface is wrapped in **`ScaleTap`** (0.96, 120 ms) — the app-wide press convention —
and carries `Semantics(button: true, label: …)`.

## 5.3 Animation inventory

| # | Element | Animation | Duration / curve |
|---|---|---|---|
| 1 | Route push | `PremiumPageRoute` | 350 ms |
| 2 | Avatar | `Hero` flight from source | route duration |
| 3 | Cover | `StretchMode.zoomBackground` parallax | scroll-driven |
| 4 | App bar | fill/scrim/icon/title cross-fade | scroll-driven, 0.55–1.0 |
| 5 | Identity zone | `fadeIn` + `slideY(0.04)` | 400 ms, delay 100 |
| 6 | Trust strip | same | 400 ms, delay 150 |
| 7 | Stat card | same | 400 ms, delay 200 |
| 8 | About | same | 400 ms, delay 250 |
| 9 | Contact | same | 400 ms, delay 300 |
| 10 | Details / Social / Listings / Reviews | same, capped at delay 400 | 400 ms |
| 11 | Sticky bar | `fadeIn` + `slideY(0.3)` | 300 ms, after resolve |
| 12 | Any press | `ScaleTap` 0.96 | 120 ms easeOut |
| 13 | Connect state | `AnimatedContainer` colour/border/label morph | 300 ms easeOutCubic |
| 14 | Contact unlock | `AnimatedSwitcher` fade+size, blur 4→0 | 300 ms easeOutCubic |
| 15 | Rating bars | `TweenAnimationBuilder` fill, 60 ms stagger | 600 ms easeOutCubic |
| 16 | Expand/collapse | `AnimatedSize` + chevron `AnimatedRotation` | 300 ms easeOutCubic |
| 17 | Shimmer | `Shimmer.fromColors` | package default |
| 18 | Section swap on retry | `AnimatedSwitcher` fade | 300 ms |
| 19 | *(optional)* Stat count-up 0→value on first paint | `TweenAnimationBuilder` | 800 ms easeOutCubic |

**Reduced motion:** when `MediaQuery.disableAnimationsOf(context)` is true, skip 3–6, 9–11, 15 and 19
and render final state immediately. Presses (12) and state morphs (13, 14) stay — they carry meaning.

---

# 6 · What NOT to copy from the React portal

1. **Two-column desktop grid** (`grid-cols-[300px_1fr]`, `max-w-7xl`) — mobile is one column.
2. **The four hardcoded Trust Badge tiles** — "Quick Response / Always Available", "Best Deals /
   Market Expertise", "Client Focused / Satisfaction First". Static marketing copy with no data.
   Replaced by the data-backed `TrustChipStrip`.
3. **Numbered pagination** (`1 2 3` + chevrons, 6 per page) — replaced by "View all N".
4. **The 10-second anonymous login-nag modal** and the 30-minute `sessionStorage.tempAuth` window.
5. **`PageHeader` with a logout button** on another user's profile.
6. **The hardcoded Unsplash cover fallback URL** — `heroGradient` instead: on-brand, offline-safe.
7. **Hover-reveal camera overlays** on avatar and cover — no hover on mobile, and no edit rights on
   someone else's profile.
8. **Forced-lowercase display name** (`className="lowercase"`) — a CSS quirk, not a design intent.
9. **Background `<canvas>` visiting-card generation + silent edge-function upload on mount** —
   expensive on open; deferred to an explicit share action.
10. **The self-only "My Connections" tab** inside the profile — belongs to the Network hub.
11. **Nothing for Report / Block** — the portal has no such flow and no backend exists, so the
    overflow menu offers only Share / Copy link / QR.
12. **Desktop `Dialog` modals** — every overlay here is a bottom sheet.
13. **Five separate sidebar detail cards** — merged into one grouped card.

# 7 · What is redesigned

| Portal | Mobile |
|---|---|
| Static header + cover | Collapsing `SliverAppBar` with crossfading title and parallax |
| Contact list with an italic "connect to view" hint | Locked card with blurred skeleton + unlock animation, then tap-to-act rows |
| Score panel + 3 quote cards | Score + animated 5-bar distribution + review cards + CTA |
| 6 bordered stat boxes in a `flex-wrap` | 3-up divided stat card + optional 2-col `MetricCardGrid` |
| 5 always-expanded sidebar cards | 1 grouped card with progressive disclosure |
| Paginated 3-col listing grid | Vertical list, first 4, "View all" |
| Inline pill action row | Sticky bottom bar with a morphing connect button |
| Comma-joined arrays | Chip `Wrap`s |

# 8 · What is enhanced for mobile

1. Collapsing cover + crossfading app bar (context never lost while scrolling).
2. `Hero` avatar flight from whichever surface was tapped.
3. Full-screen avatar viewer via the already-present `photo_view`.
4. Tap-to-call, tap-to-email, tap-to-directions on unlocked contact rows.
5. Sticky, always-reachable primary actions.
6. Pull-to-refresh.
7. Haptics on connect / accept.
8. Skeleton that matches the final layout box-for-box — zero layout shift.
9. Per-section independent loading and retry.
10. Progressive disclosure on About and Details — short screen, full information on demand.
11. Native share sheet + QR, reusing the sheets already built.

# 9 · Premium ideas worth adding

| Idea | Why | Cost |
|---|---|---|
| **Locked-contact blur → unlock reveal** | Turns a permission rule into the screen's emotional payoff; makes the value of connecting legible | Low |
| **Animated rating distribution** | Converts a single number into perceived credibility; data already in hand | Low |
| **Collapsing cover with title crossfade** | The single biggest "premium app" signal on a profile screen | Medium |
| **Hero avatar flight** | Makes navigation feel continuous rather than paged | Low |
| **Morphing connect button** | One control expressing four states beats four different buttons | Low |
| **Cover parallax on overscroll** | One `stretch: true` flag | Trivial |
| **Data-backed trust strip** | Replaces fake reassurance with real signal | Low |
| **Stat count-up on first paint** | Draws the eye to the numbers that establish credibility | Low, optional |
| **Zero-layout-shift skeleton** | The difference between "fast" and "feels fast" | Medium |

Deliberately **not** proposed, because no data exists: response-time badges, online/last-seen
indicators, mutual-connection counts, "N people viewed this profile", endorsements. Each would need
backend work and is therefore out of bounds.

---

# 10 · Widget inventory

## 10.1 Reuse as-is — no modification

| Widget | File | Used for |
|---|---|---|
| `EmptyStateView` | `core/widgets/empty_state_view.dart` | every empty + error state |
| `ScaleTap` | `core/widgets/scale_tap.dart` | every press |
| `DashboardCard` / `DashboardCardTitle` / `DashboardSectionLabel` | `widgets/shared/app_surface_card.dart` | every card + label |
| `MetricCard` / `MetricCardGrid` / `MetricCardGridShimmer` | `widgets/shared/stat_kpi_card.dart` | S9 social reach |
| `AppActionButton` (solid / outline / surface) | `widgets/shared/app_action_button.dart` | every button |
| `SectionHeader` | `widgets/section_header.dart` | S10, S11 headers |
| `PropertyCardCompact` | `widgets/property_card_compact.dart` | S10 rows |
| `SegmentedTabPill` | `core/widgets/segmented_tab_pill.dart` | reviews filter (All / Customers / Brokers) if adopted |
| `roleColor()` / `roleLabel()` | `screens/profile/profile_role.dart` | role pill (`roleSubtitle()` appended) |
| `showShareProfileSheet`, `ProfileLinkBox`, `ShareActionButton`, `copyProfileLink` | `screens/profile/actions/share_profile_sheet.dart` | share |
| `showProfileQrSheet` | `screens/profile/actions/profile_qr_sheet.dart` | QR |
| `profilePath` / `profileShareUrl` / `profileQrImageUrl` / `formattedUserType` | `core/utils/profile_link.dart` | links |
| `Shimmer.fromColors` recipe | `core/widgets/shimmer_loader.dart` | skeleton |
| `AppColors` / `AppTextStyles` / `AppConstants` | `core/theme/`, `core/constants/` | all styling |
| `CachedNetworkImage`, `PhotoView`, `share_plus`, `url_launcher`, `flutter_animate` | pubspec | — |

**Considered and rejected:** `GlassCard` (frosted-blur look not used on this screen);
`PremiumButton` (52 dp gradient + `primaryGlow` — the redesign's buttons are flat 44/46 dp, per the
existing `AppActionButton` doc comment); `StatusTag` (its colour map only knows property statuses);
`ProfileStatsRow` (hard-wired to `ProfileStats`' three labels); `ToggleRow`, `ManageListTile`
(no settings or navigation lists here).

## 10.2 New widgets

| # | Widget | Notes |
|---|---|---|
| 1 | `PublicProfileCoverHeader` | `SliverAppBar`; reuses 172/88/42 and the 28 dp bottom radii |
| 2 | `GlassCircleIconButton` | shared extraction of the private `_GlassIconButton`; original untouched |
| 3 | `ProfileAvatar` | sizes 28/36/88; verified tick; `Hero`; optional `PhotoView` tap |
| 4 | `PublicIdentityBlock` | name + pill + subtitle + handle |
| 5 | `RatingInlineRow` | value + stars + count, single `Semantics` label |
| 6 | `IdentityMetaStrip` | up to 3 hairline-separated cells, stacks at large text scale |
| 7 | `TrustChipStrip` + `TrustChip` | data-backed only |
| 8 | `StatTripletCard` + `StatTile` | `ProfileStatsRow` geometry, variable 2–3 tiles |
| 9 | `AboutCard` | `TextPainter`-measured Read more |
| 10 | `ContactCard` (`LockedContactPlate`, `ContactActionRow`) | blur → unlock |
| 11 | `ProfileDetailsCard` (`DetailRow`, `DetailGroup`, `ChipWrapValue`) | grouped + expandable |
| 12 | `SocialLinksRow` + `SocialLinkPill` | brand-coloured glyphs |
| 13 | `SocialReachCard` | wraps `MetricCardGrid` |
| 14 | `ListingsSection` | header + 4 rows + View all |
| 15 | `RatingSummaryCard` + `RatingDistributionBar` | animated histogram |
| 16 | `ReviewCard` | one review |
| 17 | `ReviewsSection` | summary + cards + CTA |
| 18 | `ConnectActionButton` | 4-state morph |
| 19 | `ProfileStickyActionBar` | 72 dp, viewer-dependent |
| 20 | `PublicProfileSkeleton` | full-layout shimmer |
| 21 | `UserListingsScreen` | thin list over existing provider data |
| 22 | `UserReviewsScreen` | thin list over existing provider data |

## 10.3 Composition tree

```
PublicProfileScreen
└─ ChangeNotifierProvider<PublicProfileProvider>
   └─ Scaffold(background: AppColors.background)
      ├─ RefreshIndicator
      │  └─ CustomScrollView(controller: _scroll)
      │     ├─ PublicProfileCoverHeader
      │     │  ├─ CachedNetworkImage | heroGradient   (RepaintBoundary)
      │     │  ├─ scrim gradient
      │     │  ├─ GlassCircleIconButton ×3
      │     │  └─ collapsed title: ProfileAvatar(28) + name
      │     ├─ SliverToBoxAdapter → Stack(clipBehavior: none)
      │     │  ├─ Positioned(top: -42, left: 20) ProfileAvatar(88, hero)
      │     │  └─ Column
      │     │     ├─ PublicIdentityBlock
      │     │     ├─ RatingInlineRow
      │     │     └─ IdentityMetaStrip
      │     ├─ SliverToBoxAdapter → TrustChipStrip
      │     ├─ SliverToBoxAdapter → Selector<…,StatsVM>  → StatTripletCard | shimmer
      │     ├─ SliverToBoxAdapter → AboutCard
      │     ├─ SliverToBoxAdapter → AnimatedSwitcher → ContactCard(locked|unlocked)
      │     ├─ SliverToBoxAdapter → ProfileDetailsCard
      │     ├─ SliverToBoxAdapter → SocialLinksRow
      │     ├─ SliverToBoxAdapter → SocialReachCard → MetricCardGrid
      │     ├─ SliverToBoxAdapter → Selector<…,ListingsVM>
      │     │                        → ListingsSection | shimmer | EmptyStateView
      │     ├─ SliverToBoxAdapter → Selector<…,ReviewsVM>
      │     │                        → ReviewsSection | shimmer | EmptyStateView
      │     └─ SliverToBoxAdapter → SizedBox(72 + safeArea + 24)
      └─ bottomNavigationBar: ProfileStickyActionBar
                              ├─ ConnectActionButton
                              └─ AppActionButton('Message')
```

---

# 11 · Navigation flow

## 11.1 Entry points → `AppConstants.publicProfileScreen` with `{userId}`

| From | Trigger |
|---|---|
| Search results | agent/owner avatar or name on a result card |
| Property Details | the agent/builder card |
| Messages — thread header | avatar or name |
| Messages — list row | long-press → View profile |
| Network / Connections | row tap |
| Reviews list | rater avatar or name |
| Reels | creator handle |
| Article | author byline |
| Notifications | actor avatar |
| Deep link | `/profile/{role}/{slug}/{userId}` → resolve to `{userId}` |

Route registered as an additive `case` in `app.dart`, pushed with the existing `PremiumPageRoute`
(350 ms). **No `BottomNavBar`** — this is a pushed detail screen, like property detail.

## 11.2 Exits

| Action | Destination |
|---|---|
| Back / swipe | pop, `NavigationProvider` untouched |
| Message | `chatThreadScreen` `{userId}` |
| Listing row | `propertyDetailScreen` `{propertyId}` |
| View all listings | `UserListingsScreen` |
| See all reviews | `UserReviewsScreen` |
| Write review | rating bottom sheet (in-place) |
| Share / QR / Copy | bottom sheets (in-place) |
| Social pill | external browser |
| Edit (self) | `editProfileScreen` |
| Sign in to connect | auth flow, returning here |

**Self-view:** reaching your own profile via a link is legal — the sticky bar becomes Edit + Share,
the contact card is unlocked, and `record_profile_view` is skipped (the RPC no-ops server-side too).

**Loops:** navigating profile → review → rater's profile is allowed; the stack is capped at
**3 profile entries** by checking the current route args before pushing, so users cannot build an
endless chain.

---

# 12 · Responsive behaviour

| Width | Behaviour |
|---|---|
| **< 340** (SE 1st gen, 320) | gutter drops 16 → 12; stat values in `FittedBox(scaleDown)` (the `MetricCard` precedent); role pill wraps below the name via `Wrap`; meta strip allows 2 lines; sticky-bar labels shrink 13.5 → 12.5 |
| **340–430** (baseline) | as specified |
| **430–600** (Max/Ultra) | unchanged; cover 172 → 190 for proportion |
| **≥ 600** (tablet, unfolded) | content constrained to `maxWidth: 560`, centred; stat card 4-up when a 4th stat exists; listings 2-col grid; social reach 3-col; cover 220 |
| **Landscape** | cover 172 → 120; avatar 88 → 64, overhang 42 → 30; identity block moves beside the avatar; sticky bar unchanged |

**Text scale:** supported 0.85 → 1.3 with no clipping. Above 1.3: meta strip stacks, stat card becomes
a 2-col grid, `DetailRow` switches from `Row` to `Column`. No fixed-height text containers anywhere —
`Flexible` + `maxLines` + ellipsis, following `MetricCard`.

**Safe areas:** cover bleeds under the status bar (`SafeArea` applied per-section, the
`profile_screen` convention); sticky bar wraps in `SafeArea(top: false)`; gesture-nav inset respected.

**Dark mode:** the app ships light-only (`AppTheme.lightTheme`, no `darkTheme`). This screen is
light-only too. Every colour is drawn from `AppColors`, so a future dark theme is a token swap.

---

# 13 · Accessibility

1. **Touch targets ≥ 44 dp.** Glass buttons are visually 38 dp — pad the hit area to 44 without
   changing the paint. Social pills are 40 dp — same treatment.
2. **Semantics per element**, following the existing `_StatTile` / `AppActionButton` pattern:
   - Stat tile → `'1,240 Listings'`; while loading → `'Listings loading'`
   - Rating → **one** label `'Rated 4.6 out of 5 from 23 reviews'` with `ExcludeSemantics` on the star
     row, so a screen reader does not announce five icons
   - Avatar → `Semantics(image: true, label: '{name} profile photo')`
   - Locked contact → `'Contact details locked. Connect with {name} to view.'`
   - Connect button → state-specific: `'Connect with {name}'` / `'Connection requested. Tap to cancel'` /
     `'Accept connection request'` / `'Connected'`
   - Distribution bar → `'5 stars, 14 reviews'`
3. **Live regions** — `SemanticsService.announce()` on connect success ("Connected. Contact details
   now available") and on retry success.
4. **Focus order** follows visual order; the sticky bar is last. Expanding a section moves focus to
   the newly revealed content.
5. **Contrast.** `textPrimary` on white = 15.3:1 ✓. `textSecondary` #6B7280 = 4.83:1 ✓ AA.
   **`textHint` #9CA3AF = 2.54:1 — fails AA.** It is acceptable for the uppercase 11.5 dp decorative
   section labels the app already uses it for, but **must never be the only carrier of information**.
   Use `textSecondary` for meta, timestamps and detail labels. Flagging this because the portal leans
   on `text-gray-400` for content that matters.
   White on `primary` #5B50E8 = 5.9:1 ✓. White on `success` #22C55E = 2.3:1 ✗ — so the connected state
   uses a **tinted fill with a `success` label on white**, not white-on-green.
6. **Reduce motion** — honour `MediaQuery.disableAnimationsOf`, per §5.3.
7. **Bold text** — `MediaQuery.boldTextOf` respected automatically by Poppins weights.
8. **Never colour-only** — connection state carries an icon and a label, not just a hue.
9. **Screen-reader traversal of the skeleton** — wrap `PublicProfileSkeleton` in
   `ExcludeSemantics` and expose a single `'Loading profile'` label.

---

# 14 · Performance

1. **Images** — `CachedNetworkImage` everywhere with `memCacheWidth` set from layout × DPR. The cover
   at full resolution in a 172 dp box is the single largest avoidable cost on this screen.
2. **`RepaintBoundary`** around the cover stack, each shimmer block, and the sticky bar. The cover
   repaints on every scroll frame otherwise.
3. **Scroll-driven app bar** via `ValueNotifier<double>` + one `AnimatedBuilder`. A `setState` per
   scroll tick would rebuild all 12 sections at 120 Hz.
4. **Granular rebuilds** — `Selector`/`Consumer` per section against the provider's independent flags,
   so a late reviews query does not rebuild the identity zone.
5. **No `shrinkWrap: true` `ListView`s** inside the `CustomScrollView`. Inline lists are capped at 4/3
   items and built as `Column`s; the full lists live on their own screens with `ListView.builder`.
6. **`const` constructors** on every leaf; `const` `EdgeInsets`, `BorderRadius`, `TextStyle` deltas
   hoisted to statics.
7. **Provider-side derivation** — rating histogram, compact number strings, relative timestamps and
   the trust-chip list are computed once when data lands, never in `build`.
8. **Parallel fetch** — `Future.wait` over the independent queries (the `ProfileProvider` pattern), not
   serial awaits.
9. **`Hero` cost** — one flight, one image; `placeholderBuilder` prevents a double decode.
10. **`AnimatedSwitcher` on the contact card only**, not on the whole column — the blur filter is the
    most expensive paint here, so it is confined to a small plate and torn down after unlock.
11. **Avatar precache** — `precacheImage` the avatar from the source screen before pushing, so the
    Hero lands on a decoded image.
12. **Dispose** the `ScrollController`, `ValueNotifier` and any `AnimationController` in `dispose()`.
13. **`record_profile_view` fires once** per session per (viewer, owner), guarded and fire-and-forget —
    never awaited on the render path.
14. **Budget:** first meaningful paint (skeleton) < 16 ms after push; identity resolved < 400 ms on a
    warm cache; steady-state scroll at 60/120 fps with no frame over 16/8 ms.

---

# 15 · Visual walkthrough — handing this to a senior Flutter developer

You push the screen from a search result. The tapped avatar **lifts off the card and flies** into
position as the route transitions over 350 ms.

**The top fifth of the screen is a cover.** If the user uploaded one it fills edge to edge, bleeding
up under the status bar; if not, you get the app's `heroGradient` — deep indigo top-left to soft
violet bottom-right, the same gradient the user's own profile header uses. Its bottom corners are
rounded 28 dp. A soft dark scrim washes the lower half so anything on top stays readable. Overscroll
and the cover **stretches and zooms** rather than tearing.

Floating on it: three 38 dp frosted-white circles — back at the left, share and a vertical ⋮ at the
right. They read as glass, not chrome.

**Straddling the cover's bottom edge, 20 dp from the left, is an 88 dp circular avatar** with a 4 dp
ring in the page background colour, so it looks punched out of the canvas. Bottom-right of it sits a
24 dp indigo disc with a white tick — present only when the profile is genuinely verified. Tap the
avatar and the photo opens full-screen; swipe down to dismiss.

Below, on the `#F4F4F8` canvas, the identity reads down the left edge: **the name at 20 dp Poppins
Bold in near-black**, and immediately beside it a small role pill — teal for a broker, indigo for a
builder, violet for an influencer — tinted at 12 % with matching text. Under that, the role in
muted grey: "Real Estate Broker". Under that, the `@handle` — and if there's no username, that line
simply doesn't exist rather than showing a placeholder. Then a rating line: **4.6** in bold, five
14 dp stars filled in warm orange, then "(23 reviews)" in grey. Then a thin meta strip — a small
indigo pin and the city, a hairline rule, a briefcase and "8 yrs experience", another rule, a
building and the top two specialisations.

**Next, a single row of pills that scrolls sideways.** Green tick "Verified". Indigo shield "RERA
MH12345678". Grey calendar "Member since 2019". Every one of them backed by a real column — there is
no "Quick Response" or "Best Deals" filler here, because there is no data for it.

**Then the numbers.** One white card, 16 dp radius, that whisper-soft `0 2 10` shadow, split into
equal thirds by two hairline verticals: **Listings · Connections · Rating**. Bold 16 dp values,
11.5 dp grey labels. While they load each value is a small shimmering bar — never a zero, because a
zero is a lie. If a query fails you get an em dash. Tap Listings and the page glides down to the
listings; tap Rating and it glides to the reviews.

**"About"** — a white card, its title at 13.5 dp semibold, four lines of 13.5 dp grey body text at
1.55 line height, and a small indigo "Read more" that appears only if the text genuinely overflows.
Tapping it grows the card smoothly rather than snapping.

**Then the moment that makes this screen.** A card titled **"Contact"** with a small padlock beside
the title. Inside, an inset grey plate holding two blurred grey bars — you can see the *shape* of a
phone number and an email, but not the values, because the real values were never put in the widget
tree. Below: "Connect to view contact details" and an outlined **Connect** button. The address is
visible regardless — that's the portal's rule.

The instant the connection is accepted, that plate **cross-fades away as the blur melts from 4 to 0
over 300 ms**, replaced by three tappable rows: a phone with a small indigo call glyph in a lilac
square, an email, an address. One medium haptic tap. Tap the phone row and the dialler opens. That
transition is the reward for connecting, and it's worth building properly.

**"Details"** follows — one card, not five. Inside, uppercase grey group labels: BUSINESS, then
BROKER INSIGHTS, then PERSONAL, each separated by a hairline. Label left in grey, value right in
semibold dark. Arrays like project types and languages render as little lilac chips that wrap, not as
a comma-mashed string. Only the first five rows show; "Show all details ▾" reveals the rest with the
chevron rotating as the card grows.

**A left-aligned row of 40 dp circles** — Facebook blue, Instagram pink, LinkedIn, YouTube red,
WhatsApp green. Brand colours, because those are identity, not theme. Tap opens the external app.

If the user has connected Meta and the viewer is signed in, a small **"SOCIAL REACH"** label sits over
a two-column grid of the app's existing metric cards — 34 dp lilac icon squares, 17 dp bold values
like "12.3K", 11 dp labels — with "Synced 2 hours ago" underneath in the lightest grey.

**"Listings"** with a "View all" link on the right. Four compact rows — 130 × 95 thumbnail on the
left, title, location, price — separated by hairlines so they read as a list rather than four floating
cards. Sold items keep the app's existing sold treatment. If the count exceeds four, a full-width
white surface button: "View all 18 listings ›". If there are none, the app's standard empty state —
lilac circle, indigo building glyph, "No listings yet".

**"Reviews"** with "See all". First a summary card: on the left a **big 32 dp indigo 4.6** with "/5"
beneath, five small stars, "23 reviews". On the right, five bars — 5★ down to 1★ — each a hairline
track with an indigo fill that **animates out from zero over 600 ms, staggered 60 ms per row**, the
first time you see it. For a builder, a hairline below adds "BROKER TRUST SCORE" and a blue 4.2.
Then three review cards: 36 dp rater avatar, name, a small role badge, "3 weeks ago" right-aligned,
five stars, four lines of quote. Then a full-width outlined **"Write a review"**.

**Pinned to the bottom the entire time** — a 72 dp white bar with a single hairline along its top,
respecting the gesture inset. Two buttons. On the right, a solid indigo **Message** with its soft
indigo glow. On the left, the connect control: solid indigo **"Connect"** when you're strangers; it
morphs over 300 ms into an amber-tinted **"Requested"** with a clock; into a solid green **"Accept"**
when they asked you; and finally into a green-tinted **"Connected"** with a tick. One button, four
states, never four buttons. While a request is in flight the label becomes a 16 dp spinner and the
width holds, so the bar never twitches.

**Scrolling up**, the cover slides away and — past 55 % — the transparent app bar **cross-fades to
solid white**, the glass buttons resolve into plain dark icons, a hairline appears along the bottom,
and a 28 dp avatar plus the name **fade and slide in** as the pinned title. You always know whose
profile you're on.

**Pull down** and an indigo refresh spinner re-runs every query. Each section reloads independently:
if reviews are slow, they shimmer in place while everything else stays live. If one fails, that
section alone shows a small cloud-off icon with "Retry" — the rest of the screen is untouched.

Every card, row, chip and button **presses down to 96 % over 120 ms** when touched. Sections faded and
lifted 4 % into place on first paint, staggered 50 ms apart, capped at 400. And if the user has
reduced motion on, all of that is simply gone — the screen is just *there*, instantly, fully formed.
