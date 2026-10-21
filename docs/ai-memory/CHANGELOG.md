# AI-maintained Engineering Changelog

This file is maintained by Claude Code sessions (per `.claude/CLAUDE.md`, the global operating manual — not the root `claude.md`, which is a separate, narrow, historical listing-migration doc) to record meaningful shipped changes going forward. It does not fabricate historical releases — no entries exist before the date this memory system was created, since no verifiable release history could be reconstructed from the repository alone (see `docs/ai-memory/CURRENT_ARCHITECTURE.md` and the git log for what evidence does exist).

## Convention for future entries

- Add a new entry at the top (reverse-chronological) for any meaningful shipped change — not every commit, but anything that changes user-visible behavior, a backend contract, a release-config value, or a documented architectural decision.
- Format:
  ```
  ## YYYY-MM-DD — Short title

  What changed, in plain terms. One or two sentences on why, if not obvious.
  Files: key files touched.
  Related: link to DECISIONS.md / INCIDENTS.md / KNOWN_ISSUES.md entry if applicable.
  ```
- Do not invent past entries. If you're unsure whether something already shipped, check `git log` rather than guessing.
- A meaningful shipped change should also update the relevant other file per `.claude/CLAUDE.md`'s "Keeping Project Memory Current" table (architecture change → `CURRENT_ARCHITECTURE.md`, contract change → `API_CONTRACTS.md`, etc.) — this changelog is a timeline, not a replacement for those.

---

## 2026-10-14 — Google Play flexible in-app update flow added

Android-only. `HomeScreen`'s existing post-frame callback (same place the once-per-session `PremiumLaunchBottomSheet.showOnce` call already lived) now also calls `InAppUpdateService.checkOnce(context)`, fire-and-forget via `unawaited`. The service checks Play for an update via the `in_app_update` package, and if one exists and is FLEXIBLE-eligible, starts the background download; once fully downloaded it shows a small AlertDialog ("Restart now" / "Later"). Every failure mode (no Play Store, `flutter run`, sideloaded APK, no update, user declining/cancelling, a platform error) is swallowed silently — never surfaced to the user, never thrown. Runs at most once per app session via a static gate (`InAppUpdateService._checkedThisSession`), mirroring `LaunchOfferSessionGate`'s pattern. Never the IMMEDIATE (blocking) update variant. Does not touch the existing `PackageInfo`-based About-dialog version display (`workspace_drawer.dart`).

The plugin itself (`UpdateCheckClient`/`PlayInAppUpdateClient` in `update_check_client.dart`) is isolated behind a small interface so `InAppUpdateService`'s branching logic is unit-tested with a fake client — the real plugin is a platform channel to Google Play and can't be exercised in a test environment. Initial design exposed a raw install-status `Stream` from the client to the service; that caused `flutter test`'s FakeAsync harness to hang indefinitely (10-minute timeout) on any test path that touched the stream, even though the service logic itself completed correctly (confirmed via temporary trace prints). Fixed by collapsing "start the download and wait for it to finish" into a single `Future<FlexibleUpdateOutcome>`-returning client method instead, removing the raw stream from the service/test surface entirely — same plain-Future-fake pattern already used elsewhere in this codebase's tests (e.g. `_FakeCommentService` in `post_comments_sheet_test.dart`).

Files: `lib/services/update_check_client.dart` (new), `lib/services/in_app_update_service.dart` (new), `lib/widgets/update_ready_prompt.dart` (new), `lib/screens/home/home_screen.dart`, `pubspec.yaml`/`pubspec.lock` (added `in_app_update: ^5.0.0`), `test/services/in_app_update_service_test.dart` (new, 9 tests).
Related: `KNOWN_ISSUES.md` (new entry for an unrelated pre-existing `workspace_navigation_gates_test.dart` failure found during this change's regression pass). Verified: `flutter analyze` unchanged at 571 issues/0 errors/7 warnings; release AAB built successfully with `config/features/play_release.json`.

## 2026-09-30 — Voice AI Assistant hidden behind a new feature flag

Added a 4th `LaunchFeatures` flag, `FEATURE_VOICE_ASSISTANT` (`bool.fromEnvironment`, default `false`, fail-closed like the other three). Disabled in `config/features/play_release.json`, enabled in `full_development.json`. Unlike the existing three flags, this one is not route-gated or scattered across call sites — it wraps the actual construction points: `_registerVoiceAgentTools()` and the `VoiceAgentProvider` `ChangeNotifierProxyProvider` in `lib/main.dart`, `FloatingAiOrb` in `lib/app.dart`'s builder, and the "Need help?" footer/orb-visibility toggle in `auth_screen.dart`. When disabled, the provider is never constructed and no voice-agent tool is ever registered — not merely hidden. App version bumped `1.0.0+4` → `1.0.0+5` around the same time (app icon also updated to a full adaptive-icon config — see `RELEASE_SAFETY.md`).

Files: `lib/config/launch_features.dart`, `config/features/{play_release,full_development}.json`, `lib/main.dart`, `lib/app.dart`, `lib/screens/auth/auth_screen.dart`.
Related: `DECISIONS.md`, `HIGH_RISK_AREAS.md`, `RELEASE_SAFETY.md`, `CURRENT_ARCHITECTURE.md`, `MODULE_MAP.md` (all updated). `TEST_MAP.md` Test Gaps: the new flag has no test coverage in `launch_features_test.dart` yet.

## 2026-09-30 — Article editing/approval moved server-side; the client-side "can't edit an approved article" lock was removed

`ArticleService.create`/`.update` now call a `cms-posts-save` Edge Function instead of writing `cms_posts` directly. The function derives author identity and the admin/publish decision from the caller's own session, and — for a non-admin's finalize save of an already-approved article — demotes it back to `approval_status = 'pending'` in the same atomic write. This replaces the previous behavior, where the RLS update policy (`approval_status = 'pending'` required) meant an author's edit of an approved article matched zero rows and looked like a successful no-op; the client used to detect this itself (`ArticleModel.isEditable`, `ArticleEditorProvider.isLocked`/`ArticleLockReason`) and simply refuse to save. Both of those are now removed as dead code — authors can reopen and edit an approved article again, and it correctly re-enters review instead of being blocked or silently ignored.

Files: `lib/services/article_service.dart`, `lib/models/article_model.dart`, `lib/providers/article_editor_provider.dart`, `test/article_editor_autosave_test.dart`, `test/article_editor_image_upload_test.dart`.
Related: `DECISIONS.md`, `API_CONTRACTS.md` (new `cms-posts-save` Edge Function entry), `MODULE_MAP.md`.

## 2026-09-30 — Chat: save an image message to the device gallery

Added a "Save image" action to the chat bubble long-press menu for approved image messages (`ChatMediaService.saveImageToGallery`) — downloads the message's existing signed URL and writes it to the device gallery via the `gal` package already used for Digital Visiting Card downloads (no new dependency or permission). Fails fast with a clear message on web, where `gal` has no implementation.

Files: `lib/screens/messaging/widgets/chat_bubble.dart`, `lib/services/chat_media_service.dart`.
Related: `MODULE_MAP.md` (Messaging).

## 2026-09-29 — Editing already-approved properties/projects/broker profiles now resubmits them for review

Added a shared `resubmitForApproval()` helper (`lib/services/resubmit_for_approval.dart`) calling a new `resubmit_for_approval` Postgres RPC. A non-admin owner's edit to an already-published property, builder project, or broker profile now demotes it back to `approval_status = 'pending'` before the content write lands — matching the website's behavior, where previously the edit landed silently with no re-review. Admin editors are skipped and publish straight through. Articles get the same end behavior via a different, newer mechanism (see the 2026-09-30 article entry above).

Files: `lib/services/resubmit_for_approval.dart` (new), `lib/services/property_service.dart`, `lib/services/project_service.dart`, `lib/services/broker_sections_service.dart`.
Related: `DECISIONS.md`, `API_CONTRACTS.md` (new RPC), `MODULE_MAP.md`, `KNOWN_ISSUES.md` KI-6 (the new helper's admin check reads `user_role`, consistent with — not a new instance of — the existing `user_type`/`user_role` inconsistency). `TEST_MAP.md` Test Gaps: no dedicated test file for the new helper yet.

## 2026-09-29 — Post-property submission confirmation no longer assumes a new listing is immediately live

`PropertyService.createProperty` now returns the row's real, server-assigned `approval_status` alongside its id (`PropertyCreationResult`), instead of just the id. Previously, the confirmation screen treated any non-null `propertyId` as "live" and always auto-offered "Publish Everywhere" regardless of moderation state. It now shows "Your listing is live!" only when `approval_status == 'approved'`, otherwise "Listing sent for admin approval" — and never auto-opens the publish-everywhere dialog for a pending listing.

Files: `lib/services/property_service.dart`, `lib/providers/post_property_provider.dart`, `lib/screens/post_property/property_submission_confirmation_screen.dart`, `test/property_submission_confirmation_screen_test.dart` (new).
Related: `TEST_MAP.md`.

## 2026-09-29 — Reel sharing in DM chat

Added a DM-only `reel_id` column/message type so a Reels-feed item can be shared into a direct chat and render as a rich preview card, mirroring the existing property-share pattern. `MessagingService.fetchSharedReels` batch-resolves ids against either `influencer_videos` (uploaded reels) or `properties_public` (a listing's own video played as a reel). Deliberately DM-only, same restriction as the existing `collab_asset_id` column — never selected for channel messages.

Files: `lib/models/shared_reel_preview.dart` (new), `lib/services/messaging_service.dart`, `lib/providers/chat_thread_provider.dart`, `lib/screens/messaging/widgets/{chat_bubble,reel_share_preview_card}.dart`, `test/reel_share_dm_test.dart` (new, 526 lines).
Related: `API_CONTRACTS.md`, `MODULE_MAP.md`.

## 2026-09-26 — Listing wizard: commercial Covered Parking and Others/PG Carpet Area were never hydrated on edit; commercial lease-only fields leaked into rent

Three related field-mapping bugs in the T0–T11 category-parity work, all metadata-key mismatches between what the portal reads/writes and what the app's edit-hydration read: (1) Commercial "Covered Parking" lives in `metadata.coveredParking`, which the app never read on edit-load, so a portal-filled value showed blank; now read and always written back (even blank, so clearing replaces a stale value). (2) An Others/PG listing has no subtype-table `carpet_area_sqft` column, so the portal keeps Carpet Area in `metadata.carpetArea`; the app only read the subtype column, so that field showed blank for those two categories (Residential/Commercial still read their own subtype column, unaffected). (3) Commercial Lease Terms (lease duration, rent escalation %, CAM charges, fit-out period) were gated on "commercial + (rent or lease)"; they apply to a commercial **lease** only per the portal, so they were wrongly visible/required for commercial rent too — narrowed to lease-only.

Also removed three obsolete backup `.zip` files that had accumulated under `lib/` (`lib/main.zip`, `lib/core/theme.zip`, `lib/core/theme/app_theme.zip`) — not build inputs, no import ever referenced them.

Files: `lib/providers/post_property_provider.dart`, `lib/screens/post_property/listing_validation_rules.dart`, `lib/services/property_service.dart`, `test/listing_validation_rules_t2_test.dart`.
Related: `CURRENT_ARCHITECTURE.md` (zip note), `KNOWN_ISSUES.md` KI-19 (a different, larger root `.zip` was later committed and then uncommitted-deleted on 2026-09-30 — a separate recurrence, not resolved by this cleanup).

## 2026-09-26 — Fix: public media upload format/size rejections; listing-video reel Like/Save state

Two independent fixes, same day.

**1. Media uploads rejected by the destination Storage bucket.** Verified the real, backend-enforced `allowed_mime_types`/`file_size_limit` for `property-media`, `project-media`, `avatars` and `media-library` directly against the backend's own migrations (now recorded in `API_CONTRACTS.md`). Found and fixed three gaps, all in video paths (no image path needed a change — every image picker call site already forces JPEG/PNG output via `image_picker`'s resize parameters, verified against the plugin's own iOS/Android source):

- `InfluencerMediaService.uploadVideo` always named/labeled the uploaded file from the *original* picked file, even when `video_compress` (which always outputs an MP4 container) had produced genuinely different MP4 bytes from a `.mov` selection — so a successfully-compressed `.mov` still uploaded as `video/quicktime`, which `property-media`'s allow-list rejects despite the bytes being fine. Fixed via a new `resolveUploadFileName`/`isAcceptedVideoFileName` pair: the upload name now follows what was actually compressed to, and a fallback-to-original file in an unsupported format is rejected before the network call instead of failing at Storage.
- `PropertyService._uploadMedia` had no format or size check at all. Property/land videos upload uncompressed, so a `.mov` clip reached Storage unconverted and was rejected there. Added `isAcceptedPropertyMediaMimeType` + a 50 MB pre-upload check (the picker UI already enforces a stricter 10 MB cap, but the service itself had none).
- `ProjectMediaService.uploadVideo` had the identical `.mov` gap (also uncompressed, also no format check) — fixed the same way.

`ProfileMediaService`/`ArticleMediaService` were investigated and needed no change — confirmed safe rather than assumed.

**2. Listing-video reel Like/Save state disagreed between the player, property screens and My Activity.** A listing-video reel's `id` is the same as its underlying property's `id`, and its like/save is recorded via `PropertyProvider` (`user_likes.property_id`/`saved_properties`), never via `ReelsProvider`'s own `_likedIds`/`_savedIds` (`user_likes.reel_id`/`saved_reels`). Two bugs followed:

- `ReelsProvider.getLikedReels`/`getSavedReels` (backing My Activity's "Reels" filter) checked only the provider's own id sets — a liked/saved listing-video reel could never appear there, no matter how many times it was liked via the player. Fixed with optional `likedPropertyIds`/`shortlistedPropertyIds` parameters (default empty, so any other caller keeps today's behavior) that decide a property-video reel's state; every influencer reel is unchanged. The pure branch logic is now `ReelsProvider.selectByLikedState`/`selectBySavedState`.
- The displayed like count (`reels_screen.dart` and `reel_action_row.dart`) computed `reel.likes + (liked ? 1 : 0)` for a listing-video reel — `reel.likes` is `properties.likes`, already the true current total, so this double-counted a property the viewer had already liked before the reel loaded. Fixed by dropping the adjustment for the property-video branch only; the influencer branch's `ReelsProvider.likeCount` (same "+1" shape) is deliberately unchanged per this fix's own scope.
- `my_activity_section.dart` also needed `excludePropertyVideoListings`: once a liked/saved listing-video property is correctly shown under the Reels filter, it must not also count under the Properties filter, or the same item appears twice and the header total (`Liked (N)`/`Saved (N)`) inflates. `PropertyProvider.getLikedProperties()`/`getShortlistedProperties()` themselves are untouched — `shortlist_screen.dart` also depends on their current, unfiltered output, so the exclusion is applied only at this one call site.

Verified: `flutter analyze` clean on every changed file (only pre-existing, unrelated info-lints). New tests: `influencer_media_service_test.dart` (9), `property_media_upload_test.dart` (6), `project_media_service_test.dart` (4), `reels_activity_state_test.dart` (9) — all pure-function tests against hand-built fixtures, no live Supabase session needed (neither `PropertyProvider` nor `ReelsProvider` accepts an injected client). Ran the full suite: 1998 passed, 7 failed. All 7 reproduce identically in isolation (verified by re-running each failing file alone) and involve files this fix never touched: `reel_share_link_test.dart` (2, `KNOWN_ISSUES.md` KI-17), `notification_centre_test.dart` (4, KI-18), and `people_search_test.dart`'s pre-existing "See all people" failure (1, already known from an earlier session). Zero failures in any file this fix changed or added.

No backend/database/auth/config change. `shortlist_screen.dart`, sign-in/OAuth, messaging, collaboration, payments and article/profile edit flows were not touched.

Files: `lib/services/{influencer_media,property,project_media}_service.dart`, `lib/providers/{property,reels}_provider.dart`, `lib/screens/reels/reels_screen.dart`, `lib/screens/reels/widgets/reel_action_row.dart`, `lib/screens/profile/widgets/my_activity_section.dart`, plus the four new test files above.
Related: `KNOWN_ISSUES.md` KI-17.

## 2026-09-26 — Fix: Influencer Edit Profile (landmark not saved, dead fields, no custom language)

Four issues investigated end-to-end against `edit_profile_provider.dart`/`edit_profile_screen.dart`, cross-checked against the authoritative backend (`propcid-main/backend/functions/edit-profile-save/index.ts`, `influencer-registration-submit/index.ts`, `_shared/registration.ts`) and the portal (`propcid-main/frontend/src/features/profile/EditProfile.tsx`) as reference:

1. **Landmark not persisting for influencer** — root cause confirmed as a provider bug, not UI/backend/hydration: `EditProfileProvider.buildSocialMediaChanges()`'s `isInfluencer` branch never included a `'landmark'` key (the `isBuilder`/`isBroker` branches both did). The field displayed correctly on load (hydration reads `sm.landmark` unconditionally) and typing into it worked, but the value was simply never included in the save payload, so it silently reverted on reopen. Fixed by adding the missing key. Regression test added (fails without the one-line fix, verified by temporarily reverting it).
2. **Portfolio links / Previous brand collaborations shouldn't appear in Edit Profile** — confirmed via the backend: `influencer-registration-submit` writes `portfolio_links`/`previous_brand_collaborations` once at registration, but `edit-profile-save` never reads or re-writes either key for any role — they are write-once by backend design. The portal's `EditProfile.tsx` never renders them either. The Flutter screen showed both as editable text fields, whose edits would silently no-op on save. Removed both `_Field`s from `_influencerContentSection` (UI only, per the task's explicit scope) — `EditProfileProvider.portfolioLinks`/`.previousCollaborations` controllers, their hydration, and their write into `social_media` are all left exactly as they were, so nothing about the stored data or the provider's public surface changed, and the two existing "round-trip" provider tests still pass unmodified.
3. **DOB validation ("unsafe")** — investigated in full and found already correct: a prior commit (`86d90a5 "Fix DOB"`) already bounds the date picker to `[1940, today-18-years]` and re-validates in `EditProfileProvider.validate()` before save, using the same `.isAfter(now)` trick the backend's `isAdultDob`/`calculateAge` (`_shared/registration.ts`) uses, which rejects a future DOB and an under-18 DOB identically and allows exactly-18-today. Verified (not assumed) with 4 new tests: future date, one-day-short-of-18, exactly-18-today, and influencer role specifically (previously only broker was covered). No code change was needed or made for this issue.
4. **No way to add a custom language** — `_ChipGroup` only ever offered a fixed canonical list plus already-stored legacy values; there was no free-text entry point. Confirmed the backend can safely persist an arbitrary custom value (`languagesKnown` → `dbArray()` → `social_media.languages_known`, a plain unchecked string array, not an enum/FK). `influencer_registration_screen.dart` already has a verified "add custom" pattern (`_addCustomLanguage`); rather than touching that unrelated screen, the same pattern was added as an opt-in `allowCustom`/`customHint` pair on `_ChipGroup` (default `false`, so every other call site — builder/broker languages, areas of expertise, content/promotion types — is unchanged) plus a new `EditProfileProvider.addCustomChip()` (a "toggleChip that only adds, never removes"), enabled only on the influencer Languages known field. A custom value then renders and can be removed via the exact same selected-chip mechanics decision 5.1 already provides for legacy values — no other rendering path was needed.

Verified: `flutter analyze` clean on all changed files (one pre-existing, unrelated info-lint at `edit_profile_provider.dart:545`). `edit_profile_parity_test.dart` (47 tests, 16 new) and `edit_profile_document_upload_test.dart` (13 tests) pass. Ran the wider auth/messaging/collaboration/public-profile/dashboard-role-metrics suites (169 tests) to confirm no regression in protected flows.

Files: `lib/providers/edit_profile_provider.dart`, `lib/screens/profile/edit_profile_screen.dart`, `test/edit_profile_parity_test.dart`.

No backend/database contract change — every write reuses an already-supported `social_media` key; no server-side uncertainty remains for any of the four issues.

## 2026-09-26 — Fix: My Networks' Total Connections/Requests Sent/Requests Received were non-interactive

On Network ▸ My Networks, the three stat tiles (`_NetworkStatsRow` in `my_networks_screen.dart`) were plain `MetricCard`s with no `onTap` — decorative counters, not the portal's tabs. `NetworkMemberships.tsx` renders the same three tiles as a 3-way toggle (`activeTile` state) that switches the list card below between Connections / Sent / Received. In the Flutter port, two of those three lists (Requests Sent, Requests Received) had no rendering path anywhere in the app: `outgoingPeerRequest`/`incomingPeerRequest` rows were already being fetched and classified correctly by `NetworkRelationshipService`/`NetworkRelationship.classify` (verified — the data layer was never the bug) and counted correctly in the tiles, but nothing rendered them as a list, so there was no way to view, cancel, accept or decline a pending peer-connection request from this screen at all (the only reachable path was visiting that specific counterpart's public profile page).

Root cause was UI-only: a missing tap affordance plus two missing list sections — not a provider, service, query or backend-contract problem. `ProfileConnectionService.cancelRequest`/`acceptRequest`/`declineRequest` already existed and already wrote the correct `builder_networks` rows (used elsewhere by the public profile page); they were simply never called from this screen.

Fix: tiles are now tappable (wrapped in a new `_StatTile`, not a change to the shared `MetricCard` widget so its other, purely-decorative call sites are untouched) and switch a new `activeTile` state (`MyNetworksTile.total/sent/received`) that selects which list `MyNetworksBody` renders. Added `NetworkRelationshipsProvider.sentRequests`/`.receivedRequests` getters and `.cancelSentRequest()`/`.acceptReceivedRequest()`/`.declineReceivedRequest()` methods (mirroring the existing `.leaveNetwork()` busy-guard pattern with a separate `actingId`/`actionError`, since a leave and a request-response can never target the same row), each a thin wrapper calling the pre-existing `ProfileConnectionService` methods keyed by `viewerId`/`counterpartUserId`. `_RelationshipRow` gained optional Cancel/Accept/Decline actions and a status-appropriate date label ("Sent"/"Received" instead of "Connected" for a still-pending row); the existing owned/joined/peer "Total Connections" view and its Leave-network flow are unchanged.

No backend/database contract change: every write reuses an already-implemented, already-RLS-covered `ProfileConnectionService` method.

Verified: `flutter analyze` clean; all 23 pre-existing `network_relationship_test.dart` tests still pass unmodified; added 6 new provider-level tests (getters, cancel/accept/decline success and failure paths, concurrent-action guard) and a new `test/my_networks_screen_test.dart` (5 widget tests) covering tile-tap switching, count-vs-list-length parity, and the Cancel/Accept/Decline callbacks — 34 tests total, all passing. Ran the wider network/invitations/messaging/profile/auth/people-search suites (300+ tests) to confirm no regression in protected flows; one unrelated, pre-existing failure in `people_search_test.dart` ("See all people" — an off-screen-hit-test flake) reproduces identically in isolation on an unmodified checkout of that file and is untouched by this change.

Files: `lib/providers/network_relationships_provider.dart`, `lib/screens/network/my_networks_screen.dart`, `test/network_relationship_test.dart`, `test/my_networks_screen_test.dart` (new).

## 2026-09-26 — Fix: article editor center/right alignment lost on save/reopen

Center and right text alignment applied via the Article Content editor's toolbar (`article_editor_screen.dart`) worked live in-session but silently disappeared after saving and reopening the article. Root cause: `articleDocumentToHtml` (`lib/core/utils/article_content_converter.dart`) called `QuillDeltaToHtmlConverter` with default options, which emit alignment as a CSS class (`class="ql-align-center"`); the HTML→Delta parser used on reopen (`articleHtmlToDocument`) only recognizes inline `style="text-align:…"`, so the class was silently dropped, and the paragraph reverted to left/default alignment. Fixed by passing `ConverterOptions(converterOptions: OpConverterOptions(inlineStylesFlag: true))`, so alignment is now written as inline `text-align` and round-trips correctly.

Left alignment was unaffected (it's Quill's un-attributed default, so it was never encoded as a class in the first place).

Added a regression test (`test/article_content_converter_test.dart`) that saves and reopens center/right-aligned content and asserts the alignment survives. Existing article-editor/converter tests (49 total across `article_content_converter_test.dart`, `article_editor_autosave_test.dart`, `article_editor_image_upload_test.dart`, `article_html_test.dart`, `article_media_service_test.dart`) still pass; `flutter analyze` is clean on the changed files.

Files: `lib/core/utils/article_content_converter.dart`, `test/article_content_converter_test.dart`.
Related: `KNOWN_ISSUES.md` KI-16 (articles saved before this fix still have unrecoverable alignment in their stored HTML — this fix does not retroactively repair old rows).

## 2026-09-26 — Project memory system initialized

Established `docs/ai-memory/` (`CURRENT_ARCHITECTURE.md`, `MODULE_MAP.md`, `API_CONTRACTS.md`, `HIGH_RISK_AREAS.md`, `TEST_MAP.md`, `KNOWN_ISSUES.md`, `INCIDENTS.md`, `DECISIONS.md`, `CHANGELOG.md`, `RELEASE_SAFETY.md`) via a read-only, 10-domain audit of the current repository state. No application code was modified. The pre-existing root `claude.md` (a narrow listing-migration directive doc) was left untouched, per its own preservation rule.

Files: `docs/ai-memory/*` (new).
