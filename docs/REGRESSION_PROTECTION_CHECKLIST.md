# PropCid Flutter — Regression Protection Checklist

**Purpose.** Every feature listed here already works today. It must still work identically after
every phase of the User Profile migration. This is the acceptance gate: a phase is not complete
until its scope items pass and the "Always verify" set passes.

**How to use.** After each phase, run §0 (automated gate) in full, then walk the manual checks for
every module the phase's Impact Analysis names as touched, plus the "Always verify" block in §16.

**Legend**
`AUTO` — covered by an existing test in `test/`; regression is caught mechanically.
`MANUAL` — no automated coverage; must be exercised on a device/emulator.
`RISK` — a known-fragile interaction documented from prior work; check even when it looks unrelated.

---

## §0 · Automated gate — run after EVERY phase, no exceptions

```
flutter analyze                 → no NEW issues vs. the recorded baseline
flutter test                    → no NEW failures vs. the recorded baseline
flutter build apk --debug       → must complete successfully
```

### Measured baseline — captured 2026-08-05, before Phase 0

| Gate | Baseline |
|---|---|
| `flutter analyze` | **447 issues — 0 errors, 0 warnings, all `info`** (`withOpacity` deprecations, `sort_child_properties_last`, `unnecessary_underscores`). Full output: `docs/impact-reports/baseline-analyze.txt` |
| `flutter test` | **540 passing, 1 failing** |
| Pre-existing failure | `phase8_social_test.dart` → `SocialAnalytics.fromLogs windows are relative to now` |

**The gate is "no new issues / no new failures", not "zero".** The pre-existing warnings and the
pre-existing failure are not this migration's to fix — repairing them would be an unrequested change
to existing code (Safe Implementation Rules R5).

> **⚠ Pre-existing failure — diagnosed, deliberately not fixed.**
> `test/phase8_social_test.dart:54` hardcodes `createdAt = '2026-08-03T10:00:00Z'` in its `_log()`
> helper, then asserts `analytics.today == 1` at line 189. `SocialAnalytics` computes its windows
> relative to `DateTime.now()`, so that assertion only holds **on 2026-08-03**. It is a time-bomb
> test that rots with the calendar, and it has nothing to do with the profile migration.
> One-line fix, needs approval as an existing-file edit:
> `createdAt = DateTime.now().toIso8601String()` — which is what "windows are relative to now" was
> trying to express in the first place.
> Until then, treat **540 pass / 1 fail** as green and watch only for a *change* in that count.

The existing suite is the primary regression harness:

| Test file | Guards |
|---|---|
`listing_constants_parity_test.dart` | dropdown values match React verbatim (T0) |
`listing_data_contract_t1_test.dart` | listing payload shape |
`listing_validation_rules_t2_test.dart` | validation parity |
`listing_step_visibility_t3_test.dart` | wizard step gating |
`listing_media_t4_test.dart` | media handling |
`listing_project_tag_t5_test.dart` | project tagging |
`listing_residential_t6_test.dart` · `listing_others_t7_test.dart` · `listing_land_t8_test.dart` · `listing_pg_t9_test.dart` · `listing_commercial_t10_test.dart` | per-category field parity |
`listing_pricing_t11_test.dart` | pricing logic |
`listing_validators_parity_test.dart` · `listing_dimensions_portal_parity_test.dart` | validator/dimension parity |
`post_property_metadata_roundtrip_test.dart` | **metadata edit-mode safety (the Phase 0 listing fix)** |
`post_property_shell_layout_test.dart` · `wizard_end_to_end_test.dart` | wizard shell + E2E |
`search_bar_parity_test.dart` | **`AppTheme.inputDecorationTheme` border leak** |
`dashboard_design_parity_test.dart` · `dashboard_regression_test.dart` | dashboard layout |
`shared_components_test.dart` | shared widget library |
`phase6_network_social_upgrade_test.dart` · `phase7_subscription_billing_test.dart` · `phase8_social_test.dart` · `phase9_network_test.dart` | Network / Social / Billing modules |
`premium_launch_banner_layout_test.dart` · `article_html_test.dart` | banner layout, article rendering |
`widget_test.dart` | **app boots; carries the second provider tree** |

---

## §1 · Authentication

Files: `screens/auth/auth_screen.dart`, `otp_screen.dart`, `reset_password_screen.dart`,
`auth_post_login.dart`, `screens/splash/splash_screen.dart`, `providers/auth_provider.dart`,
`services/auth_service.dart`, `services/session_service.dart`, `services/rbac_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 1.1 | Email + password login | MANUAL |
| 1.2 | Login by phone number or username (`loginWithIdentifier` resolves to email) | MANUAL |
| 1.3 | Sign up → role/type persisted; email-confirmation-required path returns the sentinel | MANUAL |
| 1.4 | Phone OTP: send, resend, verify, session established | MANUAL |
| 1.5 | Google OAuth opens and the session arrives via the auth-state stream | MANUAL |
| 1.6 | Forgot password sends the reset email | MANUAL |
| 1.7 | Logout clears `isLoggedIn`, `userName`, `userEmail`, `avatarUrl`, `userRole`, `userType`, `userId`, `profileCity`, `profileRow` | MANUAL |
| 1.8 | `AuthProvider._fetchUserProfile()` still populates all eight cached fields on login | MANUAL |
| 1.9 | `AuthProvider.refreshProfile()` re-reads and notifies | MANUAL |
| 1.10 | Session survives app restart (`supabase_flutter` persistence) | MANUAL |
| 1.11 | `AuthProvider.profileRow` remains an **unmodifiable** view — callers cannot mutate the cache | AUTO-able |
| 1.12 | **RISK** `AuthService.getUserProfile()` keeps returning `null` on error (not throwing) — several callers depend on that | MANUAL |

> **Phase 0 relevance:** `UserProfileService.fetchOwn()` delegates to `getUserProfile()` and must not
> change its signature, behaviour, or null-on-error contract.

## §2 · Home

Files: `screens/home/home_screen.dart` (+ `widgets/`), `providers/property_provider.dart`,
`providers/available_locations_provider.dart`

| # | Must continue working | Type |
|---|---|---|
| 2.1 | Home renders: hero/banner, category grid, property carousels, sections | MANUAL |
| 2.2 | `CustomScrollView` scroll performance unchanged | MANUAL |
| 2.3 | Premium launch banner + bottom sheet | AUTO (`premium_launch_banner_layout_test`) |
| 2.4 | Banner destination resolution (`banner_destination_resolver.dart`) | MANUAL |
| 2.5 | Bottom nav index 0 highlighted | MANUAL |
| 2.6 | Property card taps → Property Details | MANUAL |

## §3 · Search

Files: `screens/search/search_screen.dart`, `search_results_screen.dart`,
`screens/filters/filters_screen.dart`, `widgets/search_bar_widget.dart`,
`providers/filter_provider.dart`, `providers/recent_searches_provider.dart`,
`services/ai_search_service.dart`, `voice_search_service.dart`, `recent_searches_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 3.1 | Search entry auto-focuses; **no double border** on the field | AUTO (`search_bar_parity_test`) + RISK |
| 3.2 | AI free-text parsing on every search | MANUAL |
| 3.3 | Voice search | MANUAL |
| 3.4 | Suggestions + debounce | MANUAL |
| 3.5 | Recent searches: `ai_user_memory` when signed in, `shared_preferences` when out; CAP 10; partial upsert never overwrites the row | MANUAL |
| 3.6 | Category pills map correctly (Apartment→residential+Flat, Villa→residential+Villa, Plot→land, Commercial→commercial) | MANUAL |
| 3.7 | **RISK** `SearchResultsScreen.initState` calls `runSearch(reset: true)` itself — exactly **one** query per search, never two | MANUAL |
| 3.8 | `IntentStash.get('va_search_filters')` voice-agent bridge runs before the first `runSearch` | MANUAL |
| 3.9 | Filters sheet applies and clears | MANUAL |
| 3.10 | Map view + map button navigation | MANUAL |
| 3.11 | Pagination (`searchPageSize` 20) and near-me radius (15 km, cap 100) | MANUAL |

## §4 · Property Details

Files: `screens/property_detail/property_detail_screen.dart`, `screens/gallery/gallery_viewer_screen.dart`,
`models/property_detail_bundle.dart`, `services/property_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 4.1 | Hero `SliverAppBar` (260 dp), pinned collapse | MANUAL |
| 4.2 | Image carousel + `Hero` flight into the gallery (`property_hero_{id}_{index}`) | MANUAL |
| 4.3 | Content sheet: 20 dp top radius, drag handle, verified badge, title/price/location | MANUAL |
| 4.4 | Sticky bottom bar (72 dp): Schedule Visit + Enquiry sheets | MANUAL |
| 4.5 | Shortlist toggle from the hero actions | MANUAL |
| 4.6 | Amenities, nearby places, EMI widget, map | MANUAL |
| 4.7 | **RISK** the agent/owner card still renders — Phase 1 adds a profile tap target here | MANUAL |

## §5 · Property Listing (Post Property wizard)

Files: `screens/post_property/**`, `providers/post_property_provider.dart`,
`services/property_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 5.1 | All T0–T11 business logic unchanged | AUTO (13 listing tests) |
| 5.2 | Metadata merge on edit — **no corruption, no key loss** | AUTO (`post_property_metadata_roundtrip_test`) |
| 5.3 | Step visibility per category | AUTO (`listing_step_visibility_t3_test`) |
| 5.4 | Every dropdown value matches React verbatim | AUTO (`listing_constants_parity_test`) |
| 5.5 | Media pick/compress/upload to `property-media` | MANUAL |
| 5.6 | Edit mode loads and re-saves without field loss | AUTO + MANUAL |
| 5.7 | Wizard shell layout, no overflow | AUTO (`post_property_shell_layout_test`, `shell_overflow_probe`) |
| 5.8 | End-to-end submit | AUTO (`wizard_end_to_end_test`) |

> **Phase 4 relevance:** `ProfileMediaService` must not alter `PropertyService`'s
> `property-media` upload path or the wizard's compression behaviour.

## §6 · Messages

Files: `screens/messaging/**`, `providers/messaging_provider.dart`, `chat_thread_provider.dart`,
`services/messaging_service.dart`, `models/chat_message.dart`, `conversation_summary.dart`,
`channel_summary.dart`

| # | Must continue working | Type |
|---|---|---|
| 6.1 | Conversation list loads; unread counts correct | MANUAL |
| 6.2 | 1:1 thread send/receive | MANUAL |
| 6.3 | Channel (group) thread — same screen, distinct route | MANUAL |
| 6.4 | Realtime message arrival | MANUAL |
| 6.5 | Chats / Channels `SegmentedTabPill` | AUTO (`shared_components_test`) |
| 6.6 | Thread opens correctly when passed `{userId}` | MANUAL |
| 6.7 | **RISK** Phase 1 adds a profile tap on the thread header — the header must keep its existing layout and actions | MANUAL |

## §7 · Network module

Files: `screens/network/**`, `providers/network_hub_provider.dart`, `network_section_provider.dart`,
`services/network_service.dart`, `models/network_models.dart`, `network_stats.dart`

| # | Must continue working | Type |
|---|---|---|
| 7.1 | Network hub: 4 KPIs, sections | AUTO (`phase9_network_test`, `phase6_network_social_upgrade_test`) |
| 7.2 | My Networks / Leads / Referrals / Communication leaf screens | AUTO |
| 7.3 | **`NetworkService.getAcceptedCount()` returns the identical number** — Phase 6 appends methods beside it | AUTO-able + RISK |
| 7.4 | Accept / decline invitation flows already in the hub | MANUAL |
| 7.5 | Builder-vs-member KPI branch still keyed off `AuthProvider.userType` | MANUAL |

> **Phase 6 relevance:** the highest-risk file in the whole migration. New methods must be appended
> only; `getAcceptedCount` must not be refactored, re-signatured, or "cleaned up".

## §8 · Profile Completion

Files: `services/profile_completion_coordinator.dart`, `services/rbac_service.dart`,
`screens/splash/splash_screen.dart`, `screens/auth/auth_post_login.dart`,
`core/utils/profile_completion.dart`

| # | Must continue working | Type |
|---|---|---|
| 8.1 | Post-login routing to the correct role registration screen when the profile is incomplete | MANUAL |
| 8.2 | Splash resolves the pending role and routes accordingly | MANUAL |
| 8.3 | `pending_user_type` in `shared_preferences` is read and cleared | MANUAL |
| 8.4 | `RbacService` role→landing resolution | MANUAL |
| 8.5 | `calculateProfileCompletion()` returns the **same percentage** for the same row — the 4 core items, the role branches, and every fallback (`bio \|\| company_description`, `city \|\| work_city`, `rera_number \|\| license_number`, `@`-in-name rule) | AUTO-able + RISK |
| 8.6 | `ProfileCompletionCard` shows that percentage on the existing Profile screen | MANUAL |

> **Phase 3 relevance:** the edit screen consumes `calculateProfileCompletion` read-only. It must not
> be re-tuned, or the completion number changes for every existing user.

## §9 · Builder / Broker / Influencer Registration

Files: `screens/profile_completion/{builder,broker,influencer}_registration/*.dart`,
`services/profile_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 9.1 | All three 7-step wizards navigate forward/back; per-step validation | MANUAL |
| 9.2 | `ProfileService.saveBuilderProfile` writes the **same 13 fields** it writes today | MANUAL + RISK |
| 9.3 | `saveBrokerProfile` upserts `broker_profiles` **and** mirrors onto `profiles` | MANUAL + RISK |
| 9.4 | `saveInfluencerProfile` writes its `social_media` object | MANUAL + RISK |
| 9.5 | On submit: `pending_user_type` cleared → `refreshProfile()` → snackbar → `RoleHomeRouter` | MANUAL |
| 9.6 | Routes `/builder-profile`, `/broker-profile`, `/influencer-profile` still resolve to the **registration** screens | MANUAL |

> **Known pre-existing defects (R1, R2) are deliberately NOT fixed.** Do not "improve" these methods
> while nearby. If Phase 3 or 4 makes a change here tempting, stop and report instead.
>
> **Phase 3 relevance:** 🟡 A-1 changes who *navigates* to these routes, not the routes themselves.
> First-time completion must still reach the wizards via splash / coordinator / RBAC.

## §10 · Existing Profile screen (own profile)

Files: `screens/profile/profile_screen.dart`, `profile_role.dart`, `widgets/*` (8), `actions/*` (6),
`providers/profile_provider.dart`, `models/profile_stats.dart`,
`services/{profile_view,ratings,network}_service.dart`

| # | Must continue working | Type |
|---|---|---|
| 10.1 | Screen renders in order: cover → identity → stats → completion → actions → Create Content → My Content → Manage | MANUAL |
| 10.2 | Cover header: 172 dp gradient, 88 dp avatar, 42 dp overhang, verified tick, menu + bell | MANUAL |
| 10.3 | `ProfileStatsRow`: shimmer while loading, `—` on failure, `2.3K`/`1.2M` compact formatting | MANUAL + RISK |
| 10.4 | `ProfileProvider.load()` / `refresh()`; independent stats-vs-content failure flags | MANUAL |
| 10.5 | Bottom nav index 3 set from `initState` post-frame | MANUAL |
| 10.6 | Workspace drawer opens from the menu button; scrim colour | MANUAL |
| 10.7 | My Content: All / Properties / Articles tabs, empty + error states | MANUAL |
| 10.8 | Create Content grid → Post Property / Article Editor | MANUAL |
| 10.9 | Manage list → Dashboard / Saved / More / Projects (builder) | MANUAL |
| 10.10 | Share sheet and QR sheet open and produce the correct URL | MANUAL |
| 10.11 | Pull-to-refresh | MANUAL |
| 10.12 | Entrance stagger (fadeIn 400 ms, delays 100–300) | MANUAL |
| 10.13 | Edit Profile routes by role (**changes only under approved 🟡 A-1**) | MANUAL |

> **Phase 4 relevance (🟡 A-2):** editing `profile_cover_header.dart` risks 10.2. The gradient must
> remain the fallback and all four geometry constants must keep their values.
>
> **Spec relevance:** if `formatCount` is promoted to a shared util, 10.3 must be re-verified —
> `ProfileStatsRow` is the incumbent caller.

## §11 · Notifications

Files: `screens/notifications/notifications_screen.dart`,
`screens/profile/actions/notifications_sheet.dart`

| # | Must continue working | Type |
|---|---|---|
| 11.1 | Notifications screen lists rows, empty state | MANUAL |
| 11.2 | Notifications sheet from the profile bell | MANUAL |
| 11.3 | Mark-as-read behaviour | MANUAL |
| 11.4 | Unread dot on the bell | MANUAL |

> **Phase 6 relevance:** connect inserts a `builder_network_addition` notification. It must appear for
> the recipient, and a *failed* insert must never fail the connection.

## §12 · Settings

Files: `screens/profile/actions/settings_sheet.dart`, `logout_dialog.dart`

| # | Must continue working | Type |
|---|---|---|
| 12.1 | Sheet opens at 60 % height, 24 dp top radius | MANUAL |
| 12.2 | All five rows render (Dark Mode, Push, Location, Language, Email) | MANUAL |
| 12.3 | Logout row → confirm dialog → logout | MANUAL |
| 12.4 | Sheet reachable from Profile, Workspace Drawer **and** More sheet — all three entry points | MANUAL |

> **Phase 7 relevance (🟡 A-4):** wiring `comments_enabled` + `work_city` must not disturb 12.1–12.4.
> The three genuinely-local toggles keep their current visual treatment unless you rule otherwise.

## §13 · Theme

Files: `core/theme/app_theme.dart`, `app_colors.dart`, `app_text_styles.dart`,
`core/constants/app_constants.dart`

| # | Must continue working | Type |
|---|---|---|
| 13.1 | **No token value changes.** Every existing colour, text style and constant keeps its value | AUTO-able |
| 13.2 | **RISK** `AppTheme.inputDecorationTheme` untouched — it sets `filled: true` + 2 dp `#5B50E8` `enabledBorder`/`focusedBorder` at r14. Editing it breaks every form in the app | AUTO (`search_bar_parity_test`) |
| 13.3 | Any borderless `TextField` nulls all six border slots **and** sets `filled: false` | MANUAL |
| 13.4 | App remains light-only (no `darkTheme`) | MANUAL |
| 13.5 | Poppins via `google_fonts` throughout | MANUAL |
| 13.6 | New constants are **additive only** — no existing value edited | AUTO-able |

## §14 · Navigation

Files: `app.dart`, `main.dart`, `app_navigator.dart`, `providers/navigation_provider.dart`,
`widgets/bottom_nav_bar.dart`, `workspace_drawer.dart`, `more_bottom_sheet.dart`,
`core/navigation/**`, `core/animations/page_transitions.dart`

| # | Must continue working | Type |
|---|---|---|
| 14.1 | Every existing `case` in `app.dart`'s `onGenerateRoute` resolves as before | MANUAL |
| 14.2 | Unknown route still falls through to `HomeScreen` | MANUAL |
| 14.3 | `PremiumPageRoute` transition (350 ms) unchanged | MANUAL |
| 14.4 | Bottom nav: Home 0, Search 1, Reels 2, Profile 3, centre "+" unindexed; 64 dp height | MANUAL |
| 14.5 | `NavigationProvider.setIndex()` semantics unchanged | MANUAL |
| 14.6 | Workspace drawer destinations all resolve | MANUAL |
| 14.7 | More sheet destinations all resolve | MANUAL |
| 14.8 | `manage_dashboard_dispatcher` routes each role to its dashboard | AUTO (`dashboard_regression_test`) |
| 14.9 | `appNavigatorKey` password-recovery jump still fires from the auth stream | MANUAL |
| 14.10 | **RISK** `main.dart` and `test/widget_test.dart` provider trees stay **identical** | AUTO (`widget_test`) |

> Every phase that adds a route adds a `case`; every phase that adds a provider edits **both** trees.
> A provider added to only one causes `widget_test` to fail — which is the guard working.

## §15 · Deep links

Configured: `android/app/src/main/AndroidManifest.xml` (two VIEW intent-filters),
`AuthService.sendPasswordResetEmail` → `propcid://reset-password`

| # | Must continue working | Type |
|---|---|---|
| 15.1 | `propcid://reset-password` opens `ResetPasswordScreen` | MANUAL |
| 15.2 | A recovery link that establishes a session first still jumps via `appNavigatorKey` | MANUAL |
| 15.3 | Both existing intent-filters remain intact | MANUAL |
| 15.4 | `verifyRecoveryToken` token-hash path works | MANUAL |

> **Note:** the app has **no** `/profile/{role}/{slug}/{userId}` web-link handler today. The spec's
> deep-link entry is *aspirational*; wiring it would mean editing `AndroidManifest.xml` + `Info.plist`
> — **out of scope**, and it must be reported rather than implemented.

## §16 · Always verify — the cross-cutting set

Run these after **every** phase regardless of scope.

| # | Check | Type |
|---|---|---|
| 16.1 | `flutter analyze` — no new issues vs. 447 baseline | AUTO |
| 16.2 | `flutter test` — no new failures vs. 540 pass / 1 fail baseline | AUTO |
| 16.3 | `flutter build apk --debug` succeeds | AUTO |
| 16.4 | App cold-starts to splash → correct landing screen | MANUAL |
| 16.5 | Login → logout → login again | MANUAL |
| 16.6 | Bottom nav: all four tabs reachable, correct highlight | MANUAL |
| 16.7 | No new `debugPrint` noise / red-screen exceptions in a normal session | MANUAL |
| 16.8 | Provider trees in `main.dart` and `test/widget_test.dart` identical | AUTO |
| 16.9 | No file outside the phase's declared Impact Analysis list changed (`git status --short`) | AUTO |
| 16.10 | No `.sql`, `supabase/`, `AndroidManifest.xml`, `Info.plist`, `pubspec.yaml` change | AUTO |
| 16.11 | Voice agent tools still register (`main.dart` `_registerVoiceAgentTools`) and `view_my_profile` / `open_my_dashboard` still navigate | MANUAL |
| 16.12 | Theme tokens unchanged — diff `app_colors.dart`, `app_text_styles.dart`, `app_theme.dart` | AUTO |

## §17 · Other modules — smoke only

Not in the migration path, but in the same binary. One tap each per phase.

| Module | Files | Check |
|---|---|---|
| Reels | `screens/reels/**` | feed scrolls, share works |
| Shortlist / Saved | `screens/shortlist/**` | list loads, toggle persists |
| Compare | `screens/compare/**` | two properties compare |
| EMI calculator | `screens/emi_calculator/**` | computes |
| Payment | `screens/payment/**` | method screen opens |
| Subscription & Billing | `screens/subscription/**` | AUTO (`phase7_subscription_billing_test`) |
| Social module | `screens/social/**` (6 leaves) | AUTO (`phase8_social_test`) |
| Dashboards ×4 | `screens/dashboard/**` | AUTO (`dashboard_*_test`) |
| Articles | `screens/articles/**` | AUTO (`article_html_test`) + editor opens |
| Visits | `screens/visits/**` | list loads |
| Voice agent | `voice_agent/**` | mic opens, one command runs |

---

## §18 · Per-phase scope map

Which sections to walk manually after each phase (§0 and §16 are always mandatory).

| Phase | Sections to verify |
|---|---|
| **0** — model + read service | §16 only (zero existing files touched; §1.12 by inspection) |
| **1** — public profile screen | §14 (new route + provider), §4.7, §6.7, §3 (entry points), §16 |
| **2** — view recording | §10.3 (`ProfileViewService` gains a method), §11, §16 |
| **3** — edit screen | §8, §9, §10.13, §1.8–1.9, §13.2–13.3, §14, §16 |
| **4** — avatar/cover upload | §10.2, §5.5, §9.2, §16 |
| **5** — ratings | §10.3 (`RatingsService`), §16 |
| **6** — network actions | **§7 in full**, §11, §16 |
| **7** — settings / views / deletion | §12, §10.3, §11, §14, §16 |
| **8** — polish | §10.2, §10.3, §10.10, §16 |
