# PropCid — User Profile Migration Plan (React Portal → Flutter)
## Revision 2 — constrained to frontend-only integration

**Governing constraints (non-negotiable, as stated 2026-08-05):**

1. No backend functionality modified.
2. No Supabase tables modified.
3. No SQL, RLS policies, Edge Functions, RPCs, or schema modified.
4. No migrations created.
5. No existing backend services or APIs modified.
6. No existing business logic modified unless absolutely required for UI integration.
7. Reuse existing Flutter providers, services, repositories, models, widgets wherever possible.
8. If a feature requires backend work → **stop and report**, do not implement.
9. Frontend integration only, against existing backend capabilities.
10. Stop after every phase and wait for approval.

---

# SECTION 0 — Headline finding

**No phase of this migration requires any backend work.** Every server-side capability the
portal's User Profile depends on already exists and is already reachable from Flutter with the
same anon key and the same `authenticated` role. I verified each write path against its actual
policy/grant rather than assuming:

| Capability | Verified permission | Source |
|---|---|---|
| Read own profile | table grant + RLS, owner | — |
| Read another profile (signed in) | `authenticated` retains the table-level SELECT grant | `20270311000000_profiles_hide_contact_from_anon.sql` |
| Read another profile (anon) | column-restricted grant; **`email`/`phone`/`mobile_number` excluded** | same |
| Update own profile | `can_update_profile_fields()` owner branch | `20270307000000_profile_guard_allow_service_role.sql` |
| `record_profile_view` RPC | `GRANT EXECUTE … TO authenticated` (revoked from `anon`/PUBLIC) | `20270316010000_profile_views.sql:172` |
| Read `profile_views` as owner | `"Owners can see who viewed their profile"` → `auth.uid() = profile_user_id` | same, §2 |
| Realtime on `profile_views` | `REPLICA IDENTITY FULL` + publication | same, §4 |
| Insert rating | `auth.uid() = rater_id AND auth.uid() <> rated_user_id` | `20251207160017_*.sql` |
| Update own rating | `auth.uid() = rater_id` | same |
| Read any rating | `USING (true)` | same |
| Upsert/delete `builder_networks` | `FOR ALL USING (builder_id = auth.uid() OR member_id = auth.uid())` | `20260428170000_broaden_network_types.sql:16` |
| Insert `notifications` for another user | `FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL)` | `20260315180000_security_hardening.sql:54` |
| Upload avatar / cover / documents | bucket policies require path segment 1 = `auth.uid()` | `20260317110000_create_required_storage_buckets.sql` |
| Insert `account_deletion_requests` | portal submits this from an unauthenticated form | `pages/AccountDeletion.tsx` |

Two findings materially changed the plan versus Revision 1:

- **`can_update_profile_fields()` is a BEFORE UPDATE trigger on `profiles`** that *silently rewrites*
  `user_role`, `is_blocked`, `approval_status` and `user_type` back to their old values for owner
  updates — it does not raise. So the portal's disabled user-type dropdown mirrors a real
  server-side guard, and Phase 3 must **omit those four columns from the payload entirely** rather
  than send-and-hope. A silent revert would otherwise look like a successful save.
- **Cross-user `notifications` inserts are permitted**, so Phase 6's connect notification works as
  the portal writes it. My Revision-1 concern that this might be silently failing was wrong.

---

# SECTION 1 — Phase classification

**Legend**

- 🟢 **FE-ONLY** — new frontend files plus purely additive wiring (route case, constant, provider
  registration). No existing logic altered. Safe to implement under all ten rules.
- 🟡 **NEEDS-APPROVAL** — frontend-only, but changes the behaviour of code that already exists.
  Permitted only under rule 6's "absolutely required for UI integration" test, so each item is
  listed individually with a justification for you to accept or reject.
- 🔴 **BACKEND-REQUIRED / EXCLUDED** — would need schema, RLS, SQL, RPC, edge-function or
  existing-service changes. **Not implemented. Reported only, per rule 8.**

| Phase | Title | Class |
|---|---|---|
| 0 | Model + read service | 🟢 FE-ONLY |
| 1 | Public profile screen | 🟢 FE-ONLY |
| 2 | Profile-view recording | 🟢 FE-ONLY |
| 3 | Edit Profile screen | 🟢 FE-ONLY + 🟡 one entry-point rewire |
| 4 | Avatar + cover upload | 🟢 FE-ONLY + 🟡 two widget edits |
| 5 | Ratings write path | 🟢 FE-ONLY |
| 6 | Network actions | 🟢 FE-ONLY |
| 7 | Settings, views list, account deletion | 🟢 FE-ONLY + 🟡 two behaviour changes |
| 8 | Polish | 🟡 mixed — itemised, individually approvable |
| — | Pre-existing defect fixes (C1.4, C1.5) | 🔴 EXCLUDED — reported below |
| — | Portal-side inconsistencies | 🔴 EXCLUDED — reported below |

**Interpretation of rule 5 I am applying, for your confirmation.** `lib/services/*.dart` in Flutter
are client-side data-access classes, not backend services. Where a phase says it *appends a new
method* to one (`ratings_service.dart`, `network_service.dart`, `profile_view_service.dart`), no
existing method signature or behaviour is touched. If you would rather these files not be edited at
all, say so and I will put the new methods in sibling files instead
(`ratings_write_service.dart`, `network_action_service.dart`, …) at the cost of splitting related
queries across two files. **Default assumption: appending is fine; modifying is not.**

---

# SECTION 2 — Reuse map (rule 7)

Nothing below is re-implemented. This is what each phase consumes as-is.

| Existing Flutter asset | Reused for | Change |
|---|---|---|
| `providers/auth_provider.dart` — `profileRow`, `userId`, `userType`, `refreshProfile()` | identity + completion input + post-save refresh | none |
| `core/utils/profile_completion.dart` (231 lines, exact port of the portal checklist) | completion card, edit-screen hints | none |
| `core/utils/profile_link.dart` (port of `profileSlug`/`profilePath` + QR + share message) | share, QR, deep links | none |
| `services/auth_service.dart` — `updateProfileFields()`, `getUserProfile()` | **the generic `profiles` writer/reader; the new write service delegates to it rather than issuing its own update** | none |
| `services/profile_view_service.dart` — `getCount()` | views tile | +2 methods (P2, P7) |
| `services/ratings_service.dart` — `getRatingSummary()` | rating tile | +4 methods (P5) |
| `services/network_service.dart` — `getAcceptedCount()` | connections tile | +4 methods (P6) |
| `services/property_service.dart` | listing queries, `property-media` URL handling | none |
| `providers/profile_provider.dart` | own-profile stats/content; the pattern the new providers copy | none |
| `models/profile_stats.dart` | stat tiles | none |
| `screens/profile/profile_role.dart` — `roleColor()`, `roleLabel()` | role pill | +2 helpers, existing two untouched |
| `screens/profile/widgets/profile_stats_row.dart` — incl. `formatCount()` (2.3K/1.2M) | stat tiles **and** the Meta follower tiles in P8 | +1 optional callback (P7) |
| `screens/profile/actions/share_profile_sheet.dart`, `profile_qr_sheet.dart` | share + QR from the public profile | none |
| `widgets/` — `verified_badge`, `role_guard`, `status_tag`, `section_header`, `manage_list_tile`, `property_card_*`, `bottom_nav_bar`, `more_bottom_sheet`, `workspace_drawer` | throughout | none |
| `widgets/shared/` — `app_action_button`, `app_surface_card`, `stat_kpi_card`, `toggle_row`, `section_header_back_button` | cards, tiles, settings rows | none |
| `core/widgets/` — `scale_tap`, `glass_card`, `shimmer_loader`, `empty_state_view`, `premium_button`, `segmented_tab_pill`, `step_indicator`, `wizard_kit` | interactions, loading, empty states | none |
| `core/theme/` — `AppColors`, `AppTextStyles`, `AppConstants` | all styling; **no new design tokens** | none |
| `core/validation/validators.dart`, `core/utils/text_input_formatters.dart` | edit-form validation | none |
| deps already present: `image_picker`, `share_plus`, `cached_network_image`, `shimmer`, `flutter_animate`, `url_launcher`, `shared_preferences` | uploads, sharing, images | **no new packages** |

---

# SECTION 3 — Phases

## 🟢 Phase 0 — Model + read service — FE-ONLY

**Backend used:** `profiles` SELECT only. No writes.

**Create (new files only)**

- `lib/models/user_profile.dart` — `profiles` row model. Tolerant `fromMap` (the anon grant is
  narrower than the row). Typed `socialMedia` accessor reading **both** key variants per role
  (`facebook`/`facebook_page_link`, `alternate_mobile`/`alt_mobile_number`,
  `primary_platform`/`primary_content_platform`, `instagram`/`instagram_username`, …).
  Derived getters mirroring the portal's fallback chains: `displayTitle`
  (`company_name ?? agency_name ?? display_name`), `effectiveCity` (`city ?? work_city`),
  `effectiveBio` (`bio ?? company_description`), `effectiveExperience`, `effectiveRera`
  (`rera_number ?? license_number`), `isVerified`
  (`verification_status == 'verified' || license_number != null || rera_number != null`).
- `lib/services/user_profile_service.dart`
  - `fetchOwn(userId)` → delegates to the existing `AuthService.getUserProfile()`; no duplicate query.
  - `fetchPublic(userId, {required bool viewerSignedIn})` → the portal's **two exact column lists**
    from `UserProfile.tsx:331-332`. This is a hard requirement, not a style choice: requesting
    `phone`/`email`/`mobile_number` while anonymous **errors** under the current grant.
  - `fetchProfilesByIds(ids)` for rater/viewer name resolution (the portal's `profilesMap` pattern).

**Modify:** nothing.

**Tests:** `test/user_profile_model_test.dart` — fallback chains; both social-key variants;
`isVerified`; and an assertion that the anon column list string is byte-identical to the portal's.

**Approval gate:** stop.

---

## 🟢 Phase 1 — Public profile screen — FE-ONLY

**Backend used:** SELECT on `profiles`, `properties`, `builder_projects`, `influencer_videos`,
`status`, `builder_networks`, `user_ratings`. Every one of these is a query the portal already issues
from the browser with the same anon key, so the same policies apply unchanged.

**Create**

- `lib/providers/public_profile_provider.dart` — `load(userId, viewerId)`; independent futures for
  profile / properties / builder projects / videos / statuses / connection count / my rating /
  reviews / network status, each with its own loading+failed flag (copying `ProfileProvider`'s shape).
- `lib/services/profile_content_service.dart` — the five content queries, filters copied exactly:
  - `properties`: `status in ('active','sold')`, `created_at desc`
  - `builder_projects`: `status='active'`, **plus `approval_status='approved'` only when the viewer is not the owner**
  - `influencer_videos`: `status='active'`
  - `status`: `is_active=true AND expires_at >= now()`
- `lib/screens/profile/public_profile_screen.dart` — single-column mobile adaptation of
  `UserProfile.tsx`, preserving its order, headings, labels and helper text per `CLAUDE.md`:
  app bar → cover hero → identity card (avatar + shield, name + role pill, role subtitle, star row,
  info strip) → stat tiles (Active Listings · Connections, hidden for `individual` · Rating) →
  action row (Edit if self, else the four-state network button; + Message; + Share) → About Me →
  Business Details / Personal Details / Influencer Stats / Builder Details / Broker Insights (same
  conditions as the portal) → Contact Information behind the connected-or-self gate → Listings with
  6-per-page pagination and the sold overlay → Client Reviews (score panel, Broker Trust Score for
  builders, quote cards) → Trust badges.
- `lib/screens/profile/widgets/` — `public_profile_header.dart`, `profile_detail_card.dart`,
  `profile_contact_card.dart`, `profile_reviews_block.dart`, `profile_trust_badges.dart`,
  `profile_listing_grid.dart`.

**Modify (additive only)**

- `core/constants/app_constants.dart` — add `publicProfileScreen = '/public-profile'`.
- `app.dart` — add one `case`, args `{userId}`.
- `screens/profile/profile_role.dart` — **append** `roleSubtitle()` / `roleBadge()`; the existing two
  functions are untouched.
- `main.dart` **and** `test/widget_test.dart` — register `PublicProfileProvider` in **both** (existing
  project convention; the two trees must not drift).

**Deliberately out of scope, and why**

- The 10-second anonymous login nag and the 30-minute `sessionStorage.tempAuth` window — no Flutter
  `MobileLoginModal` equivalent exists, and building one is a separate auth workstream.
- The self-only "My Connections" tab — routes to the existing `AppConstants.myNetworksScreen` instead.
- Meta follower tiles — deferred to Phase 8 for scope reasons only. No auth restriction applies
  (see 🟢 R3: the columns are granted to `anon`).

**Tests:** `test/public_profile_parity_test.dart` — contact hidden unless connected/self; connections
tile hidden for `individual`; builders use `customerRating`; pagination = 6; visitor sees only
approved projects.

**Approval gate:** stop.

---

## 🟢 Phase 2 — Profile-view recording — FE-ONLY

**Backend used:** `record_profile_view(uuid)` — exists, `EXECUTE` granted to `authenticated`,
SECURITY DEFINER, idempotent, no-ops for anon and self-views, rate-limits its own notifications on a
30-minute cooldown, and **inserts the `profile_view` notification itself**. Called, not modified.

**Modify (additive)**

- `services/profile_view_service.dart` — **append** `recordView(profileUserId)`:
  `rpc('record_profile_view', params: {'p_profile_user_id': …})`; skip for anon and self; guard with
  a `shared_preferences` key `profileViewed:{viewer}:{owner}`, **removed on error** so a later visit
  retries. The existing `getCount()` and the file's explanatory comment are untouched — though the
  comment that recording is "deliberately not implemented" becomes stale and should be updated in
  the same edit.
- `providers/public_profile_provider.dart` — fire once per load, after the profile resolves.

**Known behavioural difference to record:** the portal's guard uses `sessionStorage` (cleared when
the tab closes); `shared_preferences` persists across app launches, so Flutter will suppress repeat
recordings more aggressively. This is acceptable because the RPC is idempotent and applies its own
cooldown — but it is a real difference, not a faithful port. Alternative if you prefer web parity: an
in-memory `Set` on the provider, which resets on app restart.

**Tests:** anon and self no-op; second call in a session suppressed; failure clears the guard.

**Approval gate:** stop.

---

## Phase 3 — Edit Profile screen — 🟢 FE-ONLY + 🟡 one rewire

**Backend used:** `profiles` UPDATE (owner branch of the existing trigger) and the `user_preferences`
select-then-insert/update the portal already performs. No new columns, no new tables.

**Design consequence of the trigger — important.** `can_update_profile_fields()` silently reverts
`user_role`, `is_blocked`, `approval_status` and (once set) `user_type`. The payload therefore
**omits all four**. The user-type dropdown is disabled once set, with the portal's exact note
"Role cannot be changed once set." — which now reads as UI honesty about a server guard rather than
an arbitrary restriction.

**Create**

- `lib/screens/profile/edit_profile_screen.dart` — sectioned form matching `EditProfile.tsx`'s order,
  headings and helper text; role sections switch on `user_type`.
- `lib/providers/edit_profile_provider.dart` — load, controllers, validation, payload, save, then
  `AuthProvider.refreshProfile()`.
- `lib/services/profile_write_service.dart` — the single `profiles` writer. **Delegates to the
  existing `AuthService.updateProfileFields()`** rather than issuing its own update (rule 7).
  Responsibilities:
  - **merge-first `social_media`** (`{...existing, ...changes}`) — never overwrite; the portal
    depends on this to preserve keys neither screen knows about
  - the paired-column writes: `website`+`website_url`, `bio`+`company_description`,
    `years_experience`+`years_of_experience`, `rera_number`+`license_number`, `city`+`work_city`
  - role-conditional column set (basic-only for `individual`)
  - the `user_preferences` city upsert for builder/broker
- `lib/core/validation/profile_validators.dart` — phone ≥10 digits after stripping non-digits, email
  regex, alt mobile ≥10, pincode ==6, GST ==15, PAN ==10 unless the literal sentinel `"uploaded"`.
- `lib/core/constants/profile_options.dart` — `CONTENT_TYPES_OPTIONS` (8),
  `PROMOTION_TYPE_OPTIONS` (4), `EXPERTISE_OPTIONS` (8), `LANGUAGE_OPTIONS` (10), country codes,
  gender, company structure, broker type, influencer category, primary platform — **copied verbatim
  from `EditProfile.tsx`; never invented** (`CLAUDE.md`: "Never invent dropdown values").

**Modify (additive)** — `app_constants.dart` (`editProfileScreen = '/edit-profile'`), `app.dart`
(one case), `main.dart` + `test/widget_test.dart` (provider in both).

**🟡 A-1 — requires your approval.** `screens/profile/profile_screen.dart:113-127` currently routes
builder/broker/influencer to `/builder-profile` etc., which are the **7-step registration wizards** —
so "Edit Profile" today restarts registration rather than editing. Pointing `_editProfile()` at the
new screen changes existing navigation behaviour.
- *Justification under rule 6:* without it the new screen has no entry point for the three roles that
  most need it.
- *Option A (recommended):* repoint all four roles at the new screen; wizards stay reachable for
  first-time completion via the existing splash / `profile_completion_coordinator` / `rbac_service`
  paths, which are untouched.
- *Option B (zero behaviour change):* leave `_editProfile()` alone and add a separate "Edit details"
  row to the Manage list. Both paths then coexist, which is confusing but strictly additive.

**Not touched:** `AuthProvider.updateProfile` (the in-memory-only method) and
`actions/edit_profile_dialog.dart` are left exactly as they are. See 🔴 R5 for the defect this leaves
in place.

**Tests:** `test/edit_profile_parity_test.dart` — `social_media` merge preserves unknown keys; paired
columns both written; individual writes basic columns only; the four trigger-guarded columns absent
from the payload; every validation threshold.

**Approval gate:** stop.

---

## Phase 4 — Avatar + cover upload — 🟢 FE-ONLY + 🟡 two widget edits

**Backend used:** existing `avatars` and `property-media` buckets. Both policies require path segment
1 to equal `auth.uid()`; every path below satisfies that. No bucket, policy or edge function touched.

**Create**

- `lib/services/profile_media_service.dart` — `image_picker` → upload → `getPublicUrl` → `profiles`
  update (via `ProfileWriteService`, so there is one writer):
  - avatar → **`avatars`**, `{userId}/{timestamp}.{ext}` → `avatar_url` (matches `AvatarUploadModal`)
  - cover → **`property-media`**, `{userId}/{timestamp}_background.{ext}` → `background_image_url`
    (matches `BackgroundUploadModal`)
  - documents → **`avatars`**, `{userId}/{type}_{timestamp}.{ext}` (matches `EditProfile.uploadFile`)
- `lib/screens/profile/actions/avatar_picker_sheet.dart`, `cover_picker_sheet.dart`

**Compression:** the portal compresses client-side (max 1024 px avatar, 1920 px cover).
`image_picker`'s `maxWidth`/`maxHeight`/`imageQuality` approximates this — the same approach
`post_property/steps/media_contact_step.dart:80` already documents. No new package.

**Cropping:** the portal offers `react-easy-crop` zoom + 90° rotate. Flutter has no equivalent in the
current dependency set. **Phase 4 ships pick-and-upload without cropping.** Adding a cropper means a
new package (`image_cropper`, which also needs Android/iOS native config) — flagged as a decision,
not silently included.

**🟡 A-2.** `widgets/profile_cover_header.dart` — render `background_image_url` when present (gradient
stays as the fallback), add the owner-only camera affordance, and delete the now-false comment at
lines 10-13 claiming the column is unread and has no upload path.
*Justification:* the widget currently hard-codes the cover; there is no way to display an uploaded one
without editing it.

**🟡 A-3.** `screens/profile/edit_profile_screen.dart` gains the document-upload rows — new file from
Phase 3, so this is only 🟡 if Phase 3 has already shipped.

**Explicitly excluded here:** the `'placeholder_profile.jpg'` defect in `ProfileService` — see 🔴 R1.
The new upload path is self-contained and does not require touching that method.

**Tests:** correct bucket + path per media type; `profiles` column updated; oversize rejected.

**Approval gate:** stop.

---

## 🟢 Phase 5 — Ratings write path — FE-ONLY

**Backend used:** `user_ratings` — SELECT `USING (true)`; INSERT
`WITH CHECK (auth.uid() = rater_id AND auth.uid() <> rated_user_id)`; UPDATE
`USING (auth.uid() = rater_id)`. All three verified present.

**Create**

- `lib/screens/profile/actions/rating_sheet.dart` — 1–5 stars with the portal's
  Poor / Fair / Good / Very Good / Excellent labels; ≤500-char review with counter.
- `lib/screens/profile/widgets/user_ratings_list.dart` — port of `UserRatingsDisplay`: rater avatar,
  name, role badge, relative time, stars, review.

**Modify (additive)**

- `services/ratings_service.dart` — **append** `fetchMyRating(ratedUserId, raterId)` (`maybeSingle`),
  `submitRating(...)`, `updateRating(id, …)`, `fetchReviews(userId, limit: 5)` with rater-name
  resolution, and `getCategorisedRatings(userId)` returning `(customer, broker, total)` using the
  portal's rule — customer = every rater whose `user_type != 'broker'`. Handle Postgres `23505`
  (unique violation) as the portal's "Already Rated" case. `getRatingSummary()` untouched.
- `public_profile_provider.dart` — hold `myRating`, refresh after submit.
- `public_profile_screen.dart` — Write/Update Review button, signed-in and not self.

**Tests:** insert vs update branch; customer/broker split; `23505` handled; builder shows customer
average plus broker trust score.

**Approval gate:** stop.

---

## 🟢 Phase 6 — Network actions — FE-ONLY

**Backend used:** `builder_networks` `FOR ALL USING (builder_id = auth.uid() OR member_id = auth.uid())`
— for a `FOR ALL` policy Postgres applies `USING` as the insert check, and the sender is always
`member_id`, so the upsert passes. `builder_network_invitations` has symmetric policies.
`notifications` INSERT is open to any authenticated user, so the cross-user notification the portal
writes is permitted.

**Modify (additive)**

- `services/network_service.dart` — **append**:
  - `getConnectionStatus(viewerId, ownerId)` — `builder_networks` first, then
    `builder_network_invitations` with `status in ('pending','accepted')`
  - `sendConnectionRequest(...)` — **upsert**, `onConflict: 'builder_id,member_id'`, recipient as
    `builder_id`, sender as `member_id`, `member_type` from the sender's `user_type`; then the
    `builder_network_addition` notification insert. Upsert (not insert) is what lets a re-connect
    after a prior removal revive the row instead of violating the unique constraint.
  - `cancelRequest(...)` — delete from **both** tables where `status='pending'`
  - `acceptRequest(...)` — update `builder_networks`; else accept the legacy invitation and upsert the
    network row
  - `getAcceptedCount()` untouched.
- `public_profile_provider.dart` + `public_profile_screen.dart` — four-state button
  (`none` / `pending_sent` / `pending_received` / `connected`).

**Tolerated-failure parity:** the portal logs and continues if the notification insert fails
(`UserProfile.tsx:642-644`). Flutter does the same — the connection must succeed even if the
notification does not.

**Tests:** each transition; re-connect after removal upserts cleanly; notification inserted once;
notification failure does not fail the connection.

**Approval gate:** stop.

---

## Phase 7 — Settings, views list, account deletion — 🟢 FE-ONLY + 🟡 two behaviour changes

**Backend used:** `profiles` UPDATE (owner) for `comments_enabled` + `work_city`; `profile_views`
SELECT as owner (policy verified) plus optional realtime (`REPLICA IDENTITY FULL` already set);
`account_deletion_requests` INSERT.

**Create**

- `lib/screens/profile/profile_views_screen.dart` — port of `ProfileViews.tsx`: unique-viewer summary,
  total-visits secondary, viewer rows with relative time and the "viewed N times" badge, empty and
  loading states.
- `lib/providers/profile_views_provider.dart` — list + count; optional realtime channel on
  `profile_views` filtered by `profile_user_id`.
- `lib/screens/profile/account_deletion_screen.dart` — email-or-phone form, the "what happens next"
  copy, success state.

**Modify (additive)**

- `services/profile_view_service.dart` — **append** `fetchViewers(userId, limit: 200)` plus profile
  resolution. `profile_views` references `auth.users`, not `profiles`, so **there is no embeddable
  PostgREST relationship** — the portal issues a second query, and so must Flutter. Attempting an
  embed here would fail and is exactly the kind of thing that would otherwise get mistaken for
  needing a backend change.
- `widgets/profile_stats_row.dart` — **append an optional** `onProfileViewsTap` callback. Existing
  callers are unaffected.
- `app_constants.dart`, `app.dart`, `main.dart`, `test/widget_test.dart` — additive.

**🟡 A-4.** `screens/profile/actions/settings_sheet.dart` — persist `comments_enabled` and `work_city`
(the only two the portal actually saves).
*Justification:* the five toggles are currently documented no-ops that show no feedback, so a user
believes settings saved when nothing did. Low risk precisely because there is no existing behaviour to
preserve. The three genuinely client-side toggles (dark mode, push, location) should be either clearly
labelled local or removed rather than left silently inert — **your call which.**

**🟡 A-5.** `voice_agent/tools/profile_tools.dart` — the existing `delete_account` tool
(line 211) currently has no destination; point it at the new screen.
*Justification:* leaving it dangling means a voice command that does nothing.
*Note:* the portal's flow files a **deletion request** for review — it does not delete the account.
The tool's name and description promise more than the backend does; renaming or re-describing it is a
separate decision I am not making unilaterally.

**Approval gate:** stop.

---

## Phase 8 — Polish — 🟡 itemised, approve individually

| Item | Class | Notes |
|---|---|---|
| **P8-1** Meta follower tiles (`ig_followers_count`, `ig_follows_count`, `fb_followers_count`) | 🟢 | Reuses `_StatTile.formatCount`, which already renders 2.3K/1.2M. Visible to **all** viewers — see 🟢 R3 |
| **P8-2** Visiting-card share image: Flutter `CustomPainter` → PNG → `share_plus` `XFile` | 🟢 for the image itself | Replaces the current text-only share |
| **P8-3** Invoking the existing `save-visiting-card` edge function to publish the OG image | 🟡 invoke-only | The function exists and is unmodified, but this writes to storage via the service role. **Not doing this without explicit approval** |
| **P8-4** Align the verified badge with the portal's condition (`verification_status == 'verified' \|\| license_number \|\| rera_number`) instead of Flutter's `auth.userRole != null` | 🟡 | Changes an existing visual rule on the own-profile header |
| **P8-5** Resolve the three dead `profile_completion/*_profile_screen.dart` files (1,134 lines, referenced nowhere) | 🟡 | Delete, or repurpose as the role edit screens. Deletion is safe but irreversible-ish — your call |

**Approval gate:** stop.

---

# SECTION 4 — 🔴 Reported, NOT implemented (rule 8)

None of these block any phase above. All are pre-existing and none require my touching them to
deliver the migration.

**🔴 R1 — Fake avatar in the registration wizards.**
`builder_registration_screen.dart:30-31, 540, 547` sets `_profilePhotoPath = 'placeholder_profile.jpg'`
and `_companyLogoPath = 'placeholder_logo.jpg'`; `builder_registration_screen.dart:153` passes the
first into `ProfileService.saveBuilderProfile`, which writes it to `profiles.avatar_url`
(`profile_service.dart:58`). Every builder who completes registration gets a broken avatar URL.
*Why excluded:* fixing it modifies existing write logic in an existing service (rules 5, 6). Phase 4's
upload path is independent and does not need it. **Existing rows already carry the bad value and would
need a data fix — that part is unambiguously backend work.**

**🔴 R2 — Registration wizards discard most of what they collect.**
`saveBuilderProfile` persists 13 of ~30 inputs; `social_media` is never written for builder or broker,
so gender, DOB, GST, PAN, landmark, alternate mobile, areas of expertise, languages known and all six
social handles are collected from the user and dropped
(`profile_service.dart:37-63`; `broker_registration_screen.dart:136-152`, which additionally
hard-codes `website: ''`).
*Why excluded:* same rules. *Consequence to be aware of:* until this is fixed, Phase 3's edit screen
will show those fields as empty for users who already filled them in during registration, and the
completion percentage will under-report. This is the single highest-value follow-up.

**🟢 R3 — CORRECTED: the follower columns ARE readable by `anon`. No issue.**
Revision 2 of this plan claimed `fb_followers_count`, `ig_followers_count`, `ig_follows_count`,
`ig_media_count` and `social_followers_synced_at` were missing from the `anon` grant. **That was
wrong.** Migration `20270312000000_social_follower_counts.sql:76-79` grants them explicitly:

```sql
-- New columns are NOT auto-granted to anon (see 20270311000000). Grant SELECT on
-- just these public vanity counts so logged-out visitors see them too.
GRANT SELECT (
  fb_followers_count, ig_followers_count, ig_follows_count,
  ig_media_count, social_followers_synced_at
) ON public.profiles TO anon;
```

The columns are absent from `integrations/supabase/types.ts` (which is why the portal casts with
`(supabase as any)`), but that is a stale generated type, not a permission. **Consequences:**
follower stats may be shown to logged-out visitors; the portal's `publicCols` list — which includes
all five — is correct as written and is copied verbatim by `UserProfileService.fetchPublic`; P8-1 has
no auth restriction.

**Only `email`, `phone` and `mobile_number` are withheld from `anon`** (migration `20270311000000`).
Those three remain the sole reason `fetchPublic` needs two column lists.

**🔴 R4 — Portal avatar-bucket inconsistency.**
`EditProfile` and `AvatarUploadModal` write avatars to `avatars`; `UserProfile`'s inline handler
writes them to `property-media`. Flutter follows the `avatars` convention. Reconciling the portal is a
portal change, out of scope.

**🔴 R5 — `edit_profile_dialog` reports a save that never happens.**
`edit_profile_dialog.dart:63` calls `AuthProvider.updateProfile`, which only mutates in-memory fields
(`auth_provider.dart:301-306`), then shows "Profile updated successfully". Phase 3 supersedes this
path but, under rule 6, **leaves the dialog and the provider method in place**, so the defect survives
unless you approve either 🟡 A-1 Option A (which removes the entry point) or a separate deletion.

**🔴 R6 — `broker_profiles` is written but never read.**
`ProfileService.saveBrokerProfile` upserts a separate `broker_profiles` table *and* mirrors onto
`profiles`; nothing in the portal reads `broker_profiles`. Flutter keeps writing it (removing the
write would change existing behaviour) and sources every read from `profiles`.

**🔴 R7 — `approval_status: 'pending'` writes are silently discarded.**
`profile_service.dart:59` and the broker path both send `approval_status: 'pending'`, which
`can_update_profile_fields()` reverts to the old value for non-admin owners. Harmless today, but the
code reads as though it works. Reported, not touched.

---

# SECTION 5 — Risks carried into implementation

| # | Risk | Handling |
|---|---|---|
| E1 | Requesting PII columns while anonymous **errors** | Phase 0 reproduces the portal's conditional column lists exactly and asserts them in a test |
| E2 | `can_update_profile_fields()` reverts silently rather than erroring | Phase 3 omits all four guarded columns; a test asserts their absence from the payload |
| E3 | `shared_preferences` persists across launches where `sessionStorage` did not | Documented in Phase 2 with an in-memory alternative offered |
| E4 | No `profile_views` ↔ `profiles` PostgREST relationship | Two-query pattern, matching the portal |
| E5 | No crop UI without a new package | Phase 4 ships without cropping; adding `image_cropper` is a flagged decision |
| E6 | `main.dart` / `test/widget_test.dart` provider trees drift | Every provider-adding phase updates both |
| E7 | `AppTheme.inputDecorationTheme` leaks borders into custom-container `TextField`s | The edit form uses ordinary `InputDecoration`, so it is unaffected; any borderless field must use the six-slot + `filled:false` recipe from `search_bar_widget.dart` |
| E8 | Portal `UserProfile` is a desktop two-column layout | Adapted to one column per `CLAUDE.md` ("only adapt layouts where required because of mobile screen width"); order, headings, labels and helper text preserved |

---

# SECTION 6 — Sequencing and what I need from you

**Recommended first delivery:** Phases 0 → 1 → 2 (a working public profile that records views).
All three are 🟢 FE-ONLY with zero approval gates beyond the per-phase stop.

**Decisions needed before Phase 1 starts**

- D1 — Message button: reuse `AppConstants.chatThreadScreen`? (assumed yes)
- D2 — Confirm skipping the anonymous login nag and `tempAuth` window
- D3 — Confirm the self-only "My Connections" tab defers to `myNetworksScreen`
- D4 — Confirm my rule-5 reading: appending new methods to existing Flutter *client* services is
  acceptable; if not, they go in sibling files

**Approvals needed later, not now:** 🟡 A-1 (Phase 3), A-2/A-3 (Phase 4), A-4/A-5 (Phase 7),
P8-3/P8-4/P8-5 (Phase 8).
