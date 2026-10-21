# High-Risk Areas

Areas of the app where a change has outsized blast radius, based on a read-only audit (2026-09-26). Each entry explains *why* it's risky, not just that it is — use this to decide how much investigation a change needs before touching it, per `.claude/CLAUDE.md`'s "Before Any Change" checklist (not the root `claude.md`, which is a separate, narrow, historical listing-migration doc — see `KNOWN_ISSUES.md` for how it's stale).

## Authentication / Session (`AuthProvider`, `AuthService`, `AuthResolver`)

**Files**: `lib/providers/auth_provider.dart`, `lib/services/auth_service.dart`, `lib/services/auth_resolver.dart`

**Why risky**: `AuthProvider` is the single owner of post-auth navigation for the entire app — every screen's reachability ultimately depends on `AuthResolver.classify` returning the right `AuthDestination`. The code contains extensive, deliberate race-condition handling (generation counters, coalesced same-user re-fires, `isCurrentUserLive` liveness checks) that fixed real production bugs (a documented "Home, then back to Sign In" bug class from having two independent navigation deciders). Naive changes here easily reintroduce that class of bug.

**Depends on it**: every authenticated screen in the app; the voice agent's `logout`/`delete_account` tools route through `AuthProvider.logout()`; `PendingInvitationGate` and `InviteDeepLinkHandler` both read `AuthProvider` state.

**Before changing**: read the doc comments at `auth_provider.dart:129-146` (navigation-ownership rationale) and `:509-645` (profile resolution + staleness guards) in full. Check `test/providers/auth_navigation_test.dart`, `test/services/auth_resolver_test.dart`, `test/providers/auth_provider_test.dart`.

## Role / RBAC Logic

**Files**: `lib/services/auth_resolver.dart` (live), vs. the orphaned `lib/services/rbac_service.dart`, `lib/widgets/role_guard.dart`, `lib/services/profile_completion_coordinator.dart` (dead)

**Why risky**: two role vocabularies coexist in the schema/codebase — `profiles.user_type` (live, drives all real gating) and `profiles.user_role` (mostly dead `buyer`/`seller`, but also holds `admin`/`super_admin` for staff, checked inconsistently by different features — see `KNOWN_ISSUES.md`). It is easy to write new role-gating code against the wrong column or against the dead `RBACService` API, producing code that looks correct but never actually gates anything live.

**Depends on it**: `PostPropertyRouteGate`, `AddProjectRouteGate`, `InfluencerVideoRouteGate`, `ManageDashboardDispatcher`, voice-agent `permissions.dart` (`canCreate`), article-publish gating, social-campaign-kind gating.

**Before changing**: confirm which column (`user_type` vs `user_role`) the specific feature actually reads by grepping the live call sites in `MODULE_MAP.md`'s Authentication section — do not assume based on the RBAC guide doc, which describes the dead architecture.

## Backend URLs / API Contracts / Supabase SDK Initialization

**Files**: `.env`, `lib/main.dart:41-46`

**Why risky**: `SUPABASE_URL`/`SUPABASE_ANON_KEY` are force-unwrapped at startup with no fallback — a bad value crashes the app before any UI renders. Multiple candidate URL/key pairs exist in `.env` (some commented out), so which backend the app actually talks to is not obvious from a quick read. A hardcoded Meta OAuth redirect elsewhere in the code references a *different* project ref than the currently-active URL — changing `.env` without checking that reference could silently break Meta OAuth.

**Depends on it**: literally every Supabase-backed feature in the app.

**Before changing**: never invent or alter env var names/contracts without corroborating against actual Edge Function/DB behavior (not verifiable from this repo alone) — see `.claude/CLAUDE.md`'s "never silently change an API/backend/database contract" rule.

## Client-Side Secrets / `.env` Bundling

**Files**: `.env` (repo root, declared as a Flutter asset in `pubspec.yaml:137`), any `--dart-define`/`--dart-define-from-file` value, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, any Dart source.

**Why risky**: `.env` is bundled *inside the shipped app* as an asset. Any value placed there — or in source code, a native manifest/plist, or a compile-time `--dart-define` — must be treated as **recoverable by an end user** (the app package can be unpacked/decompiled). This is not a theoretical risk: `android/app/src/main/AndroidManifest.xml` already has a plaintext Google Maps API key committed to it (see `RELEASE_SAFETY.md`).

**The rule**: never place a true server secret in anything the Flutter client ships. This includes, at minimum:
- Supabase **service-role** keys (the anon key is fine client-side by design — it's meant to be public and rely on RLS)
- OpenAI (or any LLM provider) API secrets — this app already avoids this correctly by proxying through a Supabase Edge Function (`openai-proxy`) rather than holding a model-provider key client-side
- Razorpay **secret** key (only `RAZORPAY_KEY_ID`, the publishable id, belongs client-side — verified as the only Razorpay env var in `.env`)
- Meta/Facebook **app secret** (only `META_APP_ID`, the public client id, belongs client-side)
- Database passwords, private signing/server tokens, or any credential meant to authenticate as a privileged/service identity

**For values that are legitimately client-visible** (Supabase anon key, `GOOGLE_MAPS_API_KEY`, `RAZORPAY_KEY_ID`, `META_APP_ID`, `VAPID_PUBLIC_KEY`): the safety boundary is provider-side restriction, not secrecy — e.g. a Google Maps key must be scoped by package name/SHA-1 fingerprint and API surface in the Google Cloud Console, a Supabase anon key relies entirely on RLS being correct. Document that such restrictions remain required; do not assume documenting "this key is meant to be public" makes an unrestricted key safe.

**Before adding any new env var or `--dart-define`**: ask whether the value would still be safe if every user of the app could read it directly — because they effectively can.

## Media Uploads & Public URL Resolution

**Files**: `lib/core/utils/public_media_url.dart`, `lib/services/{property,profile_media,project_media,chat_media,article_media,influencer_media}_service.dart`

**Why risky**: eight Storage buckets, each with different public/private access patterns and different path conventions, are involved (see `API_CONTRACTS.md` for the full table); according to client-side code comments, several path conventions are intended to satisfy expected RLS policies (e.g. `influencer_media_service.dart` uses a deliberately uid-first path, per its own code comment, to match a policy said to require the first path segment to equal `auth.uid()`). The actual policies must be verified server-side before changing those paths. `PublicMediaUrl.resolve` is the single shared resolver for public Supabase Storage URLs, used by every one of the app's public-media upload flows (property, profile, project, article, influencer) — a bug there breaks image/video display app-wide. Private buckets (`documents`, `chat-media`, `collab-onetime`, `collab-deliverables`) never go through it — they instead preserve a bare storage path and/or rely on a signed-URL Edge Function flow, a structurally different (and not interchangeable) mechanism. The client never calls `getPublicUrl()` on the `chat-media`/`documents` buckets and always resolves reads through their respective signed-URL Edge Functions instead — this is the client-side evidence for treating them as private, not a read of the actual Supabase Storage SELECT policy, which is not present in this repository. **Actual Supabase Storage policies must be checked server-side before changing any access behavior for these buckets.** If a code change accidentally calls `getPublicUrl()` on them, reads will likely fail against the real policy; conversely, a change to add a public-read policy server-side would be a real security regression regardless of what the client currently assumes.

**Depends on it**: every screen that displays an uploaded image/video.

**Before changing**: verify the target bucket's actual public/private status and RLS path convention before changing any upload path string — the per-bucket table in `API_CONTRACTS.md` is the reference.

## Messaging / Realtime

**Files**: `lib/services/messaging_service.dart`, `lib/providers/{messaging_provider,chat_thread_provider}.dart`

**Why risky**: three independent Supabase Realtime subscriptions exist (message-list level, per-thread level, notifications level) with no explicit reconnect/backoff logic — recovery from a missed event relies entirely on the SDK's own socket reconnection plus app-level pull-to-refresh/cursor-based catch-up. The service deliberately does **not** duplicate DB-trigger-owned behaviors (notification creation, `last_message_at` maintenance) — re-adding that logic client-side would create duplicate notifications. Message edit/delete/reactions all funnel through RPCs whose exact server-side rules (e.g. the "15-minute edit window") are not verifiable from this repo.

**Depends on it**: the entire Messages tab, Notification Centre unread badge (shares logic paths), collaboration-marketplace conversations.

**Before changing**: re-read the header comments in `messaging_service.dart` explaining what the DB owns vs. what the client owns before adding any new write path.

## Payments / Subscriptions / Collaboration Marketplace

**Files**: `lib/services/{payment_service,subscription_service,collaboration_service,collab_functions_client,razorpay_checkout_session}.dart`

**Why risky**: this is a **real, live client-side Razorpay integration**, not mock UI. **Verified from Flutter implementation**: the client never sends a price/amount field in any payment request (`payment_service.dart`'s `createOrder`/`previewOrder`). **Expected server contract according to client comments — not independently verified**: that the `create-order` Edge Function resolves pricing server-side from `profiles.user_type`; the Edge Function source is absent from this repository, so this specific server-side behavior is taken on the client code comment's word, not confirmed by reading the actual server implementation. The client-side integration is implemented and wired; **server-side behavior (the Edge Functions that actually create/verify orders and resolve pricing) cannot be independently verified from this repository** — "wired" describes the Flutter side only, not a claim about server-side correctness or production-readiness. It is currently gated OFF (`FEATURE_SUBSCRIPTIONS=false`, `FEATURE_PAID_COLLABORATIONS=false` in the Play release config). A change that inadvertently flips a flag default, or that reintroduces client-side price computation, has real financial/security consequences the moment the flag is turned on — the client-side "never sends a price" behavior is the one half of this contract this repository can actually prove, and it must be preserved regardless of what the server does.

**Note on collaboration route-gating**: unlike subscriptions, the paid-collaboration marketplace has **no dedicated entry in `LaunchFeatures.routeEnabled()`'s route table** (verified in `lib/config/launch_features.dart` — only `_subscriptionRoutes` and `_metaRoutes` sets exist, no `_collabRoutes`). Paid-collaboration gating is instead enforced by scattered call-site checks (`if (!LaunchFeatures.paidCollaborations) ...` in messaging/notification/profile providers and screens), not by a single route choke point. A collaboration-related *screen* reached by an unusual path (not a named route in the blocked set) is not automatically re-checked the way subscription/Meta routes are — see `KNOWN_ISSUES.md` if this becomes a concrete problem.

**Depends on it**: `LaunchFeatures.subscriptions`/`.paidCollaborations` gate ~15+ call sites across messaging, notifications, and dashboard screens.

**Before changing**: never alter the fail-closed default (`defaultValue: false`) in `launch_features.dart` without an explicit, separate instruction — this is a deliberate release-safety design, not an oversight.

## Feature Flags / Release Route Gating

**Files**: `lib/config/launch_features.dart`, `config/features/{play_release,full_development}.json`

**Why risky**: `LaunchFeatures.routeEnabled()` is the single choke point stopping a disabled feature's screen from being reached via deep link, stale saved route, or notification payload — even when every UI entry point is correctly hidden. This covers **subscription routes and Meta/social routes only** (`_subscriptionRoutes`, `_metaRoutes` in `launch_features.dart`) — the paid-collaboration marketplace has no equivalent route set and relies entirely on scattered call-site checks instead (see the Payments/Collaboration section above). If the route gate is bypassed or weakened, gated payment/social screens become reachable in a release build; a weakened *call-site* check would be the equivalent risk for collaboration specifically.

**Fourth flag, `FEATURE_VOICE_ASSISTANT` (added 2026-09-30)**: a third enforcement style, distinct from both of the above — not a named-route set, not scattered call-site checks, but a conditional at the three actual construction points (`_registerVoiceAgentTools()` and the `VoiceAgentProvider` `ChangeNotifierProxyProvider` in `lib/main.dart`, `FloatingAiOrb` in `lib/app.dart`'s builder), plus one screen-level conditional in `auth_screen.dart`. Disabled in `config/features/play_release.json`, matching the other three flags' fail-closed default. Since nothing constructs `VoiceAgentProvider` when disabled, any code that assumes it's always in the widget tree (e.g. via `context.read<VoiceAgentProvider>()` outside a flag check) would throw a `ProviderNotFoundException` — check the flag before adding a new call site that reads this provider.

**Before changing**: any change to `launch_features.dart` should be treated as release-configuration, not ordinary app logic — cross-check against `RELEASE_SAFETY.md`.

## Android/iOS Release Signing & Package Identity

**Files**: `android/app/build.gradle.kts`, `android/key.properties`, `ios/Runner.xcodeproj/project.pbxproj`

**Why risky**: `android/key.properties` is a required, gitignored, machine-local release-signing input — expected to be present only on an authorized release-build machine, not a permanent guarantee of this repository's state. Its presence and completeness must be checked at release time, not assumed from documentation. Android release builds are hard-gated to fail if it's missing/incomplete or the keystore file doesn't exist — this is intentional (prevents an accidental debug-signed release) and must not be "fixed" by relaxing the gate. Separately, the **iOS bundle ID is still the Flutter placeholder** (`com.example.propcidApp`), mismatched from Android's `com.propcid.app` — this is a known, code-comment-acknowledged gap blocking Universal Links, not something to silently "correct" without understanding why it hasn't been fixed yet (may be intentionally deferred to iOS store-listing setup).

**Before changing**: never touch signing config or bundle identifiers without explicit instruction — see `RELEASE_SAFETY.md`.

## Deep Links / Universal Links

**Files**: `lib/core/navigation/invite_deep_link_handler.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Runner.entitlements`

**Why risky**: the team-invite Universal Link (`https://propcid.com/accept-invite*`) is registered in both native manifests but the code's own comments confirm the required `assetlinks.json`/`apple-app-site-association` hosting is not yet fully in place for that domain — so Android will accept the intent filter without granting verified-link status, and iOS's associated-domains entitlement is similarly incomplete pending the bundle-ID fix above. This is a known, partially-implemented feature, not a regression to "fix" casually.

## Shared Models Used Across Multiple Modules

**Files**: `lib/models/chat_message.dart` (backs both DM and channel messages), `lib/models/property_model.dart` (backs all 5 listing categories), `PublicMediaUrl` (shared across 5 upload services)

**Why risky**: a change to any of these ripples across every consumer simultaneously. `PropertyModel` in particular carries category-specific fields (residential/commercial/land) on one shared class — verify all category branches when touching it, not just the one you're working on.

## Property Edit-Hydration Path (Active Uncertainty, Not Yet a Confirmed Fix)

**Files**: `lib/services/property_service.dart` — `fetchForEdit` (contains a still-present, explicitly labeled `[EDIT_TRACE]` temporary debug-print block)

**Why risky**: the code comment states this instrumentation is intentionally still in place pending on-device confirmation that a real bug ("Portal-created listings edit blank in the app") is fully fixed — meaning the underlying fix (metadata merge-on-update) may not be fully verified in production yet, despite being merged. Treat any further edit-hydration work in this area as touching an open question, not settled code. See `KNOWN_ISSUES.md`.
