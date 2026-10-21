# Module Map

Navigational map from a read-only audit (2026-09-26). Use this to locate functionality quickly; see `CURRENT_ARCHITECTURE.md` for how the pieces fit together and `API_CONTRACTS.md` for backend detail.

## App Shell / Bootstrap

- **Entry**: `lib/main.dart`, `lib/app.dart`, `lib/app_navigator.dart`
- **Config**: `lib/config/launch_features.dart` (feature flags), `lib/config/role_plan_config.dart` (pricing catalogue, not a flag system)
- **Navigation infra**: `lib/core/navigation/` — `invite_deep_link_handler.dart`, `pending_invitation_gate.dart`, `current_route_notifier.dart`, `manage_dashboard_dispatcher.dart`, `banner_destination_resolver.dart`, `notification_route_resolver.dart`, `post_property_route_gate.dart`, `workspace_destinations.dart`
- **Constants**: `lib/core/constants/app_constants.dart` (named-route strings), `lib/core/constants/project_options.dart`

## Authentication & Roles

- **Screens**: `lib/screens/auth/` — `auth_screen.dart`, `otp_screen.dart`, `account_type_screen.dart`, `individual_profile_details_screen.dart`, `individual_username_password_screen.dart`, `reset_password_screen.dart`
- **Registration wizards**: `lib/screens/profile_completion/{builder,broker,influencer}_registration/*.dart` (live) vs `lib/screens/profile_completion/{builder,broker,influencer}_profile_screen.dart` (orphaned — see `KNOWN_ISSUES.md`)
- **Provider**: `lib/providers/auth_provider.dart` — session state + sole owner of post-auth navigation
- **Services**: `lib/services/auth_service.dart` (all Supabase Auth calls), `lib/services/auth_resolver.dart` (pure profile→destination classifier), `lib/services/edge_functions_service.dart` (OTP/username-auth/account-deletion/data-export Edge Functions)
- **Dead RBAC layer** (do not build on this without confirming with the team first): `lib/services/rbac_service.dart`, `lib/widgets/role_guard.dart`, `lib/services/profile_completion_coordinator.dart`
- **Tests**: `test/auth_screen_test.dart`, `test/auth_otp_verification_type_test.dart`, `test/providers/auth_navigation_test.dart`, `test/providers/auth_provider_test.dart`, `test/services/auth_resolver_test.dart`, `test/services/auth_service_error_mapping_test.dart`, `test/screens/account_type_screen_test.dart`, `test/account_deletion_screen_test.dart`

## Property / Listing Domain

- **Models**: `lib/models/property_model.dart` (`PropertyModel`). `PropertyCategory` and `ListingIntent` are declared separately, in `lib/providers/post_property_provider.dart:61,63` (`enum PropertyCategory { residential, commercial, land, pg, other }`, `enum ListingIntent { sell, rent, lease }`), not in the model file.
- **Wizard**: `lib/screens/post_property/` — 8 steps under `steps/` + `review_step.dart`, `post_property_screen.dart`, `property_submission_confirmation_screen.dart`, `listing_field_keys.dart`, `listing_constants.dart`, `listing_value_aliases.dart`, `listing_validation_rules.dart`, `booking_enquiry_validation.dart`
- **Provider**: `lib/providers/post_property_provider.dart`
- **Service**: `lib/services/property_service.dart` (create/update/search/detail/edit-hydration/media upload)
- **Search**: `lib/providers/property_provider.dart`, `lib/providers/filter_provider.dart`, `lib/screens/search/*`, `lib/screens/filters/filters_screen.dart`
- **Details**: `lib/screens/property_detail/property_detail_screen.dart` (large, monolithic — 3700+ lines)
- **Visits**: `lib/services/visit_booking_service.dart`, `lib/screens/visits/visits_screen.dart` — see `KNOWN_ISSUES.md` (buyers can't cancel own bookings)
- **Enquiries**: `lib/services/property_inquiry_service.dart`
- **Favorites/Likes**: `lib/services/saved_properties_service.dart`, `lib/services/property_likes_service.dart`, `lib/providers/shortlist_provider.dart` (possible duplication with `PropertyProvider`'s own shortlist state — unresolved, see `KNOWN_ISSUES.md`)
- **Sharing**: `lib/screens/property_detail/widgets/share_property_sheet.dart` (link/social share) — distinct from `lib/services/project_share_service.dart` (network-notification-only "share")
- **Governing docs**: root `claude.md`, `docs/migrationn/migration-specification.md`, `docs/migrationn/final-architecture-review.md` (note the doc-folder is spelled `migrationn`, double n — `claude.md` itself references the singular-n path, which doesn't exist)
- **Tests**: the T0–T11 parity series (`test/listing_*_t*.dart`), `test/wizard_end_to_end_test.dart`, `test/post_property_*_test.dart`, `test/listing_edit_hydration_crash_test.dart` — see `TEST_MAP.md`

## Builder Projects & Inventory

- **Models/services**: `lib/models/project_model.dart` (full 30-column model), `lib/models/builder_project_model.dart` (legacy 10-field summary, deliberately kept), `lib/services/project_service.dart`
- **Wizard**: `lib/screens/add_project/` — `add_project_screen.dart`, steps under `steps/`, `project_field_keys.dart`, `project_validation_rules.dart`
- **Provider**: `lib/providers/add_project_provider.dart`
- **Detail/listing**: `lib/screens/project/project_detail_screen.dart`, `lib/screens/project/latest_projects_screen.dart`, `lib/screens/dashboard/widgets/my_projects_section.dart`
- **Inventory/offers/team**: `lib/screens/team/widgets/team_inventory_tab.dart`, `manage_units_screen.dart`, `lib/screens/dashboard/widgets/builder_inventory_summary.dart`, `builder_offers_section.dart`, `builder_offer_editor_sheet.dart`, `lib/screens/team/widgets/team_offers_tab.dart`, `lib/screens/team/team_workspace_screen.dart`
- **Likes/saves**: `lib/providers/projects_provider.dart`, `lib/services/project_likes_service.dart`, `lib/services/saved_projects_service.dart`
- **Media**: `lib/services/project_media_service.dart` (bucket `project-media`)
- **Governing doc**: `docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md` — stale, undersells what's implemented (see `KNOWN_ISSUES.md`)

## Media (cross-cutting)

- **Central URL resolver**: `lib/core/utils/public_media_url.dart` (`PublicMediaUrl.resolve`)
- **Per-domain services**: `lib/services/property_service.dart` (`_uploadMedia`), `lib/services/profile_media_service.dart`, `lib/services/project_media_service.dart`, `lib/services/chat_media_service.dart`, `lib/services/article_media_service.dart`, `lib/services/influencer_media_service.dart`
- **Reels**: `lib/services/reels_service.dart`, `lib/models/reel_model.dart`, `lib/screens/reels/widgets/reel_video_view.dart`

## Messaging / Chat / Realtime

- **Models**: `lib/models/chat_message.dart`, `lib/models/conversation_summary.dart`, `lib/models/channel_summary.dart`, `lib/models/message_reaction.dart`
- **Service**: `lib/services/messaging_service.dart` (1300+ lines — conversations, channels, reactions, edit/delete, block/report, forward)
- **Providers**: `lib/providers/messaging_provider.dart` (list-level: Chats/Channels/Collabs tabs), `lib/providers/chat_thread_provider.dart` (single-thread state)
- **Media**: `lib/services/chat_media_service.dart` (private `chat-media` bucket). Added 2026-09-30: `ChatMediaService.saveImageToGallery` downloads an approved image message's signed URL and writes it to the device gallery via the existing `gal` dependency (same package already used by the Digital Visiting Card download — no new dependency/permission); fails fast on web (`gal` has no web implementation). Wired from `ChatBubble`'s long-press action sheet as "Save image", shown only when `message.isImage && mediaStatus == approved`.
- **Reel sharing in DMs** (added 2026-09-29): a DM-only `messages.reel_id` column (never present on `channel_messages` — collaboration/reel-share are both 1:1-only) backs a `reel_share` message type. `lib/models/shared_reel_preview.dart` is a small chat-specific preview shape (deliberately not the full `ReelModel`, mirroring why `shared_property_preview.dart` exists), resolved server-side by `MessagingService.fetchSharedReels` against either `influencer_videos` or (for a listing-video reel) `properties_public`. Rendered by `lib/screens/messaging/widgets/reel_share_preview_card.dart`, hydrated in `lib/providers/chat_thread_provider.dart`. See `API_CONTRACTS.md`.
- **Screens**: `lib/screens/messaging/` — `chat_thread_screen.dart`, `channel_settings_screen.dart`, `blocked_users_screen.dart`, widgets: `create_channel_sheet.dart`, `chat_bubble.dart`, `chat_media_view.dart`, `collab_message_bubbles.dart`, `forward_message_sheet.dart`, `share_property_sheet.dart`, `reel_share_preview_card.dart`, `send_to_user_flow.dart`
- **Tests**: `test/chat_thread_report_test.dart`, `test/messaging_collab_hidden_test.dart`, `test/collaboration_marketplace_test.dart`, `test/notification_collab_filter_test.dart`, `test/reel_share_dm_test.dart` (reel-share-in-DM end-to-end: write → fetch → hydrate → render → tap-through, plus a non-regression check for property/text/image messages and channel behavior)

## Network / Social

- **Relationships**: `lib/models/network_relationship.dart` (`classifyRelationship`), `lib/services/network_relationship_service.dart`, `lib/providers/network_hub_provider.dart`, `lib/providers/network_relationships_provider.dart`
- **Invitations**: `lib/models/network_models.dart` (`NetworkInvitation`), writes live in `lib/services/profile_connection_service.dart` (not a separate invitation service — see code comment reasoning in the audit)
- **People search**: `lib/services/people_search_service.dart`, `lib/models/people_search_result.dart`, `lib/providers/people_search_provider.dart` — cross-checked and verified against `docs/PEOPLE_SEARCH_PORTAL_COMPARISON.md`
- **Analytics/Communication**: `lib/services/network_analytics_service.dart`, `lib/services/network_communication_service.dart`, `lib/providers/network_analytics_provider.dart`, `lib/providers/network_communication_provider.dart`
- **Public profile**: `lib/screens/profile/public_profile_screen.dart`, `lib/providers/public_profile_provider.dart`

## Payments / Subscriptions / Collaboration

- **Payments**: `lib/services/razorpay_checkout_session.dart`, `lib/services/payment_service.dart`
- **Subscriptions**: `lib/services/subscription_service.dart` (read-only), `lib/providers/subscription_provider.dart`, `lib/screens/subscription/subscription_billing_screen.dart`, `upgrade_screen.dart`
- **Collaboration marketplace**: `lib/models/collaboration.dart`, `lib/services/collaboration_service.dart`, `lib/services/collab_functions_client.dart` — sample/deliverable video uploads go to the private `collab-onetime`/`collab-deliverables` Storage buckets (see `API_CONTRACTS.md`), not the `property-media` bucket used elsewhere
- **Gating UI**: `lib/widgets/premium_launch_bottom_sheet.dart`, `lib/widgets/premium_launch_banner.dart`
- **Placeholder**: `lib/screens/stubs/coming_soon_screen.dart` — used for unimplemented write actions (e.g. "Cancel Subscription")
- **Gating flag**: `lib/config/launch_features.dart` (`FEATURE_SUBSCRIPTIONS`, `FEATURE_PAID_COLLABORATIONS`)

## Voice AI Agent

- **Root**: `lib/voice_agent/` — `config/ai_config.dart`, `models/`, `prompt/system_prompt.dart`, `providers/voice_agent_provider.dart`, `rag/route_index.dart`, `services/{openai_proxy,speech_service,voice_agent_service,conversation_manager,conversation_history_service,intent_stash}.dart`, `tools/{registry,navigation_tool,search_tools,property_tools,profile_tools,favorites_tool,utility_tools,permissions}.dart`, `widgets/{floating_ai_orb,voice_agent_panel,conversation_history,voice_waveform}.dart` (file count deliberately omitted — it drifts with every change and has no architectural value; the directory/component breakdown above is the durable fact)
- **Registered at**: `lib/main.dart:29-36` (`_registerVoiceAgentTools`)
- **Verified tool count (every `toolRegistry.register(...)` call site)**: **31** registered tool names:

  | File | Register call sites | Tools |
  |---|---|---|
  | `navigation_tool.dart` | 1 | `navigate` |
  | `favorites_tool.dart` | 1 | `show_saved_properties` |
  | `search_tools.dart` | 2 | `search_properties`, `compare_properties` |
  | `property_tools.dart` | 8 | `create_listing`, `update_listing`, `delete_listing`, `publish_listing`, `save_draft`, `my_properties_summary`, `schedule_visit`, `add_images` |
  | `profile_tools.dart` | 12 | `view_my_profile`, `update_profile`, `open_my_dashboard`, `open_manage_dashboard`, `show_notifications`, `show_my_network`, `open_chat`, `my_visit_bookings`, `post_content`, `delete_account`, `open_dashboard_action`, `logout` |
  | `utility_tools.dart` | 1 call site, loops over 7 names | `confirm`, `unknown`, `ask_platform`, `auth_required`, `suggest_signup`, `ask_about_platform`, `ask_property_info` — sentinel/no-op tools; `VoiceAgentProvider`'s own state machine handles these, `.execute()` is never called on them, registration only exists so `toolRegistry.has(name)` returns true |

  24 real action/navigation tools + 7 sentinel/state-machine utility tools = 31 total.
- **Gating (added 2026-09-30)**: the whole feature is behind `LaunchFeatures.voiceAssistant` (`FEATURE_VOICE_ASSISTANT`) — `if (LaunchFeatures.voiceAssistant) _registerVoiceAgentTools();` and the `VoiceAgentProvider` `ChangeNotifierProxyProvider` registration are both conditional in `lib/main.dart`, and `FloatingAiOrb` in `lib/app.dart`'s builder is wrapped the same way. `auth_screen.dart`'s "Need help?" footer is also conditional on this flag. Disabled in `config/features/play_release.json`, enabled in `full_development.json` — see `DECISIONS.md`.
- **Governing docs**: `VOICE_ASSISTANT_ANALYSIS.md` (website-only analysis, not this app), `VOICE_ASSISTANT_IMPLEMENTATION_PLAN.md` (stale — see `KNOWN_ISSUES.md`)
- **Tests**: `test/floating_ai_orb_test.dart` — no dedicated test file for `VoiceAgentProvider` itself

## Notifications

- **Service**: `lib/services/notification_service.dart` — never sends client-side push; realtime-only receipt of DB-trigger-created rows
- **Provider**: `lib/providers/notification_provider.dart`
- **Routing**: `lib/core/navigation/notification_route_resolver.dart`
- **Tests**: `test/notification_centre_test.dart`, `test/notification_collab_filter_test.dart`

## Dashboards / Analytics

- **Screens**: `lib/screens/dashboard/` — `builder_dashboard_screen.dart` + widgets, broker/influencer/individual equivalents (per `manage_dashboard_dispatcher.dart` role table)
- **Services**: `lib/services/dashboard_analytics_service.dart`, `lib/services/unified_leads_service.dart`, `lib/services/broker_sections_service.dart`, `lib/services/builder_sections_service.dart`
- **Tests**: `test/dashboard_*_test.dart`, `test/broker_sections_test.dart`, `test/builder_sections_test.dart`, `test/builder_dashboard_b3_test.dart`, `test/builder_inventory_summary_test.dart`, `test/my_listings_status_test.dart`

## Profile

- **Model**: `lib/models/user_profile.dart` (implied — see `test/user_profile_model_test.dart`)
- **Services**: `lib/services/profile_service.dart`, `lib/services/profile_write_service.dart` (deliberately excludes DB-trigger-guarded columns), `lib/services/profile_media_service.dart`, `lib/services/profile_view_service.dart`
- **Screens**: `lib/screens/profile/` — includes `actions/logout_dialog.dart`, `actions/settings_sheet.dart`

## Article / Content Editor

- **Service**: `lib/services/article_service.dart`, `lib/services/article_media_service.dart`
- **Provider**: `lib/providers/article_editor_provider.dart` (admin-detection uses `user_type`, not `user_role` — see `KNOWN_ISSUES.md` inconsistency)
- **Write path changed 2026-09-30**: `ArticleService.create`/`.update` no longer write `cms_posts` directly — both now call the `cms-posts-save` Edge Function (see `API_CONTRACTS.md`), which derives author identity and the admin/publish decision server-side from the caller's own session, and demotes a non-admin's edit of an already-approved article back to `approval_status = 'pending'` in the same atomic write. This removed the client-side `ArticleModel.isEditable` / `ArticleEditorProvider.isLocked`/`ArticleLockReason` gate — an author can now reopen and edit an approved article (it goes back to pending), rather than the editor refusing to save at all. See `DECISIONS.md`.
- **Tests**: `article_content_converter_test.dart`, `article_editor_autosave_test.dart`, `article_editor_image_upload_test.dart`, `article_html_test.dart`, `article_media_service_test.dart` — see `TEST_MAP.md` (previously missing its own section there).

## Edit-Approval Resubmission (cross-cutting, added 2026-09-29)

`lib/services/resubmit_for_approval.dart` is a small shared helper (`resubmitForApproval(client, table:, id:)`) calling a new `resubmit_for_approval` Postgres RPC (SECURITY DEFINER — `approval_status` is a staff-only, trigger-guarded column no plain client UPDATE can touch). A non-admin's edit of already-published content now sends it back to `pending` review, matching the website's behavior; an admin's edit is skipped (publishes straight through). Called before the content write (so the previous-approved snapshot trigger still sees the untouched row) from:
- `lib/services/property_service.dart` (`updateProperty`)
- `lib/services/project_service.dart` (project edits)
- `lib/services/broker_sections_service.dart` (`BrokerProfileService.save`, existing-profile branch only)

Articles use the same end behavior but via a different mechanism — see Article / Content Editor above. The admin check in `resubmit_for_approval.dart` reads `profiles.user_role`, consistent with `property_service.dart`'s own staff-admin check (see `KNOWN_ISSUES.md` KI-6). No dedicated test file exists yet for `resubmit_for_approval.dart` itself — see `TEST_MAP.md` Test Gaps.

## Android / iOS Native Projects

- `android/app/build.gradle.kts`, `android/key.properties` (+ `.example`), `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`
- Full detail in `RELEASE_SAFETY.md`

## Test Infrastructure

- `test/support/` — `fake_auth_service.dart`, `fake_network_communication_service.dart`, `fake_property_inquiry_service.dart`, `fake_visit_booking_service.dart`, `overflow_detector.dart`, `wizard_driver.dart`
- Full map in `TEST_MAP.md`
