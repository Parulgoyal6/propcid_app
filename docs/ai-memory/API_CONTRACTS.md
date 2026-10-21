# API Contracts

Flutter-consumed backend contracts, verified from current code on 2026-09-26. No secret values are recorded anywhere in this file — only variable/key names, table/bucket/function names, and behavior. Mark unknowns explicitly; do not infer backend behavior this repo cannot verify (the actual SQL migrations / Edge Function source are not in this repository).

**Evidence labeling convention used throughout this file**: every server-side behavior claim (RLS policies, Storage SELECT policies, Edge Function side effects, edit windows, resend/rate limits, signed-URL lifetimes, payment validation, automatic server-side state transitions) is **inferred from Flutter-side code comments and response handling, not independently verified against SQL migrations or Edge Function source** (neither is present in this repository). Where a claim is instead something this repo can prove directly — a Dart method exists, a request is shaped a certain way, a client-side check runs — that's a **VERIFIED FROM FLUTTER IMPLEMENTATION** fact. Anything about what the server actually enforces is an **EXPECTED SERVER CONTRACT ACCORDING TO CLIENT COMMENTS/RESPONSES** — plausible and code-comment-sourced, but not independently proven. Treat the latter category as a strong hint for where to look, not a guarantee, before relying on it for anything security- or money-relevant.

## Backend Topology

**Hybrid, Supabase-primary.** Hundreds of direct `supabase_flutter` SDK calls (`.from(`, `.rpc(`, `.storage.`, `.functions.invoke(`) across roughly 90 Flutter source files — a durable order-of-magnitude, not a count to keep exact since it drifts with every feature change. No separate custom EC2 REST API client layer is present in the Flutter code — the Flutter client uses Supabase-compatible SDK/API contracts directly. Infrastructure or reverse proxies that might sit behind the configured Supabase hostname cannot be determined from this repository alone.

**Google Maps/Places are the primary explicit third-party REST API integrations made directly by dedicated Flutter services** (`geocoding_service.dart`, `places_autocomplete_service.dart`, `nearby_places_service.dart`) — this is narrower than saying they're the app's *only* external network traffic. Distinct from that dedicated-service integration pattern, the app also performs other external-network behavior that is not a "backend API integration" in the same sense and is not catalogued exhaustively here:
- **External browser/OAuth navigation** — Google Sign-In, Meta/Facebook OAuth, and any web-based checkout step open outside the app's own API layer.
- **Share URLs** — social share sheets (WhatsApp/Facebook/Twitter/LinkedIn) hand off to the OS share intent, not a direct HTTP call from this app.
- **Externally hosted media/images** — `CachedNetworkImage` and similar widgets fetch whatever URL a Storage row/`PublicMediaUrl.resolve` result points to; this is normal media loading, not a distinct integration.
- **Generic URL/media downloads** — e.g. `social_service.dart:560`'s plain `http.get` to re-download an already-uploaded Storage image for re-encoding.

Razorpay's native checkout SDK runs locally for UI only — order creation/verification are Supabase Edge Functions, not a direct Razorpay REST call from Dart.

## Environment Configuration (names only)

Loaded via `flutter_dotenv` from `.env` at repo root (`lib/main.dart:41`):

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase project base URL. **Ambiguous which value is active** — `.env` has one uncommented value plus commented-out alternates (a `*.supabase.co` host and `apis.propcid.com`). |
| `SUPABASE_ANON_KEY` | Supabase anon/public JWT. A second, commented-out key also exists. |
| `MEDIA_URL` | Optional CDN host that public Storage URLs get rewritten onto. When unset, `PublicMediaUrl.resolve` is a no-op. The active value for any specific release must be verified from that release's own environment/build configuration — this repository's `.env` is a single working-tree snapshot, not a guarantee of what any given release ships with. |
| `GOOGLE_MAPS_API_KEY` | Google Geocoding/Places REST + `google_maps_flutter` map rendering. |
| `RAZORPAY_KEY_ID` | Passed to the native Razorpay checkout sheet only. |
| `RAG_GROUNDING`, `VOICE_AUTONOMOUS`, `VOICE_ALWAYS_CONFIRM` | Voice-agent flags — **currently inert**, not read anywhere in `lib/` (the equivalent Dart config in `lib/voice_agent/config/ai_config.dart` is hardcoded instead, with "Phase 2/3" TODO comments). |
| `VAPID_PUBLIC_KEY` | Web-push VAPID public key. |
| `META_APP_ID` | Public Meta/Facebook OAuth client id. App secret stays server-side. |
| `NEGOTIATION_APP_URL` | Documented as a separate "Negotiation" web app's URL — confirmed dead, zero references in `lib/`. |

**Known discrepancy**: `lib/services/meta_oauth_service.dart` hardcodes the Meta OAuth callback redirect to a literal Supabase project host that matches the *commented-out* `.env` entry, not the currently-active `SUPABASE_URL` value. Unconfirmed whether this is intentional (redirect pinned to one fixed project regardless of app environment) or stale — flag before touching Meta OAuth.

## Auth Header Flow

Three coexisting patterns:
1. **Default** (most services): `Supabase.instance.client.functions.invoke(name, body:)` with no explicit headers — `supabase_flutter` attaches the session bearer token + `apikey` internally.
2. **Hardened path** — `CollabFunctionsClient` (used by `CollaborationService`): requires a live session before any call, sends the access token explicitly as `Authorization: Bearer $token`, and on a 401 refreshes once and retries exactly once.
3. **Manual headers** — `OpenAiProxy` (voice agent): builds `apikey`/`Authorization` headers by hand for raw `http` calls (not `functions.invoke`), falling back to the anon key if there's no session (so anonymous voice-agent use still authenticates as `anon`).

Direct Postgres (`.from(`, `.rpc(`) and Storage calls rely entirely on the ambient `SupabaseClient` session.

## Supabase Auth Flows

| Flow | Mechanism |
|---|---|
| Email/password login | `username-auth` Edge Function resolves email-or-username server-side, returns `access_token`/`refresh_token`; client calls `auth.setSession(...)`. Client never resolves username→email itself (that RPC is revoked from `anon`/`authenticated`). |
| Email signup | `auth.signInWithOtp(email, shouldCreateUser: true, emailRedirectTo: 'com.propcid.app://login-callback')` — a magic link. |
| Phone OTP | `send-otp` Edge Function (MSG91) for send/resend/verify; verify returns `hashed_token` + `verification_type`, then `auth.verifyOTP(type:, tokenHash:)`. Supabase's native phone auth is deliberately not used. |
| Google OAuth | `auth.signInWithOAuth(OAuthProvider.google, redirectTo: 'com.propcid.app://login-callback')`. |
| Password reset | `sendPasswordResetEmail`/`verifyRecoveryToken`/`updatePassword`; reached via `propcid://reset-password` deep link and Supabase's own `AuthChangeEvent.passwordRecovery`. |

## Direct Supabase/DB Usage (tables, non-exhaustive but representative)

`available_locations`, `billing_profiles`, `broker_profiles`, `builder_network_invitations`, `builder_networks`, `builder_projects`, `builder_ratings`, `channel_messages`, `channel_participants`, `channels`, `cms_posts`, `collab_assets`, `collab_invoices`, `collab_payments`, `collaborations`, `conversation_participants`, `conversations`, `followers`, `influencer_video_views`, `influencer_videos`, `message_reactions`, `message_reports`, `messages`, `network_channels`, `network_commissions`, `network_leads`, `network_performance`, `network_referrals`, `notifications`, `post_comments`, `profile_views`, `profiles`, `profiles_public`, `properties`, `properties_commercial`, `properties_land`, `properties_public`, `properties_residential`, `property_contact_details`, `property_inquiries`, `property_visit_bookings`, `saved_projects`, `saved_properties`, `saved_reels`, `social_accounts`, `social_accounts_safe`, `social_ad_campaigns`, `social_ad_leads`, `social_share_logs`, `social_share_preferences`, `social_share_queue`, `subscriptions`, `top_builders_city`, `user_blocks`, `user_likes`, `user_preferences`, `user_ratings`.

Notable: `social_service.dart` deliberately reads `social_accounts_safe` (not the base table) to avoid exposing encrypted OAuth tokens. `people_search_service.dart` deliberately queries base `profiles` (not the `profiles_public` view) because the view omits fields the search card needs.

**`messages.reel_id`** (added 2026-09-29, DM-only): backs the `reel_share` message type shared from the Reels feed into a DM. **Not present on `channel_messages`** — reel sharing is 1:1-only, same restriction as `collab_asset_id`. `MessagingService._dmMessageColumns` includes it, `_messageColumns` (the shared/channel select) deliberately does not; `test/reel_share_dm_test.dart` pins this split via `@visibleForTesting` accessors. A shared `reel_id` resolves against either `influencer_videos` (uploaded reel) or `properties_public` (a listing's own video played as a reel) — see `MessagingService.fetchSharedReels`.

### Known RPC functions

`current_auth_user_is_live`, `track_property_view`, `global_search`, `toggle_reaction`, `edit_message`, `delete_message_for_me`, `delete_message_for_everyone`, `start_conversation`, `hide_conversation`, `record_profile_view`. A further ~15 `.rpc(...)` call sites in `collaboration_service.dart`, `messaging_service.dart`, `influencer_video_service.dart`, `article_service.dart`, `profile_view_service.dart` were located but not all individually re-verified by exact function name — treat as a partial list.

`resubmit_for_approval` (added 2026-09-29) — SECURITY DEFINER RPC, params `p_table` (text table name) + `p_id` (row id). Called by `lib/services/resubmit_for_approval.dart` before a non-admin owner's edit of already-published `properties`/`builder_projects`/broker-profile rows, to demote `approval_status` back to `'pending'` (a plain client UPDATE cannot touch that staff-only, trigger-guarded column). Returns a bool; the caller throws on RPC failure rather than treating a thrown error as "not resubmitted". **Expected server contract per client code comments — not independently verified**: that the RPC checks row ownership itself before demoting. See `DECISIONS.md`.

## Storage Buckets

| Bucket | Access | Used for |
|---|---|---|
| `property-media` | public | Listing photos/videos, profile cover photos, influencer video/thumbnail uploads (shared bucket, different path convention per service) |
| `avatars` | public | Avatar photos + 4 of 6 profile document kinds (RERA/GST/registration-proof/company-logo) |
| `documents` | **private** *(EXPECTED SERVER CONTRACT ACCORDING TO CLIENT USAGE — the client never calls `getPublicUrl()` on this bucket and never resolves a public URL for it; the actual Supabase Storage SELECT policy is not present in this repository and must be checked server-side before changing any access behavior here)* | Aadhaar/PAN verification docs — path stored, never a resolved URL |
| `chat-media` | **private** *(same evidence basis as `documents` above — inferred from client usage, not from reading the actual policy; verify server-side before changing access behavior)* | Chat images + voice notes — read only via `get-chat-media-url` Edge Function's signed URL |
| `media-library` | public | Article featured/inline images |
| `project-media` | public, no per-user path restriction | All 5 builder-project asset types (logo, master layout, images, videos, brochure) |
| `collab-onetime` | **private**, read only via `collab-sample-view` Edge Function (signed URL) | Collaboration-marketplace "sample" video uploads. Path `{authUid}/{uuid4}.mp4` *(VERIFIED FROM FLUTTER IMPLEMENTATION — `lib/services/collaboration_service.dart:635-651`)*. MP4 only, ~9-16s duration (portal tolerance around a 10-15s spec), max 60MB (`maxSampleBytes`) — both enforced client-side before upload *(verified)*; a separate 5-resend cap is mentioned in a client code comment as server-owned *(EXPECTED SERVER CONTRACT ACCORDING TO CLIENT COMMENTS — not duplicated or independently verifiable client-side)*. |
| `collab-deliverables` | **private**, read only via `collab-deliverable-url` Edge Function *(VERIFIED FROM FLUTTER IMPLEMENTATION that the client calls this Edge Function and receives a URL back; the "300s signed URL" lifetime and "flips the collaboration to `completed` server-side" behavior are EXPECTED SERVER CONTRACT ACCORDING TO CLIENT CODE COMMENTS, not independently confirmed)* | Collaboration-marketplace final deliverable video uploads. Same path convention `{authUid}/{uuid4}.mp4`. Owning service: `CollaborationService.uploadDeliverable` (`lib/services/collaboration_service.dart:656-672`). MP4 only, max 300MB (`maxDeliverableBytes`), uploaded original/uncompressed, no duration check — all client-side-verifiable facts. |

Verified directly against `lib/services/collaboration_service.dart` (lines 113-126, 585-672). **Flutter code currently references 8 Supabase Storage bucket names** — this reflects every bucket name found by grepping `lib/` for `.storage.from(` and bucket-name constants, not an exhaustive read of the server-side bucket inventory. A bucket that exists server-side but is referenced only from SQL/Edge Function code (not present in this repo) would not be visible here, so 8 is a lower bound on the client's usage, not proof of the complete bucket list.

**Format/size allow-lists for the four public buckets — verified 2026-09-26** directly against the backend's own migrations (`propcid-main/database/migrations/20260522105737_fix_audit_issues.sql` for `file_size_limit`, `20270420000100_restrict_public_bucket_mime_types.sql` for `allowed_mime_types`), not inferred from client behavior. Supabase Storage enforces `allowed_mime_types` as a real allow-list against the upload's declared `Content-Type` header — a file whose bytes are fine but whose header names something outside this list is rejected, independent of the actual byte content:

| Bucket | `allowed_mime_types` | `file_size_limit` |
|---|---|---:|
| `property-media` | `image/jpeg`, `image/png`, `image/webp`, `video/mp4`, `video/mpeg` | 50 MB |
| `project-media` | `image/jpeg`, `image/png`, `image/webp`, `image/avif`, `image/gif`, `application/pdf`, `video/mp4` | 50 MB |
| `avatars` | `image/jpeg`, `image/png`, `image/webp`, `image/avif`, `application/pdf` | 5 MB |
| `media-library` | `image/jpeg`, `image/png`, `image/webp`, `video/mp4` | 50 MB |

Notably, neither `property-media` nor `project-media` accepts `video/quicktime` (`.mov`) — property/project videos upload uncompressed (see below), so a `.mov` clip (the common default on iPhone Camera Roll) fails at Storage unless the client rejects it first. `lib/services/property_service.dart`, `project_media_service.dart` and `influencer_media_service.dart` now validate against this table before calling `uploadBinary` (2026-09-26 fix — see `CHANGELOG.md`); `profile_media_service.dart` and `article_media_service.dart` needed no change, since every image path they expose already forces JPEG/PNG output through `image_picker`'s resize parameters regardless of source format (verified against `image_picker_ios`/`image_picker_android`'s own re-encoding logic — HEIC/WebP/AVIF sources are never passed through untouched when `maxWidth`/`maxHeight`/`imageQuality` are supplied, which every picker call site in this app does).

Public-URL resolution: `lib/core/utils/public_media_url.dart` (`PublicMediaUrl.resolve`) rewrites `.../storage/v1/object/public/<bucket>/<path>` onto `MEDIA_URL` if set; no-op otherwise; throws `StateError` if `MEDIA_URL` is set but unusable (fails loud, never returns a broken URL). Never applied to private/signed-URL paths.

Upload mechanism: 100% direct client SDK — `storage.from(bucket).uploadBinary(...)` + `getPublicUrl()` (public) or bare path storage (private). No presigned-URL round trip anywhere. No `flutter_image_compress` dependency — all "compression" is `image_picker`'s own `maxWidth/maxHeight/imageQuality` at pick time, with different ceilings per feature. `video_compress` (720p) is used only for influencer videos; property/project videos upload uncompressed.

## Edge Functions (Supabase, invoked via `functions.invoke` or manual HTTP)

| Function | Purpose |
|---|---|
| `send-otp` | Phone OTP (MSG91) send/resend/verify |
| `username-auth` | Email/username+password sign-in |
| `delete-account-request`, `export-user-data` | Account deletion / data export |
| `meta-oauth-exchange`, `meta-select-page`, `meta-disconnect` | Meta/Facebook connection lifecycle |
| `meta-followers-sync`, `meta-list-ad-accounts`, `meta-select-ad-account`, `meta-campaign-create`, `meta-campaign-sync`, `meta-targeting-search`, `meta-leads-sync` | Social/ads management |
| `moderate-media`, `moderate-comment` | Chat media/text moderation before send |
| `get-chat-media-url` | Signed URL for a private chat-media object |
| `property-comments` | Action-based (`{action: 'delete', commentId}` confirmed from `CommentService.deleteComment`, added 2026-09-29); also referenced in code comments as the server-side enforcement point for comment-creation validation the portal shares. Re-checks ownership server-side for delete — a non-owner gets a 403 surfaced as the server's own message, not a generic one. Not previously listed in this table despite existing call sites — a pre-existing documentation gap, not a new function as of this audit. |
| `cms-posts-save` | Article create/update (added 2026-09-30, replacing a direct `cms_posts` insert/update). Body: `{id, finalize, contentType: 'article', title, brief, contentHtml, category, tags, featuredImageUrl, readTime, seoTitle, seoDescription, slug}`. **Verified from Flutter implementation**: the client no longer sends author identity, `user_type`, or an admin flag — those are dropped from the request body entirely. **Expected server contract per client code comments — not independently verified**: the function derives author identity and the admin/publish decision from the caller's own session/profile row, and — for a non-admin's `finalize: true` save of an already-approved article — demotes `approval_status` back to `'pending'` in the same atomic write; `finalize: false` (autosave) never touches moderation state. See `DECISIONS.md` and `MODULE_MAP.md` → Article / Content Editor. |
| `invite-team-member`, `accept-team-invite` | Builder team invitations |
| `influencer-video-save` | Persist an influencer video post-upload |
| `influencer-audience-insights` | Cross-content dashboard insights |
| `create-order`, `verify-payment`, `manage-subscription`, `refund-payment`, `download-invoice`, `update-billing-profile` | Razorpay order/subscription lifecycle. **Client never sends a price** *(verified from Flutter implementation)*. That `create-order` resolves the price server-side from `profiles.user_type` is an **EXPECTED SERVER CONTRACT according to client comments**, not a directly verified server implementation — the Edge Function source is absent from this repository. |
| `billing-history` | Billing history list |
| `openai-proxy` (`/chat/completions`, `/audio/speech`, `/audio/transcriptions`) | Voice agent LLM chat, TTS, STT — proxies OpenAI so no API key lives client-side |
| `collab-agreement`, `collab-create-order`, `collab-sample-view`, `collab-deliverable-url`, `collab-dispute`, `download-collab-invoice` | Collaboration marketplace lifecycle |

Not present in this repository: Edge Function source code itself (no `supabase/functions/` directory found) — this app only calls these by URL/name. Server-side behavior (exact validation, rate limits, edit windows) is taken on the Dart client's own code comments, not independently verified against the actual function source or SQL migrations.

## Google Maps/Places REST (external, non-Supabase)

| Endpoint | Purpose |
|---|---|
| `maps.googleapis.com/maps/api/geocode/json` | Reverse-geocode a tapped map point |
| `places.googleapis.com/v1/places:autocomplete`, `.../v1/places/{placeId}` | Location search-as-you-type + place details |
| `places.googleapis.com/v1/places:searchNearby` | Nearby hospitals/schools/malls/airports/metro |

All keyed by `GOOGLE_MAPS_API_KEY`, all fail-soft (return null/empty on error, never throw for missing results).

## Per-Service Contract Summary

| Service | Backend | Key operations | Notable request/response contract |
|---|---|---|---|
| `auth_service.dart` | Supabase Auth + Edge Functions | login, signup, OTP, OAuth, password reset, profile upsert | `username-auth` needs `access_token`+`refresh_token` both present; OTP verify needs `hashed_token`+`verification_type` |
| `property_service.dart` | Supabase DB + Storage + RPC | listing CRUD, edit-bundle fetch, view tracking, search | `track_property_view` RPC params: `property_uuid`, `viewer_user_id`, `viewer_session_id`, `view_duration`, `view_percentage`; `global_search` RPC param `search_term` |
| `messaging_service.dart` | Supabase DB + RPCs + `moderate-comment` | conversation/message CRUD, reactions, reports | `moderate-comment` response: `isAllowed` bool + `reason` string; moderation **fails open** on transport/parse error |
| `chat_media_service.dart` | Storage (`chat-media`) + Edge Functions | upload, moderate, signed URL fetch | `moderate-media` body: `storagePath`, `bucket`, `messageId`, `surface` |
| `payment_service.dart` | Edge Functions (Razorpay server-side) | createOrder, verifyPayment, subscription mgmt | `create-order` response requires non-empty `orderId`+`keyId`; `verify-payment` requires `success == true` |
| `collaboration_service.dart` + `collab_functions_client.dart` | Supabase DB + hardened-auth Edge Functions | state transitions, payment verification, disputes | Every Edge call requires a live session first — client throws before any network call otherwise |
| `people_search_service.dart` | Supabase DB (`profiles`) | text/role search | Deliberate `.not('is_blocked','is',true)` (not `.eq`) to also exclude NULL rows; `filterValue()` quotes PostgREST metacharacters the portal leaves unescaped |
| `voice_agent/services/openai_proxy.dart` | Edge Function `openai-proxy` via raw `http` | chat/TTS/STT | Manually built headers (see Auth Header Flow #3); model name is never specified client-side — chosen entirely server-side |
| `rbac_service.dart` | None | — | Pure client-side logic, **dead code** — see `KNOWN_ISSUES.md`. Not a real backend contract. |
| `profile_media_service.dart` | Storage (`avatars`, `property-media`, `documents`) | avatar/cover/verification-document upload | Bucket ownership declared directly as named constants: `avatarBucket = 'avatars'` (line 97), `coverBucket = 'property-media'` (line 104, deliberately not `avatars`, matching the portal's `BackgroundUploadModal.tsx`), `verificationDocumentBucket = 'documents'` (line 111). **The Flutter client treats `documents` as private and never resolves it through a public URL** *(verified from Flutter implementation)*. The actual Supabase Storage read policy is not present in this repository and must be verified server-side — do not treat "private" here as an independently confirmed server-side fact. |

## Unknowns / Unverifiable From This Repository

- Exact server-side validation rules, rate limits, and the documented "15-minute edit window" for messages — taken from Dart-side comments only, not the actual SQL/Edge Function source.
- Whether `FEATURE_SUBSCRIPTIONS`/`FEATURE_PAID_COLLABORATIONS`/`FEATURE_META_PUBLISHING` are ever set differently by a CI/CD pipeline beyond the two committed JSON files (no `.github/workflows` was found/inspected).
