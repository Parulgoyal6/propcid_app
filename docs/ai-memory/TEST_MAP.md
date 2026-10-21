# Test Map

Current test suite mapped to features, from a read-only audit (2026-09-26). 115 `.dart` files under `test/` (102 at the root, plus `core/`, `providers/`, `screens/`, `services/`, `support/` subfolders). Almost every test file opens with a header comment stating exactly what bug/regression it pins — that authorship is the source for the "what it protects" descriptions below, not inference. No intentionally disabled tests were found via `skip: true` or `@Skip` (verified by repo-wide grep, re-confirmed 2026-09-26). One occurrence of `skip: false` exists (`test/collaboration_marketplace_test.dart:698`) — this does **not** disable that test; `skip: false` is the explicit non-skipped state, functionally identical to omitting the parameter. Do not read "no skip markers" as "zero occurrences of the word `skip`."

**Test-type key**: unit = pure Dart, no `testWidgets`; widget = `testWidgets` against fakes; integration-like = a widget test driving a real multi-step screen/provider chain end-to-end.

**No mock framework is used anywhere** — `test/support/fake_*.dart` files subclass real services and override only the network-touching methods, so no live Supabase call is ever made in a test run.

## Auth, Onboarding & Session

| File | Type | Protects |
|---|---|---|
| `auth_screen_test.dart` | widget | Real keyboard/focus behavior; Sign Up exercised end-to-end, Sign In/Google/OTP deliberately not tapped |
| `auth_otp_verification_type_test.dart` | unit | Correct OTP type mapping (`signup` vs `magiclink`) from server response |
| `providers/auth_navigation_test.dart` | widget | AuthProvider is the sole owner of post-auth navigation |
| `providers/auth_provider_test.dart` | unit/widget-adjacent | AuthProvider state machine against `FakeAuthService` |
| `services/auth_resolver_test.dart` | unit | `AuthResolver.classify` routing table, incl. `is_blocked` outranking a complete profile |
| `services/auth_service_error_mapping_test.dart` | unit | Edge-function error-mapping parity |
| `screens/account_type_screen_test.dart` | widget | Only the 4 real user types offered; upsert never touches `user_role` |
| `account_deletion_screen_test.dart` | widget | Phone-account email regex parity; 14-day grace warning renders |
| `route_protection_test.dart` | widget | A flag-disabled route can't be reached via direct navigation, not just hidden from menus |
| `workspace_navigation_gates_test.dart` | widget | Gated destinations never render in the Workspace Drawer when flags are off |

## Listing / Post-Property Wizard (T0–T11 parity series)

The T0–T11 files (`listing_constants_parity_test.dart` through `listing_pricing_t11_test.dart`) individually pin each migration phase described in `docs/migrationn/final-architecture-review.md` §Q14 — constants/allow-list, data-contract renames, validation port, step-visibility, media, builder-tag, and per-category field closure (residential/others/land/pg/commercial). See `MODULE_MAP.md` for the full file list.

| File | Type | Protects |
|---|---|---|
| `listing_edit_hydration_crash_test.dart` | unit | `initFromRawData()` must never throw on a malformed field, and must not abort hydration of fields assigned after it |
| `post_property_metadata_roundtrip_test.dart` | unit | NEW-1 fix: editing a web-created listing no longer destroys metadata keys the app's own form doesn't collect |
| `post_property_route_gate_test.dart` | widget | 4-case role-gate decision table for `/post-property`, `/add-project`, influencer video wizard — **failing as of the 2026-09-23 log, see Known Issues** |
| `post_property_shell_layout_test.dart` | widget | Wizard shell has no overflow at smallest target viewport/step/category |
| `add_project_wizard_test.dart` | integration-like | Builder project wizard end-to-end — **14 failures as of the 2026-09-23 log** |
| `wizard_end_to_end_test.dart` | integration-like | Full walkthrough for all 12 category × listing-type combos — **18 failures (all) as of the 2026-09-23 log** |
| `builder_project_foundation_test.dart` | unit | Builder-project model NOT-NULL/CHECK parity — **2 failures as of the log** |
| `project_detail_test.dart` | widget | Owner-vs-visitor edit visibility, share dedup — **9 failures (all) as of the log** |

## Article / Content Editor

Not previously mapped here despite existing since baseline — a genuine pre-existing gap in this file, not new coverage. `article_content_converter_test.dart` (HTML↔Delta round-trip, incl. the center/right-alignment regression test — see `CHANGELOG.md`), `article_editor_autosave_test.dart`, `article_editor_image_upload_test.dart`, `article_html_test.dart`, `article_media_service_test.dart`. The first two were updated 2026-09-30 alongside the `cms-posts-save` Edge Function migration (see `DECISIONS.md`) to drop assertions against the now-removed `ArticleModel.isEditable`/`ArticleEditorProvider.isLocked` lock.

## Listing / Post-Property Wizard (T0–T11 parity series) — additional file

`property_submission_confirmation_screen_test.dart` (added 2026-09-29) — regression coverage for the confirmation screen no longer treating a non-null `propertyId` as "the listing is live" regardless of real `approval_status`; asserts pending-approval copy and no auto-offered "Publish Everywhere" for anything other than an `approved` listing. `listing_others_t7_test.dart` (added 2026-09-29) is one more file in the existing T0–T11 series, covering the Others/PG category — see the section below for what that series pins collectively.

## Media / Uploads

`article_media_service_test.dart`, `profile_media_service_test.dart` — bucket/path/MIME convention correctness (live upload itself explicitly out of scope, needs a live bucket+session). `public_media_url_test.dart` — `MEDIA_URL` rewrite only applies to public URLs, unconfigured case is a no-op, misconfigured case fails loud. `influencer_video_test.dart`/`_form_test.dart` — CHECK-constraint vocabulary, real 50MB bucket limit (not the portal's stated 200MB). `influencer_media_service_test.dart` (fixed: compressed `.mov` uploaded mislabeled as `video/quicktime` despite genuinely-MP4 bytes, and an unsupported fallback format was never rejected before upload), `property_media_upload_test.dart` (fixed: no pre-upload format/size gate at all — a `.mov` property video reached Storage unconverted and was rejected there), `project_media_service_test.dart` (same `.mov` gap as property videos, since project videos also upload uncompressed).

## Messaging / Chat / Collaboration / Network / Social

`chat_thread_report_test.dart` (fixed channel-reporting no-op bug), `messaging_collab_hidden_test.dart`, `collaboration_marketplace_test.dart` (model/eligibility/stepper/upload validation), `notification_collab_filter_test.dart`, `network_invitations_test.dart`, `network_communication_test.dart` (updated 2026-09-29 for the Network ▸ Communication create-channel sheet's manual-member picker removal), `network_relationship_test.dart` (also covers `NetworkRelationshipsProvider`'s Sent/Received request actions — cancel/accept/decline), `network_analytics_test.dart`, `profile_connection_actions_test.dart` (3 production-risk scenarios: insert-vs-upsert, sender/recipient direction, legacy-invitation-only visibility), `phase6_network_social_upgrade_test.dart`, `phase7_subscription_billing_test.dart`, `phase8_social_test.dart`, `phase9_network_test.dart`, `my_networks_screen_test.dart` (My Networks' Total Connections/Requests Sent/Requests Received tile-tap-to-switch-list fix), `reel_share_dm_test.dart` (added 2026-09-29 — reel-share-in-DM: write → fetch → hydrate → render → tap-through end-to-end, plus non-regression for property/text/image/channel messages; see `API_CONTRACTS.md`).

## Notifications

`notification_centre_test.dart` — query shape, type→style/filter mapping with safe unknown fallback, derived (not separately tracked) unread count, optimistic mark-read rollback, realtime dedup, routing table.

## Profile

`user_profile_model_test.dart`, `public_profile_parity_test.dart`, `public_profile_collab_button_test.dart`, `public_profile_device_validation_test.dart` (geometry-based overflow probe — explicitly **not** real device validation, no emulator/adb available), `profile_builder_projects_test.dart` (**4 failures, all, as of the log**), `profile_rating_test.dart`, `profile_view_recording_test.dart`, `profile_views_test.dart`, `edit_profile_parity_test.dart` (3 highest-consequence bugs: non-merging `social_media` write, half-written column pairs, trigger-guarded column no-ops), `edit_profile_document_upload_test.dart`, `number_format_test.dart`.

## Search

`people_search_test.dart`, `search_bar_parity_test.dart` (deliberately pumped under real `AppTheme.lightTheme` since the bug originated in the theme itself), `providers/property_provider_search_test.dart`.

## Release Gating / Feature Flags

`launch_features_test.dart` (every flag defaults false under the exact config `flutter test` runs with), `premium_launch_gate_test.dart`, `premium_launch_banner_layout_test.dart`, `social_publish_gates_test.dart`.

## Dashboard / Analytics

`dashboard_analytics_source_test.dart`, `dashboard_role_metrics_test.dart`, `dashboard_design_parity_test.dart`, `dashboard_regression_test.dart`, `cross_content_insights_widget_test.dart`, `cross_content_insights_parsing_test.dart`, `dashboard_cross_content_provider_test.dart`, `cross_content_routing_test.dart`, `broker_sections_test.dart` (**1 failure as of the log**), `builder_sections_test.dart`, `builder_dashboard_b3_test.dart`, `builder_inventory_summary_test.dart`, `my_listings_status_test.dart`.

## Home / Influencer / Reels

`home_scroll_performance_test.dart` (3 silent perf bugs fixed), `home_reels_categories_test.dart`, `home_upgrade_test.dart`, `category_directory_screens_test.dart`, `floating_ai_orb_test.dart`, `reels_screen_layout_test.dart`, `reel_share_link_test.dart` (**2 `shareUrl` failures — see `KNOWN_ISSUES.md` KI-17**), `influencer_routing_test.dart`, `influencer_quick_actions_test.dart`, `reels_activity_state_test.dart` (fixed: a liked/saved listing-video reel never appeared under My Activity's Reels filter, and its like count double-counted a pre-existing like).

## Visits / Bookings / Enquiries

`visits_screen_test.dart`, `visit_booking_service_test.dart`, `booking_enquiry_validation_test.dart`.

## Shared UI / Layout Infrastructure

`shared_components_test.dart`, `shell_overflow_probe.dart` (**marked "temporary, deleted after use" in its own header — still present**, flag for cleanup), `settings_sheet_test.dart`, `widget_test.dart` (app-smoke test — **failing as of the 2026-09-23 log** with a `ProviderNotFoundException` for `CompareProvider`; needs a fresh run to confirm current status).

## Test Gaps (documented by the test authors themselves, not inferred)

1. No live-backend verification anywhere — every Supabase-touching test uses a fake/subclassed service or an unreachable `SupabaseClient`. RPCs, storage uploads, and realtime behavior beyond client-side handler logic are out of scope.
2. No real device/emulator validation exists in this environment (`public_profile_device_validation_test.dart` states this explicitly). It references `docs/impact-reports/PHASE_1_DEVICE_VALIDATION.md` for the remaining human-on-hardware checklist — **that file does not currently exist**, only the 5 `*_IMPACT_REPORT.md` files and 6 baseline `.txt` logs are present. Worth flagging to whoever owns doc reconciliation.
3. Video duration probing (`collaboration_marketplace_test.dart`) needs `video_player` platform channels unavailable under `flutter test` — documented gap, not silent.
4. `shell_overflow_probe.dart` — self-described temporary probe, still checked in.
5. No test file targets `lib/services/rbac_service.dart` directly — consistent with it being dead code (see `KNOWN_ISSUES.md`); role-gating is verified indirectly through route-gate/screen tests instead.
6. No dedicated test file for `VoiceAgentProvider` / the voice assistant. This gap now also covers the new `FEATURE_VOICE_ASSISTANT` flag (added 2026-09-30) — confirmed via grep that `launch_features_test.dart` has zero references to it, so the 4th flag's fail-closed default is untested even though the other three are (per `launch_features_test.dart`'s existing coverage).
7. No test file targets `lib/services/resubmit_for_approval.dart` directly (added 2026-09-29) — the demote-to-pending behavior it implements for properties/projects/broker profiles is exercised only indirectly, if at all, by each caller's own existing tests. Worth a dedicated unit test given it gates a moderation-bypass-adjacent behavior.

## Captured Log Snapshots (2026-09-23, 3 days before this audit — treat as "last known state," not current truth)

- **`full-test-serial.txt`** (full `flutter test` run): **1689 passing, 56 failing.** Failures cluster in `add_project_wizard_test.dart` (14), `post_property_route_gate_test.dart` (7, essentially the whole gate decision table), `project_detail_test.dart` (9, all), `wizard_end_to_end_test.dart` (18, all), `profile_builder_projects_test.dart` (4, all), `builder_project_foundation_test.dart` (2), `broker_sections_test.dart` (1), `widget_test.dart` (1, its only test — `ProviderNotFoundException` for `Consumer<CompareProvider>`). The spread across unrelated domains but shared widget-tree/provider-construction symptom suggests **one shared harness/provider-tree regression**, not 56 independent bugs — worth a focused re-run before triaging individually. See `KNOWN_ISSUES.md`.
- **`wizard-single-test.txt`**: a single narrow debug run of one test in `wizard_end_to_end_test.dart` — passed. Not representative of the full file (which shows 18 failures in the full run above); not a contradiction, just a much smaller slice.
- **`analyzer-output.txt`**: 549 issues, 0 errors/warnings, all `info`-level (deprecated `withOpacity`, lint style). Baseline in `docs/REGRESSION_PROTECTION_CHECKLIST.md` was 447 issues (2026-08-05) — **+102 info-level drift**, low severity but real against that doc's "no new issues vs. baseline" gate.

**A fresh `flutter test` / `flutter analyze` run is the only way to know whether these are still the current numbers** — none was run during this read-only audit.
