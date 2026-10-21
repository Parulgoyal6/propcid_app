# PropCid Mobile — Master Implementation Blueprint

**Version 2** · 2026-08-04
Supersedes V1 (chat-provided) and the Phase 12 addendum, both of which are folded in here.

---

## 0. Sources of truth (unchanged from V1)

| Role | Source | Rule |
|---|---|---|
| **Functional** | React Portal (`propcid/`) | Behaviour, queries, business rules. Where docs disagree with React, React wins. |
| **Visual** | Approved mobile designs (`profiledesign/`) | Layout, spacing, type, colour. Where design conflicts with an existing Flutter primitive, the design wins. |
| **Target** | Flutter app (`FLUTTER-APP/`) | Owns its own architecture and navigation. |

**Backend rule:** backend functionality must not be modified unless a future
phase explicitly requires it and that requirement is approved in writing. See
Contract V2 §A.

---

## 1. Delivered architecture (as built, verified 2026-08-04)

```
Widget → Provider (ChangeNotifier) → Service → Supabase
```

- State: `provider` package only. No Riverpod / Bloc / GetX.
- Routing: `onGenerateRoute` in `lib/app.dart`, **39 routes**.
- Screen-scoped providers via `ChangeNotifierProvider` at the top of each screen;
  only genuinely global providers live in `main.dart`.
- Every async screen splits into `XScreen` (provider host) + `XBody`
  (provider-free visuals) so layout is testable without Supabase.

### 1.1 Load lifecycle (discovered during implementation — was **not** in V1)

An async `load()` body runs synchronously to its first `await`, and most raise a
loading flag and call `notifyListeners()` before that point. Called from
`didChangeDependencies` — which runs during build — this trips
`assert(!_dirty)` and can touch a deactivated ancestor.

**Mandated pattern**, now centralised in `DeferredSectionLoader`
(`lib/screens/shared/section_loader.dart`):

1. resolve `userId` from `AuthProvider`;
2. guard against re-loading the same user;
3. defer the call to `addPostFrameCallback`;
4. re-check `mounted` inside the callback.

Applied in Profile, Messages, Network hub, Subscription, and all ten Social and
Network leaf screens.

### 1.2 Shared component library (`lib/widgets/shared/`, 7 files)

| File | Exports | Introduced |
|---|---|---|
| `stat_kpi_card.dart` | `MetricCard`, `MetricCardGrid`, `MetricCardGridShimmer` | P5 (promoted), P6 (shimmer) |
| `section_header_back_button.dart` | `DashboardHeaderBar` | P5 (promoted), P7 optional subtitle |
| `app_chart_wrapper.dart` | `DashboardLineChart` | P5 (promoted) |
| `app_surface_card.dart` | `DashboardCard`, `DashboardCardTitle`, `DashboardSectionLabel` | P6 (promoted) |
| `toggle_row.dart` | `AppToggle`, `ToggleRow` | P5; P6 sizes, P8 `bordered` |
| `content_picker_dialog.dart` | `ContentPickerItem` + `showContentPickerSheet` | P5 |
| `app_action_button.dart` | `AppActionButton` (solid/outline/danger/surface) | P7; P8 `surface` |

Also shared: `lib/core/widgets/` — `EmptyStateView`, `SegmentedTabPill`,
`ScaleTap`, `ShimmerLoader`, `GlassCard`, `PremiumButton`, `StepIndicator`.

**Promotion protocol** (established P5, reused P6/P9): move the class verbatim,
adjust import depth only, leave a one-line `export` shim at the old path so
existing imports are untouched, and prove type identity in a test
(`expect(shared.X, legacy.X)`).

### 1.3 Cross-module abstractions (discovered — **not** in V1)

| Abstraction | Purpose |
|---|---|
| `AsyncSection<T>` (`lib/providers/async_section.dart`) | value + loading + failed + dispose-safe notify. On failure keeps the previous value and raises `failed`; never substitutes an empty value. `SocialSection` and `NetworkSection` both extend it. |
| `DeferredSectionLoader` | the lifecycle pattern in §1.1 |
| `WorkspaceDestinations` | one implementation of every drawer / More-sheet destination, so the two surfaces cannot diverge |

### 1.4 Honest-state doctrine (discovered — **not** in V1)

A rule applied consistently from Phase 3 onward, and now binding:

- A **failed** read renders `—` or an explicit error, never `0` and never an
  empty list. "Couldn't load X" and "You have no X" are different sentences.
- Never render a figure with no backing query. Where React hardcodes a value
  (Network Performance Summary: `85%` / `2.3 hrs` / `4.8/5`), mobile shows `—`
  and keeps the row.
- Never assert account state that has not been read (the Upgrade screen omits
  the design's "Current Plan" badge because no subscription query runs there).
- Controls that cannot yet act are visibly inert with a stated reason, never
  silently no-op.

---

## 2. Completed work — Phases 1A – 9

All nine phases delivered, gated on: zero new analyzer issues, full test suite,
debug APK build, and a written regression checklist.

| Phase | Scope | Status |
|---|---|---|
| **1A** | Design tokens, `PremiumPageRoute`, shared primitives | ✅ Complete |
| **1B** | Workspace Drawer, More sheet, `WorkspaceDestinations`, `ComingSoonScreen` | ✅ Complete |
| **2** | Profile root rebuild — new foundation for all later modules | ✅ Complete |
| **3** | Manage Dashboard ×4 roles; Analytics / Content Manager / Audience tabs | ✅ Complete |
| **4** | Messaging — Chats + Channels, thread, composer, realtime | ✅ Complete |
| **5** | Article Editor (no rich-text dependency) + shared-component promotion | ✅ Complete |
| **6** | Network hub, Social hub, Upgrade screen; 5 of 7 `comingSoon()` retired | ✅ Complete |
| **7** | Subscription & Billing — hub + 10 tabs + Billing Policies; last 2 retired | ✅ Complete |
| **8** | Social leaves ×6 — Accounts, Campaigns, Leads, Preferences, Activity, Analytics | ✅ Complete |
| **9** | Network leaves ×4 — My Networks, My Leads, My Referrals (4 sub-tabs), Communication (3 sub-tabs) | ✅ Complete |

### 2.1 Design coverage

**44 of 47** design screens implemented (94%). The three outstanding are
`isCheckout`, `isPaymentSuccess`, `isRefundFlow` (+3 steps) — all payment-provider
dependent, all scheduled in Phase 10.

### 2.2 Placeholder retirement

All **7** original `comingSoon()` call sites now reach real screens
(4 in `workspace_drawer.dart`, 3 in `more_bottom_sheet.dart`).

> **V1 correction, carried forward:** V1 located these in
> `workspace_destinations.dart`. They were never there. V2 records the correct
> locations above.

### 2.3 Verified navigation graph

39 routes. Every hub card is covered by an end-to-end test asserting it pushes
its real named route.

```
Profile ─┬─ Manage Dashboard (role dispatcher → 4 dashboards)
         ├─ Messages ── Chat thread / Channel thread
         ├─ Network hub ─┬─ My Networks
         │               ├─ My Leads
         │               ├─ My Referrals  (Overview│Referrals│Commissions│Performance)
         │               └─ Communication (Channels│Messaging│Settings)
         ├─ Social hub ──┬─ Accounts ├─ Campaigns ├─ Leads
         │               └─ Preferences ├─ Activity ├─ Analytics
         ├─ Upgrade
         ├─ Subscription & Billing (10 tabs → Billing Policies)
         └─ Articles, Reels, Feed, Settings, Logout
```

### 2.4 Providers, services, models delivered

**Providers (19 total).** Added by these phases: `profile_provider`,
`dashboard_analytics_provider`, `individual_dashboard_provider`,
`messaging_provider`, `chat_thread_provider`, `article_editor_provider`,
`network_hub_provider`, `network_section_provider`, `social_provider`,
`subscription_provider`, `async_section`.

**Services (26 total).** Added by these phases: `dashboard_analytics_service`,
`messaging_service`, `article_service`, `network_service`, `social_service`,
`subscription_service`, `profile_view_service`, `ratings_service`.

**Models added:** `profile_stats`, `article_model`, `article_summary`,
`channel_summary`, `chat_message`, `conversation_summary` (2 classes),
`dashboard_analytics` (4), `tagged_project`, `network_stats`,
`network_models` (9), `social_models` (7), `subscription_summary` (3).

### 2.5 Verified backend mappings (read-only)

| Service | Tables / views / functions |
|---|---|
| `dashboard_analytics_service` | `properties` \| `influencer_videos` (parameterised via `AnalyticsContentSource`), `saved_properties`, `followers` |
| `network_service` | `builder_networks`, `network_leads`, `network_referrals`, `network_commissions`, `network_performance`, `network_channels` |
| `social_service` | `social_accounts_safe` **(view)**, `social_share_preferences`, `social_share_logs`, `social_share_queue`, `social_ad_campaigns`, `social_ad_leads` |
| `subscription_service` | `subscriptions`, `billing_profiles`, `billing-history` **(Edge Function, read)** |
| `profile_view_service` | `profile_views` |
| `ratings_service` | `user_ratings` |

All six are **write-free** (zero `insert`/`update`/`upsert`/`delete`/`rpc`).

#### Two follower metrics — clarification (discovered; **absent from V1**)

These look contradictory and are not:

| Surface | Source | Why |
|---|---|---|
| Profile "Followers" tile | accepted `builder_networks` via `NetworkService.getAcceptedCount` | Standing instruction: match the React portal, do not use the unused `followers` table |
| Dashboard ▸ Audience followers | `followers` table | React's `BrokerAudienceInsights` / `IndividualAudienceInsights` / `InfluencerAudienceInsights` all read `followers` |

Both are faithful to React. `followers` is currently empty, so the Audience
figure legitimately reads 0. **Do not "fix" either to match the other.**

#### Security rule (discovered; **absent from V1**)

`social_accounts` carries six encrypted OAuth columns. All reads go through the
`social_accounts_safe` view, which excludes them. **Tokens must never reach a
client.** Any future social work inherits this rule.

### 2.6 Money units by domain (discovered; **absent from V1**)

Getting this wrong misstates figures by 100×.

| Domain | Storage | Handling |
|---|---|---|
| Billing (`payments`, `invoices`, `refunds`) | integer **minor units** (paise) | ÷100 once, in `BillingHistoryItem.fromJson` |
| Social ads (`social_ad_*`) | integer **minor units** | `formatMinorAmount()` |
| Network (`network_commissions`, referrals) | `numeric` **rupees** | no division; `formatRupeeAmount()` |

### 2.7 Quality baseline

| Metric | Value |
|---|---|
| Analyzer | 486 issues — 2 error / 28 warning / 456 info; **zero new** across all nine phases |
| Tests | 28 suites, 537 tests, 536 passing |
| APK | debug builds clean |
| Small-screen | every new screen probed at 320×568 with maximal data |

Four real overflows were caught by those probes and fixed in-phase (MetricCard
4.3px, plan card 277.8/246, bordered ToggleRow, `NetworkDetailRow` 375/220).

---

## 3. Remaining work

Only work **not** yet implemented appears here.

### Phase 10 — Transactional flows · **BLOCKED**

Delivers the last 3 design screens.

- `isCheckout`, `isPaymentSuccess`, `isRefundFlow` (3 steps)
- Meta OAuth connection; campaign and channel creation
- Retires 15 write placeholders (Cancel Subscription, Edit Billing Details,
  Download Invoice, Create Referral, Create Channel, Bulk Message, Export CSV,
  Lead Settings, Contact Support, Raise a Ticket, Payment Methods, plan checkout)

**Blocked on:** Razorpay mobile strategy · Meta OAuth mobile redirect strategy.
First phase to move money — requires a different risk posture and its own
approval gate.

### Phase 11 — Drift cleanup · unblocked, low risk

- Retire the P5/P6/P9 re-export shims by repointing imports
- Consolidate `UpperCaseTextFormatter` (duplicated across two registration screens)
- Consolidate `DashboardEmptyState` vs `EmptyStateView`
- Delete orphaned `lib/models/profile_model.dart` → analyzer reaches **0 errors**
- Repair `test/widget_test.dart` (`ProviderNotFoundException`) → suite fully green
- Decide the fate of `WorkspaceDestinations.comingSoon` (now unreferenced)

### Phase 12 — Global Network Search & Public Profile · unblocked, needs decisions

Search profiles → open public profile → Join Network → Message.
Absent from V1, from the design, and from the app; present in React.

- **12.1** People search — `profiles_public`, `.or(display_name, company_name, bio)`
- **12.2** Public profile — port `UserProfile.tsx`; Properties│Networks tabs
- **12.3** Join Network — 4-state machine `none` / `pending_sent` /
  `pending_received` / `connected` over `builder_networks` +
  `builder_network_invitations`
- **12.4** Message — wiring only; `MessagingService.startConversation` exists

**Hard requirement:** phone and email are exposed **only** when connected or
viewing your own profile (`UserProfile.tsx:2024-2025`). Enforce at the query
layer, not in the widget tree. Requires an explicit test.

**Two properties that make this phase different:**
1. **No design exists** — the first phase without a visual source of truth.
2. **Writes resume** — Phases 5–9 were strictly read-only.

Full specification: `docs/BLUEPRINT_ADDENDUM_PHASE_12_GLOBAL_NETWORK_SEARCH.md`
(now superseded by this section; retained for its detail).

### Phase conflict check

No duplicate or conflicting phases. 1A–9 are closed and immutable; 10, 11 and 12
are disjoint in scope; 11 and 12 are independent of 10 and of each other.

---

## 4. Technical debt

All pre-existing; none introduced by Phases 1A–9.

| Item | Impact | Fix |
|---|---|---|
| `lib/models/profile_model.dart` — 2 analyzer errors (`equatable` not in pubspec) | **None at runtime** — imported nowhere, excluded from the build | P11 |
| `test/widget_test.dart` fails — `ProviderNotFoundException` for `VoiceAgentProvider` | CI cannot be treated as green | P11 |
| `UpperCaseTextFormatter` duplicated ×2 | Drift risk | P11 |
| `DashboardEmptyState` vs `EmptyStateView` | Two empty-state implementations | P11 |
| 28 warnings / 456 info (mostly deprecated `withOpacity`) | Cosmetic | P11 |
| 5 duplicate **private** class names | None — file-scoped, genuinely different widgets | Accept |
| `auth_provider.dart` +15 lines | Additive `profiles`-row cache (blueprint §10), made during Profile work, pre-contract. No auth/session/RBAC behaviour changed | Accept; documented |
| No staging Supabase project | Contract §D.2 asks for staging validation; all verification was read-only against production | Product decision |

---

## 5. Future enhancements (not scheduled)

- Rich-text article editing (deliberately deferred; no editor dependency)
- Live Meta Insights — reach, CTR, engagement (React defers these too)
- Referral count — React hardcodes `totalReferrals = 0`; needs a real query
- Editable Social Preferences (`savePreferences` exists in React)
- Editable Network Communication settings — **would require schema work**, since
  no per-network notification column exists
- Network invitation accept/decline, lead status updates, assignment rules
- Deep-link parity for public profiles (React serves 6 URL shapes)
- React surfaces with no mobile design and no current demand: `seo`, `team`, `tools`

---

## 6. Open product decisions

| # | Decision | Blocks |
|---|---|---|
| 1 | Razorpay mobile strategy | P10 |
| 2 | Meta OAuth mobile redirect strategy | P10 |
| 3 | **Plan taxonomy conflict** — design ladder (free/plus/pro/concierge, ₹0/9/19/49) vs `planConfig.ts` (free/pro/builder/enterprise, USD). `subscriptions.plan` stores the latter; neither is derivable from the other | Upgrade + Features accuracy |
| 4 | Mobile design for Phase 12, or authorisation to derive from React | P12 |
| 5 | Confirm RLS permits Phase 12's membership writes — contract forbids changing RLS | P12 |
| 6 | Phase 12 search entry point — People section in global search, or Network ▸ Find People | P12 |
| 7 | Enable `savePreferences` writes | Future |
| 8 | Staging Supabase project | Validation confidence |
