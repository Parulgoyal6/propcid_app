# Known Issues

Verified from current code, explicit TODO/FIXME markers, currently-failing tests, or applicable existing documentation, as of a read-only audit on 2026-09-26. Nothing here is a suspicion promoted to a fact — each entry has a cited source. Statuses: OPEN, INVESTIGATING, BLOCKED, RESOLVED. Nothing is marked RESOLVED without direct evidence.

---

## KI-1: 56 failing tests in the 2026-09-23 full-test-run snapshot

**Status**: INVESTIGATING (unverified whether still current)

`full-test-serial.txt` (captured 2026-09-23, 3 days before this audit) shows 1689 passing / 56 failing. Failures cluster in `add_project_wizard_test.dart` (14), `post_property_route_gate_test.dart` (7), `project_detail_test.dart` (9, all), `wizard_end_to_end_test.dart` (18, all), `profile_builder_projects_test.dart` (4, all), `builder_project_foundation_test.dart` (2), `broker_sections_test.dart` (1), `widget_test.dart` (1, its only test — `ProviderNotFoundException` for `Consumer<CompareProvider>` inside `lib/widgets/compare_floating_bar.dart`).

`widget_test.dart`'s own header comment describes a "Phase 11" repair for a similar `ProviderNotFoundException` class of bug affecting 4 *other* providers (AuthProvider, ReelsProvider, AvailableLocationsProvider, VoiceAgentProvider) — `CompareProvider` is not mentioned in that repair note, so this is either (a) a pre-fix log, already resolved in current code, or (b) a newer regression where `CompareProvider` was added to the widget tree without being added to the test harness.

**Why unresolved**: the spread across unrelated domains (routing, builder projects, project detail, profile content, the smoke test) sharing a widget-tree/provider-construction symptom suggests one shared harness/provider-tree regression, not 56 independent feature bugs.

**Next step**: run `flutter test` fresh and compare against this snapshot before assuming any of these failures still exist or are new.

**Source**: `full-test-serial.txt` (root), `test/widget_test.dart` header comment.

---

## KI-2: Analyzer lint drift vs. documented baseline

**Status**: OPEN

`analyzer-output.txt` (2026-09-23): 549 `info`-level issues, 0 errors/warnings. `docs/REGRESSION_PROTECTION_CHECKLIST.md`'s baseline (2026-08-05, cross-confirmed by `docs/impact-reports/baseline-analyze.txt`): 447 issues. That's +102 info-level drift (deprecated `withOpacity`→`.withValues()`, `sort_child_properties_last`, `unnecessary_underscores`, `unnecessary_import`, deprecated `renderViewElement`) against that checklist's own "no new issues vs. baseline" gate. Low severity (no errors/warnings), but real drift.

**Source**: `analyzer-output.txt` (root), `docs/REGRESSION_PROTECTION_CHECKLIST.md`, `docs/impact-reports/baseline-analyze.txt`.

---

## KI-3: Buyers cannot cancel their own property visit bookings

**Status**: OPEN — expected backend-policy blocker; current server policy not independently verified.

**Verified from Flutter implementation**: `lib/services/visit_booking_service.dart`'s `cancelBooking` (line ~183) issues a genuine update attempt against the `property_visit_bookings` table, and the code does not fake success — whatever the server returns is surfaced to the user as-is, nothing is silently swallowed.

**Expected server contract, per client comments — not independently verified**: the file's own header comment (lines 27-38) states that as of migration `20260314133000_add_property_visit_bookings.sql`, RLS has no policy allowing a visitor to update/delete their own booking — only the property owner may update a row's status. This migration/policy is not present in this repository, so the claim that a buyer's cancel attempt is currently rejected server-side is taken on the client code comment's word, not confirmed by reading the actual RLS policy. Treat this as a likely, well-evidenced blocker, not a proven one, until the server policy is checked directly.

**Source**: `lib/services/visit_booking_service.dart:27-38, ~183`.

---

## KI-4: Live temporary debug-trace block signals unresolved edit-hydration uncertainty

**Status**: INVESTIGATING

`PropertyService.fetchForEdit` (`lib/services/property_service.dart:514-571`) contains an active block of `debugPrint('[EDIT_TRACE] ...')` calls with a comment explicitly labeling it "TEMPORARY — P0 real-device edit-hydration trace. Remove once the reported bug (Portal-created listings edit blank in the app) is confirmed fixed on-device." Despite the corresponding fix (metadata merge-on-update, `updateProperty` lines 618-695) being merged and covered by tests (`post_property_metadata_roundtrip_test.dart`, `listing_edit_hydration_crash_test.dart`), the presence of this still-live instrumentation is a direct signal from the code's own author that on-device confirmation had not happened as of this snapshot.

**Source**: `lib/services/property_service.dart:514-571`. See also `HIGH_RISK_AREAS.md`.

---

## KI-5: `RBAC_IMPLEMENTATION_GUIDE.md` describes a largely dead role architecture

**Status**: OPEN (documentation/code mismatch, not a runtime bug)

The doc describes a two-axis role model (`user_role: buyer/seller` + `user_type: individual/builder/broker/influencer`) enforced via `RBACService`, `RoleGuard`/`BuyerOnly`/`SellerOnly`/etc. widgets, and a `ProfileCompletionCoordinator`. All of these exist as files but are **orphaned** — `RBACService` is instantiated only by 3 screens that are themselves unreachable from any live route; `role_guard.dart`'s widgets have zero references anywhere else in `lib/`; `ProfileCompletionCoordinator` has zero references outside its own file. The live app instead uses a single-axis model driven by `user_type` alone (see `CURRENT_ARCHITECTURE.md` → Roles), via `AuthResolver.classify`. **No live code path ever writes `user_role = 'buyer'`** (confirmed by exhaustive grep); only 3 dead screens write `user_role = 'seller'`.

**Recommendation for the team** (not acted on by this audit): confirm whether these orphaned RBAC components (`rbac_service.dart`, `role_guard.dart`, `profile_completion_coordinator.dart`, and the unreachable `profile_completion/{builder,broker,influencer}_profile_screen.dart` files) are safe to delete or are being kept for a planned reintroduction of the buyer/seller axis.

**Source**: `RBAC_IMPLEMENTATION_GUIDE.md` (root), `lib/services/rbac_service.dart`, `lib/widgets/role_guard.dart`, `lib/services/profile_completion_coordinator.dart`, `lib/services/auth_resolver.dart`.

---

## KI-6: Inconsistent column used for "is staff admin" detection

**Status**: OPEN

`lib/providers/article_editor_provider.dart:115-118` checks `profiles.user_type == 'admin'/'super_admin'` to grant immediate-publish rights (line numbers shifted slightly from the original 125-132 citation after the 2026-09-30 article-service refactor; the check itself is unchanged). `lib/services/property_service.dart` (`_checkApproval`, ~line 1702) and `lib/screens/social/social_campaigns_screen.dart:48-58` instead check `profiles.user_role == 'admin'/'super_admin'`. **A third site now exists to the same pattern**: the new shared `lib/services/resubmit_for_approval.dart` (added 2026-09-29) also checks `user_role` (`_adminRoles = ['admin', 'super_admin']`) before deciding whether to demote a row back to pending on a non-admin's edit — consistent with the `user_role`-reading sites, not a new inconsistency, but one more place a future fix must touch if this is ever reconciled. Different client code paths use `user_type` and `user_role` for the same staff-admin decision. The canonical backend/admin-provisioning field cannot be established from this repository alone; both could theoretically be populated. This needs resolving with whoever owns backend/admin-provisioning, not a guess from this repo alone.

**Source**: `lib/providers/article_editor_provider.dart:115-118`, `lib/services/property_service.dart` (`_checkApproval`), `lib/screens/social/social_campaigns_screen.dart:48-58`, `lib/services/resubmit_for_approval.dart`.

---

## KI-7: `docs/BLUEPRINT_ADDENDUM_PHASE_12_GLOBAL_NETWORK_SEARCH.md` is stale — claims "not started" but the feature is implemented

**Status**: RESOLVED in code, doc not yet updated

The doc's header states "Status: Specified, not started" (dated 2026-08-04). Current code contradicts this directly: People search (§12.1), the public profile screen (§12.2), the Join Network state machine (§12.3, `ProfileConnectionStatus` enum in `profile_connection_service.dart:67-81`), and Message wiring (§12.4) are all fully implemented, including the doc's own "non-negotiable" contact-detail gating rule (verified verbatim in `PublicProfileProvider.canSeeContactDetails`). The work landed under a different internal phase label ("Phase 6"/"Stage 1/2" per `public_profile_screen.dart`'s own header comments) rather than "Phase 12."

**Source**: `docs/BLUEPRINT_ADDENDUM_PHASE_12_GLOBAL_NETWORK_SEARCH.md`, `lib/services/people_search_service.dart`, `lib/services/profile_connection_service.dart:67-81`, `lib/screens/profile/public_profile_screen.dart`, `lib/providers/public_profile_provider.dart:109`.

---

## KI-8: `docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md` is stale — claims the builder-project wizard/inventory "does not exist"

**Status**: RESOLVED in code, doc not yet updated

The doc's §2 current-state table and §3 gap analysis (G1-G12) claim the project wizard, project detail, inventory, offers, and team screens don't exist. Current code has substantially built the plan's own Phase B1-B8 roadmap: `lib/models/project_model.dart`, `lib/services/project_service.dart`, `lib/screens/add_project/*`, `lib/providers/add_project_provider.dart`, `lib/screens/project/project_detail_screen.dart`, inventory/offers/team screens under `lib/screens/team/`. The dashboard defect the doc flags (builder "Add Project" wrongly opening the property wizard) is also fixed, with the fix's own code comment (`builder_dashboard_screen.dart:353`) explicitly noting the old behavior it replaced.

**Source**: `docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md`, see `MODULE_MAP.md` → Builder Projects & Inventory for the full file list.

---

## KI-9: `VOICE_ASSISTANT_IMPLEMENTATION_PLAN.md` is stale — claims listing CRUD and logout/delete-account tools are "out of scope for v1"

**Status**: RESOLVED in code, doc not yet updated

The plan explicitly defers `create_listing`/`update_listing`/`delete_listing`/`publish_listing` and `logout`/`delete_account` to a later phase. Current code has all of these fully registered and implemented in `lib/voice_agent/tools/property_tools.dart` and `profile_tools.dart`, including a guided multi-turn slot-fill flow for `create_listing` described in `lib/voice_agent/prompt/system_prompt.dart:260-301`. The plan's proposed file layout was also superseded — implementation landed under a dedicated `lib/voice_agent/` package rather than scattered into the app's existing `lib/models`/`lib/services`/`lib/providers` directories as the plan proposed.

**Source**: `VOICE_ASSISTANT_IMPLEMENTATION_PLAN.md`, `lib/voice_agent/tools/property_tools.dart`, `lib/voice_agent/tools/profile_tools.dart`, `lib/voice_agent/prompt/system_prompt.dart:260-301`.

---

## KI-10: `claude.md`'s "Phase 0 only" framing understates what's actually implemented

**Status**: OPEN (framing/documentation issue, not a code bug)

Root `claude.md` frames metadata edit-mode fixes as "the first implementation phase" and says not to begin category-parity work (T6-T11 style) until that's done. Current code shows T0 through roughly T5/T6+ (shared constants, validation port, step-visibility, media, builder-tag, and NEW-1/3/4/5 fixes from `docs/migrationn/final-architecture-review.md`) are already implemented and cited by their own review-doc finding numbers in code comments (e.g. `property_service.dart:798-818, 1375-1378` cite "final-architecture-review NEW-5" directly). This doesn't mean the workstream is complete (see KI-4 for the still-open on-device confirmation), but the "don't start T6+ yet" framing in `claude.md` is inconsistent with what's on disk. Flag before assuming `claude.md`'s phase framing is current.

**Source**: root `claude.md`, `lib/services/property_service.dart` (multiple cited line ranges), `docs/migrationn/final-architecture-review.md`.

---

## KI-11: `claude.md` references a doc path that doesn't exist (`docs/migration/` vs actual `docs/migrationn/`)

**Status**: OPEN — minor, but breaks the documented source-of-truth chain

`claude.md` (root, lines 14-15) cites `docs/migration/migration-specification.md` and `docs/migration/final-architecture-review.md` (singular "migration"). The actual folder on disk is `docs/migrationn/` (double "n"). The referenced files exist, just under a differently-spelled path. Confirmed independently by two separate audit passes.

**Source**: root `claude.md:14-15`, actual folder `docs/migrationn/`.

---

## KI-12: Three voice-agent environment/config variables are configured but inert

**Status**: OPEN

`VOICE_AUTONOMOUS`, `VOICE_ALWAYS_CONFIRM`, and `RAG_GROUNDING` (three variables, not two) exist as `.env` keys but a repo-wide grep of `lib/` found zero references to those key names. These are **not** the app's `LaunchFeatures` compile-time feature flags (`FEATURE_SUBSCRIPTIONS`/`FEATURE_PAID_COLLABORATIONS`/`FEATURE_META_PUBLISHING`, see `CURRENT_ARCHITECTURE.md` → Feature Flags) — they're a separate, voice-agent-specific set of env vars that simply aren't wired to anything. `lib/voice_agent/config/ai_config.dart`'s equivalent flags (`isAutonomous`, `alwaysConfirmIntents`, `isRagGroundingEnabled`) are hardcoded Dart getters instead, with inline "Phase 2/3" TODO comments. Not wired up as of this audit.

**Source**: `.env`, `lib/voice_agent/config/ai_config.dart`.

---

## KI-13: Two possibly-duplicate shortlist state sources

**Status**: INVESTIGATING (not yet reconciled)

`lib/providers/shortlist_provider.dart` (32 lines, thin) exists as a separate top-level provider from `PropertyProvider`'s own shortlist state (`toggleShortlist`/`isShortlisted`/`_syncShortlistFlags` in `property_provider.dart`). Whether these are consistent, redundant, or serve genuinely different call sites was not resolved by the underlying audit — flagged as a targeted follow-up, not a confirmed bug.

**Source**: `lib/providers/shortlist_provider.dart`, `lib/providers/property_provider.dart` (lines 156-192, 571-607).

---

## KI-14: iOS bundle ID is still the Flutter placeholder

**Status**: OPEN

`ios/Runner.xcodeproj/project.pbxproj` still declares `PRODUCT_BUNDLE_IDENTIFIER = com.example.propcidApp` (Flutter's generated placeholder), mismatched from Android's `com.propcid.app`. The code's own comments (`ios/Runner/Runner.entitlements`) confirm this blocks Universal Links from being fully configured. Not something to "fix" casually — may be intentionally deferred to iOS App Store listing setup. See `RELEASE_SAFETY.md` for full detail.

---

## KI-15: Plaintext Google Maps API key committed to Android manifest

**Status**: OPEN

`android/app/src/main/AndroidManifest.xml` (lines 25-27) hardcodes a `com.google.android.geo.API_KEY` value in plaintext. Per `HIGH_RISK_AREAS.md`'s client-secret rule, any value shipped in the app package must be treated as recoverable by an end user — the safety boundary for this key is provider-side restriction (package name/SHA-1/API scope in the Google Cloud Console), which cannot be verified from this repository. See `RELEASE_SAFETY.md` for full detail.

---

## KI-16: Articles saved before the 2026-09-26 alignment-persistence fix still have unrecoverable alignment

**Status**: OPEN

`lib/core/utils/article_content_converter.dart`'s `articleDocumentToHtml` used to call `QuillDeltaToHtmlConverter` with default options, which emit block attributes (including center/right alignment) as CSS classes (`class="ql-align-center"`). `articleHtmlToDocument`'s `HtmlToDelta().convert()` (from `flutter_quill_delta_from_html`) only reads alignment from an inline `style="text-align:…"` value (or a legacy `align="…"` HTML attribute) — never from a `class` — so any article saved with center/right alignment before this fix has that alignment permanently absent from its stored `content`/`content_html`, not just hidden.

The fix (same date) makes `articleDocumentToHtml` pass `ConverterOptions(converterOptions: OpConverterOptions(inlineStylesFlag: true))`, so alignment is now written as `style="text-align:…"` and round-trips correctly for anything saved from now on. It does not — and cannot, from the client alone — recover alignment on rows already written with the old, class-based HTML; that data would need a one-time backfill (re-parse stored `content_html` for `ql-align-*` classes and rewrite it) if historical articles need their alignment restored.

**Source**: verified via `test/article_content_converter_test.dart`'s round-trip test (failed against class-based HTML before the fix, passes after) and direct inspection of `vsc_quill_delta_to_html-1.0.5`'s `OpConverterOptions`/`op_to_html_converter.dart` and `flutter_quill_delta_from_html-1.5.3`'s `default_html_to_ops.dart`/`html_utils.dart` in the pub cache.

---

## KI-17: `reel_share_link_test.dart`'s `ReelModel.shareUrl` tests fail against current code

**Status**: OPEN — discovered during an unrelated regression sweep (media-upload/reel-like-state fixes, 2026-09-26), not investigated further; not caused by that work.

Two tests fail in isolation, with no other test files loaded and nothing in `reel_model.dart`/`core/utils/profile_link.dart` touched by that session's changes:

- `ReelModel.shareUrl a property-backed reel links to that property` — expected `https://propcid.com/property/p-7/sea-view-3bhk`, got `https://propcid.com/property-reels/v-1/sea-view-3bhk`.
- `ReelModel.shareUrl an unlinked reel falls back to the feed, not a dead per-reel URL` — expected `https://propcid.com/property-reels`, got `https://propcid.com/property-reels/v-1/sea-view-3bhk`.

Both mismatches look like `reelShareUrl`'s routing (in whatever file defines it — not yet located) is currently building a `/property-reels/{id}/{slug}` link unconditionally, rather than branching on whether the reel carries a linked property, and rather than omitting the id/slug entirely when unlinked. Not investigated beyond confirming the failure is real, reproducible in isolation, and unrelated to the media-upload/reel-state fixes shipped the same day.

**Source**: `test/reel_share_link_test.dart` (`ReelModel.shareUrl` group), run in isolation via `flutter test test/reel_share_link_test.dart`.

---

## KI-18: 4 `notification_centre_test.dart` failures, reproducible in isolation

**Status**: OPEN — discovered during the same regression sweep as KI-17 (media-upload/reel-like-state fixes, 2026-09-26); not caused by that work and not investigated further. `notification_centre_test.dart` isn't touched, imported, or exercised by any file that fix changed.

Four `NotificationsScreen` tests fail both inside a full `flutter test` run (1998 passed / 7 failed total that day — the other 3 are KI-17's 2 plus `people_search_test.dart`'s pre-existing "See all people" failure, already logged) and in complete isolation (`flutter test test/notification_centre_test.dart` alone reproduces the identical 4 failures):

- `renders real rows with title, message and time` — `Expected: exactly one matching candidate; Actual: Found 0 widgets with text "1 new"` (an unread-count pill the test expects to render).
- `mark all read clears the pill`
- `a realtime arrival appears without a refresh`
- `lays out cleanly at 320 dp and 130% text`

All four look like one shared root cause (the missing/wrong "N new" unread-count pill), not four independent bugs, but this wasn't traced further — out of scope for the session that found it. A cosmetic-only notifications-screen commit (`18dfb92`, 2026-09-30) touched this screen's app bar since — it removed a decorative icon only, nothing related to the unread-count pill, so this remains unresolved and unverified.

**Source**: full-suite run captured 2026-09-26 (1998 passed, 7 failed), cross-checked by running `test/notification_centre_test.dart` alone.

---

## KI-19: A large (~17MB) root-level `.zip` was committed, then deleted in the working tree without a commit

**Status**: OPEN — repository hygiene, not a code bug.

Commit `498c412` ("artical edit approval fix", 2026-09-30) added a binary `.zip` file at the repo root (17,680,203 bytes, tracked as `.zip`) alongside that commit's real article-service changes — almost certainly an accidental `git add` of a local backup/archive rather than an intended source file. As of this audit, that file is deleted in the working tree (`git status --short` shows `D .zip`) but that deletion has not itself been committed, so the 17MB blob is still present in `HEAD`'s tree/history. This is a separate, later recurrence of the same class of issue already fixed once for `lib/`-scoped zips by `bbf477c` (see `CURRENT_ARCHITECTURE.md`'s repository-maintenance note).

**Not acted on by this audit** (this session only updates `docs/ai-memory/*`): confirm with whoever authored `498c412` whether the root `.zip`'s deletion should be committed, and consider whether that commit's history should be reviewed before the branch is merged, since the blob remains in git history either way once pushed.

**Source**: `git show 498c412 --stat` (`.zip | Bin 0 -> 17680203 bytes`), `git status --short` (`D .zip`) as observed 2026-09-30.

---

## KI-20: `workspace_navigation_gates_test.dart`'s "every ordinary destination is untouched" test fails, reproducible in isolation

**Status**: OPEN — discovered during the regression pass for the 2026-10-14 in-app-update change (see `CHANGELOG.md`); not caused by that change and not investigated further. The test file doesn't reference `HomeScreen`, `InAppUpdateService`, or any file that change touched.

`flutter test test/workspace_navigation_gates_test.dart` run completely alone (no other test files loaded) fails on `WorkspaceDrawer every ordinary destination is untouched`: `Expected: exactly one matching candidate; Actual: Found 0 widgets with text "Reels"`. Looks like `WorkspaceDrawer` no longer renders a "Reels" row the test expects, or renders it under different text/an icon only — not traced further.

**Source**: isolated run of `test/workspace_navigation_gates_test.dart`, captured 2026-10-14.
