# Decisions

Verified architectural/engineering decisions, compiled from in-code doc comments during a read-only repository audit (2026-09-26). Every entry cites the code comment or test that evidences it. Where a decision's *why* could not be established from available evidence, it is marked "Rationale not currently verifiable" rather than invented.

---

## Decision — AuthProvider is the sole owner of post-auth navigation

Status: Active, load-bearing

### Context
An earlier architecture apparently had two independent places deciding where to navigate a user after auth events, producing a documented "Home, then back to Sign In" bug class (e.g. after a Google OAuth callback).

### Decision
`AuthProvider` (constructed before `runApp`) is the single source of truth for post-auth navigation. `AuthResolver.classify` is a pure function of the fetched `profiles` row only — it never reads `SharedPreferences` or any other side-channel — specifically so no second decision path can disagree with it.

### Reason
Explicit doc comments at `lib/providers/auth_provider.dart:129-146` and `lib/services/auth_resolver.dart:57-61` describe this as a deliberate fix for the two-decider bug class.

### Files affected
`lib/providers/auth_provider.dart`, `lib/services/auth_resolver.dart`, `lib/screens/splash/splash_screen.dart`.

### Do not change without checking
Any change that lets a screen navigate based on auth state independently of `AuthProvider` risks reintroducing the original bug class.

### Evidence
`auth_provider.dart:129-146, 509-645`; `auth_resolver.dart:57-86`; `test/providers/auth_navigation_test.dart`.

---

## Decision — Phone OTP is routed through a custom MSG91 Edge Function, not Supabase's native phone auth

Status: Active

### Context
Supabase Auth supports phone OTP natively.

### Decision
Phone OTP send/resend/verify goes through a custom `send-otp` Edge Function (MSG91) instead.

### Reason
Explicit code comment at `lib/services/auth_service.dart:216-220` states this is deliberate, not an oversight. The business rationale beyond this being deliberate is not currently verifiable.

### Files affected
`lib/services/auth_service.dart`, `lib/services/edge_functions_service.dart`.

### Do not change without checking
Reverting to Supabase's native phone auth would need to account for whatever originally motivated this choice — rationale beyond "deliberate" not currently verifiable from this repo.

### Evidence
`auth_service.dart:216-220`.

---

## Decision — Username/email login resolution happens server-side, never client-side

Status: Active, security-relevant

### Context
A client-side RPC to resolve username→email for login existed at some point.

### Decision
That RPC is revoked from `anon`/`authenticated` roles; login instead calls a `username-auth` Edge Function that resolves the identifier and returns tokens directly.

### Reason
Code comment at `auth_service.dart:109-115` frames this as intentional hardening.

### Files affected
`lib/services/auth_service.dart`, `lib/services/edge_functions_service.dart`.

### Do not change without checking
Do not reintroduce a client-side username→email resolution RPC without understanding why it was revoked.

### Evidence
`auth_service.dart:109-115, 126-152`.

---

## Decision — Metadata merge-on-update instead of replace (NEW-1 fix)

Status: Active, still carrying a live debug-trace pending on-device confirmation (see `KNOWN_ISSUES.md` KI-4)

### Context
`PropertyService.updateProperty` previously replaced a listing's entire `metadata` JSONB column on every edit, silently destroying keys the Flutter form doesn't collect but the React portal does (or vice versa).

### Decision
`updateProperty` now does `{...existingMetadata, ..._buildMetadata(provider)}` — an additive merge, fetched via `_fetchExistingMetadata` first.

### Reason
`docs/migrationn/final-architecture-review.md`'s "NEW-1" finding, cited by name directly in the code comment.

### Files affected
`lib/services/property_service.dart:618-695, 855`.

### Do not change without checking
Any change to this merge order must account for the documented ordering hazards with `_applyProjectTag` and `_fillTypedEmpties`, which must run after the merge in a specific order (see their own doc comments).

### Evidence
`property_service.dart:618-695, 1393, 1449`; `test/post_property_metadata_roundtrip_test.dart`; `docs/migrationn/final-architecture-review.md`.

---

## Decision — Builder project creation/inventory is deliberately a separate model/service/wizard from the property listing wizard

Status: Active

### Context
Properties and builder projects share some conceptual overlap (both are "things a builder posts") but have different schemas and lifecycles.

### Decision
`ProjectModel`/`ProjectService`/`add_project_provider.dart`/`lib/screens/add_project/*` is a fully separate system from `PropertyModel`/`PropertyService`/`PostPropertyProvider`/`lib/screens/post_property/*`. A legacy narrower `builder_project_model.dart` (10 fields) is deliberately kept alongside the newer 30-column `project_model.dart` because it still backs one existing widget.

### Reason
Doc comment at `lib/models/project_model.dart:4-11` explains the coexistence explicitly ("decision D6" in the underlying planning doc).

### Files affected
`lib/models/project_model.dart`, `lib/models/builder_project_model.dart`, `lib/services/project_service.dart`, `lib/screens/add_project/*`.

### Do not change without checking
Do not consolidate the two project models without confirming every consumer of the legacy one has been migrated first.

### Evidence
`project_model.dart:4-11, 198`; `docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md`.

---

## Decision — All feature gating (subscriptions, paid collaborations, Meta publishing) is compile-time, fail-closed

Status: Active, release-critical

### Context
The app needs to ship some features (payments, collaboration marketplace, Meta social publishing) in a not-yet-launched state without deleting the implementation.

### Decision
Four `bool.fromEnvironment` flags in `lib/config/launch_features.dart` (`FEATURE_SUBSCRIPTIONS`, `FEATURE_PAID_COLLABORATIONS`, `FEATURE_META_PUBLISHING`, and — added 2026-09-30 — `FEATURE_VOICE_ASSISTANT`), each defaulting to `false`. A build that omits `--dart-define-from-file` entirely gets every gated feature hidden, never silently enabled. Two committed JSON files (`config/features/play_release.json` all-false, `config/features/full_development.json` all-true) select the value at build time. Gating is applied **asymmetrically** across all four: `FEATURE_SUBSCRIPTIONS` and `FEATURE_META_PUBLISHING` are enforced at the route level (`LaunchFeatures.routeEnabled`, a single choke point in `onGenerateRoute`, via dedicated `_subscriptionRoutes`/`_metaRoutes` sets) plus scattered call-site checks; `FEATURE_PAID_COLLABORATIONS` has no dedicated route set and is enforced by scattered call-site checks only; `FEATURE_VOICE_ASSISTANT` is neither — it wraps the construction of `VoiceAgentProvider` and the voice-agent tool registry directly in `lib/main.dart`/`lib/app.dart`, so a disabled build never creates them at all, plus one screen-level conditional in `auth_screen.dart`. Never by deleting the underlying screens/providers/services in any case.

### Reason
File header comment at `launch_features.dart:10-23` states the fail-closed design and the "nothing is deleted, only entry points are gated, all reversibly" principle explicitly. `FEATURE_VOICE_ASSISTANT`'s own rationale beyond "hide the voice assistant" (commit message: "hide voice agent") is not currently verifiable from this repository.

### Files affected
`lib/config/launch_features.dart`, `config/features/*.json`, `lib/main.dart`, `lib/app.dart`, `lib/screens/auth/auth_screen.dart`, ~23 call sites across 15 files for the original three flags (see `KNOWN_ISSUES.md`/`API_CONTRACTS.md` for the list).

### Do not change without checking
Never change a flag's `defaultValue` away from `false`, and never delete a gated feature's implementation just because it's currently hidden — see `HIGH_RISK_AREAS.md`.

### Evidence
`launch_features.dart:1-79`; `test/launch_features_test.dart`; `test/route_protection_test.dart`; `test/workspace_navigation_gates_test.dart`.

---

## Decision — Client never supplies payment price; server-side price resolution is the expected contract

Status: Active, security-relevant

### Context
A naive Razorpay integration could let the client specify the amount to charge.

### Decision
**Verified from Flutter implementation**: `payment_service.dart`'s `createOrder`/`previewOrder` never send a price field in the request body. **Expected server contract, per client code comments — not directly verified server implementation**: the `create-order` Edge Function is said to resolve the price server-side from the caller's own `profiles.user_type`; the Edge Function source is absent from this repository, so this specific server-side resolution behavior is taken on the client comment's word, not independently confirmed.

### Reason
Code comment at `payment_service.dart:25-30` states this is deliberate anti-tampering design.

### Files affected
`lib/services/payment_service.dart`.

### Do not change without checking
Never add a client-supplied price/amount field to any payment request, regardless of whether the server-side resolution described above can be independently confirmed — the client-side half of this contract (never sending a price) is verified and must be preserved either way.

### Evidence
`payment_service.dart:25-30, 129-143` (client-side behavior only — no server-side source available to cross-check).

---

## Decision — Chat/channel message editing and deletion go through server-validated RPCs, not direct table writes

Status: Active

### Context
Direct client writes to `messages`/`channel_messages` for edit/delete would need to duplicate server-side validation (e.g. an edit-time-window rule) client-side, risking drift.

### Decision
`editMessage`, `deleteMessageForMe`, `deleteMessageForEveryone`, `toggleReaction` all call dedicated Postgres RPCs (`edit_message`, `delete_message_for_me`, `delete_message_for_everyone`, `toggle_reaction`) rather than raw `.update()`/`.delete()` calls.

### Reason
Inferred from the consistent RPC-only pattern in `messaging_service.dart:1003-1107`; the exact server-side rules (e.g. the "15-minute edit window") are taken on the Dart code's own comments, not independently verified against SQL (not in this repo).

### Files affected
`lib/services/messaging_service.dart`.

### Do not change without checking
Do not replace an RPC call with a direct table write for these operations — the server-side validation would be lost.

### Evidence
`messaging_service.dart:1003-1107`; `lib/models/chat_message.dart:53-54`.

---

## Decision — Collaboration-type chat messages bypass the normal message action sheet entirely

Status: Active, described as a deliberate safety rule

### Context
Collaboration-marketplace system messages (payment, agreement, deliverable, etc.) carry business-critical state.

### Decision
Six collaboration message types render through a dedicated `CollabMessageBubble` widget and never through `ChatBubble`'s long-press action sheet — so edit/forward/delete-for-everyone/react can never reach them.

### Reason
Code comment at `chat_thread_screen.dart:1059-1062` labels this "Phase 1 safety rule" explicitly.

### Files affected
`lib/screens/messaging/widgets/collab_message_bubbles.dart`, `lib/screens/messaging/chat_thread_screen.dart:1063-1079`, `lib/models/chat_message.dart:133-139`.

### Do not change without checking
Do not wire collaboration message types into the generic action sheet without understanding why they were deliberately excluded.

### Evidence
`chat_thread_screen.dart:1059-1079`; `test/collaboration_marketplace_test.dart`.

---

## Decision — Voice agent tools never write property/listing DB rows directly for creation; they reuse the manual wizard

Status: Active

### Context
An earlier version of the `create_listing` voice tool apparently wrote directly to the `properties` table and always threw due to wrong column names.

### Decision
`create_listing` instead stashes a slot-filled draft into `IntentStash` and navigates to `/post-property`, reusing the exact same wizard/provider/service path a manual user would use. (`update_listing`/`delete_listing`/`publish_listing`/`save_draft` do write directly, but only to pre-existing rows the user already owns, via fuzzy title lookup scoped to `user_id`.)

### Reason
Code comment in `lib/voice_agent/tools/property_tools.dart` (around the `create_listing` tool definition) states this explicitly as the reason for reuse over direct writes.

### Files affected
`lib/voice_agent/tools/property_tools.dart`.

### Do not change without checking
Do not reintroduce a direct-write path for voice-driven listing *creation* without re-verifying the full column contract `PropertyService.createProperty` already encodes.

### Evidence
`lib/voice_agent/tools/property_tools.dart:22-105`.

---

## Decision — Editing already-published content resubmits it for approval instead of silently keeping it live

Status: Active, added 2026-09-29/2026-09-30

### Context
`approval_status` is a staff-only, trigger-guarded column (`trg_guard_staff_cols`) that a plain client UPDATE cannot write. Before this change, an owner's edit to an already-approved property/project/broker-profile/article simply never touched moderation state — the edit landed silently on a still-"approved"/live row with no re-review, unlike the website.

### Decision
A non-admin owner's edit to already-published content now demotes it back to `approval_status = 'pending'`, matching the website. Two mechanisms exist for the same end behavior: a shared client-callable RPC, `resubmit_for_approval(p_table, p_id)` (`lib/services/resubmit_for_approval.dart`), called immediately before the content write for `properties`, builder projects, and broker profiles; and, for articles specifically, a single server-side Edge Function (`cms-posts-save`) that does the demotion atomically as part of the same write rather than as a separate prior RPC call (see the Article `cms-posts-save` decision below). Admin editors are skipped in both mechanisms and publish straight through, matching the website's admin behavior.

### Reason
Code comment in `lib/services/resubmit_for_approval.dart` states this explicitly: "Sends an owner's edit of already-published content back to review, the way the website does." Business rationale for why this parity mattered enough to add now is not currently verifiable beyond that comment.

### Files affected
`lib/services/resubmit_for_approval.dart` (new), `lib/services/property_service.dart`, `lib/services/project_service.dart`, `lib/services/broker_sections_service.dart`.

### Do not change without checking
Do not call the content-write for any of these tables without first calling `resubmitForApproval` for a non-admin owner's edit — skipping it silently re-introduces the original gap (an edit that never re-enters review). Do not reorder it to run after the write — the RPC's own doc comment states it must run first so a "previous-approved snapshot" trigger still sees the untouched row.

### Evidence
`lib/services/resubmit_for_approval.dart` (full file, 42 lines); `lib/services/property_service.dart` (`updateProperty`); `lib/services/project_service.dart`; `lib/services/broker_sections_service.dart` (`BrokerProfileService.save`). No dedicated test file exists yet — see `TEST_MAP.md` Test Gaps.

---

## Decision — Article writes moved server-side to a `cms-posts-save` Edge Function; the client-side edit lock was removed

Status: Active, added 2026-09-30

### Context
Direct `cms_posts` writes relied on an RLS policy requiring `approval_status = 'pending'` for an author's own UPDATE to match any rows — so an author could never edit an already-approved article at all (the update would silently match zero rows and report success). `ArticleModel.isEditable` and `ArticleEditorProvider`'s `ArticleLockReason`/`isLocked` existed specifically to detect this client-side and refuse to save, rather than let the RLS mismatch look like a successful no-op.

### Decision
`ArticleService.create`/`.update` now call a `cms-posts-save` Edge Function instead of writing `cms_posts` directly. The function derives author identity and the admin/publish decision from the caller's session server-side (the client no longer sends `authorName`/`userId`/`userType`/an admin flag in the write body) and, for a non-admin's finalize save of an already-approved article, demotes it back to `pending` in the same atomic write — so authors can now edit an approved article again (it goes back to review), rather than the editor refusing to save. `ArticleModel.isEditable` and the lock machinery were removed as dead code once the server took over enforcing/handling this.

### Reason
Code comment on `ArticleService._invokeSave` states the previous direct-write path "could never let an author edit an already-approved article" and that the new path "requir[es] re-approval" atomically instead. Deeper business rationale for the timing of this change is not currently verifiable beyond the comment.

### Files affected
`lib/services/article_service.dart`, `lib/models/article_model.dart`, `lib/providers/article_editor_provider.dart`.

### Do not change without checking
Do not reintroduce a direct `cms_posts` insert/update from the Flutter client — the RLS policy this was built around still requires `approval_status = 'pending'`, and reverting would silently restore the "can't edit an approved article" gap. Any change to the `cms-posts-save` request body must be cross-checked against the Edge Function's actual accepted fields (server source not present in this repository).

### Evidence
`lib/services/article_service.dart` (`_invokeSave`, `create`, `update`); removed code confirmed via `git show 498c412 -- lib/models/article_model.dart lib/providers/article_editor_provider.dart`. See `API_CONTRACTS.md` and `MODULE_MAP.md` → Article / Content Editor.

---

## Decision — Android release builds fail hard rather than falling back to debug signing

Status: Active, release-critical

### Context
A release build silently signed with a debug key would ship an unpublishable/insecure artifact without obvious warning.

### Decision
`android/app/build.gradle.kts`'s `gradle.taskGraph.whenReady` block fails the build outright if any task with "Release" in its name runs while `key.properties` is missing, any required signing property is blank, or the resolved keystore file doesn't exist on disk. This check is scoped to Release-named tasks only — debug/profile builds are unaffected.

### Reason
Inferred from the check's own structure and comments (lines 99-120) — a deliberate release-safety gate, not incidental.

### Files affected
`android/app/build.gradle.kts:10-120`.

### Do not change without checking
Never relax or bypass this gate to "fix" a build failure — the failure is the intended behavior when signing config is incomplete. See `RELEASE_SAFETY.md`.

### Evidence
`android/app/build.gradle.kts:10-120`.
