# Builder Flow — Portal Analysis & Flutter Implementation Plan

Functional reference: the React portal at `c:\Users\USER\Desktop\Flutter\propcid`.
No Supabase schema, SQL, RLS, RPC or Edge Function change is proposed. Every
table, policy and storage bucket below already exists and was read from the
migrations.

---

## 1. Portal builder flow — the complete map

### 1.1 Surfaces

| Surface | File | Lines | Role |
|---|---|---|---|
| Builder dashboard | `pages/BuilderDashboardManage.tsx` | 1,264 | Overview stats, charts, sections; route `/manage-builder-dashboard` |
| Dashboard chrome | `components/builder-dashboard/layout/{BuilderDashboardLayout,BuilderSidebar,BuilderTopNav}.tsx` | 215 | Sidebar nav: **Overview / Inventory / Marketed Offers / Team** |
| Dashboard cards | `components/builder-dashboard/*.tsx` (16 files) | ~1,600 | Stat cards, 5 chart cards, funnel, activity, project table, calendar |
| Projects manager | `features/property/BuilderProjectsManager.tsx` | 952 | Project list + offers list; edit / delete / share; hosts the wizard |
| **Project wizard** | `features/property/BuilderProjectWizard.tsx` | 1,438 | 5-step create/edit — the core of the flow |
| Inventory manager | `features/property/BuilderInventoryManager.tsx` | 670 | `project_inventory` CRUD per project |
| Team manager | `features/team/BuilderTeamManager.tsx` | 526 | `builder_team_members` |
| Network invitations | `features/network/BuilderNetworkInvitations.tsx` | 748 | `builder_networks` + `builder_network_invitations` |
| Ratings / testimonials | `features/profile/BuilderRatingsTestimonials.tsx` | 492 | `builder_ratings` + `builder_testimonials` |
| Registration | `features/registration/BuilderRegistration.tsx` | — | Already ported to Flutter |

**Builders never touch `properties`.** No portal builder surface creates,
edits or lists a property listing. Their entire inventory is
`builder_projects` → `project_inventory`.

### 1.2 `builder_projects` — the full column set

Base `CREATE` in `20250905144708`, then `20251002170139` (+`master_layout_url`),
`20251208170423` (+`approval_status`), `20251213062519` (+`website_url`,
`contact_number`, `logo_url`, `other_images`), `20260424130000` (+`likes`,
`views`), `20260630000000` (+`translations`).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `builder_id` | uuid | NOT NULL — `auth.uid()` |
| `title` | varchar(255) | NOT NULL |
| `description` | text | **NOT NULL, default `''`** |
| `project_type` | text | NOT NULL, CHECK — 8 values (§1.3) |
| `location` | text | NOT NULL |
| `status` | text | **NOT NULL**, default `'active'`, CHECK `active \| inactive \| completed \| under_construction` |
| `approval_status` | text | **NOT NULL**, default `'pending'` |
| `total_units`, `available_units` | integer | **NOT NULL, default 0** |
| `price_range_min/max`, `area_sqft_min/max` | numeric | **NOT NULL, default 0** |
| `latitude`, `longitude` | numeric | **NOT NULL, default 0** — the wizard never collects these |
| `amenities`, `media_urls`, `map_images`, `videos_urls`, `other_images` | text[] | **NOT NULL, default `{}`** |
| `brochure_url`, `website_url`, `contact_number`, `logo_url`, `master_layout_url`, `rera_number` | text | **NOT NULL, default `''`** |
| `completion_date`, `possession_date` | date | **Nullable** — the two deliberate exceptions |
| `likes`, `views` | integer | **NOT NULL**, default 0 |
| `translations` | jsonb | Not written by the wizard |
| `created_at`, `updated_at` | timestamptz | NOT NULL |

> **This is the single most important technical constraint in the whole feature.**
> `20270315000000_no_null_listing_and_project_columns.sql:251-275` makes **24
> columns NOT NULL**. Sending `null` for any of them fails the insert with a
> `23502`. The portal solves it with `dbText`/`dbNum`/`dbArray` coercion helpers
> (§1.5); Flutter must do the same. `completion_date` / `possession_date` are the
> only two that legitimately take `null`, via `dbDate`.

### 1.3 Vocabularies (verbatim — never invent)

`project_type` — the CHECK constraint **and** `PROJECT_TYPES`
(`BuilderProjectWizard.tsx:56-65`):

| value | label |
|---|---|
| `plotted_development` | Plotted Development |
| `group_housing` | Group Housing |
| `integrated_township` | Integrated Township |
| `gated_community_plots_villas` | Gated Community with Plots/Villas |
| `farm_houses` | Farm Houses |
| `service_apartment` | Service Apartments |
| `commercial_spaces` | Commercial Spaces |
| `office_spaces` | Office Spaces |

`COMMON_AMENITIES` (`:67-72`) — 19 suggestions, and the user may add free-text:
Swimming Pool, Gymnasium, Clubhouse, Children Play Area, Landscaped Gardens,
Security, 24/7 Power Backup, Parking, Elevator, Sports Complex, Community Hall,
Jogging Track, Senior Citizen Park, Library, Shopping Complex, School, Hospital,
ATM, Restaurant.

`status` — `active | inactive | completed | under_construction`.
`project_inventory.status` — `available | booked | sold | blocked`.

### 1.4 The wizard's 5 steps and their exact required-field rules

`STEPS` (`:251-257`) and `lib/validation/projectRules.ts`:

| # | key | Title | Required fields |
|---|---|---|---|
| 0 | `basic` | Basic Info | `title`, `project_type`, `location`, `description` |
| 1 | `details` | Project Details | `total_units` (>0), `available_units` (≥0), `price_range_min` (>0), `price_range_max` (>0), `area_sqft_min` (>0), `area_sqft_max` (>0), `completion_date`, `possession_date`, `rera_number` |
| 2 | `media` | Contact & Media | `website_url`, `contact_number` (phone format), `logo_url`, `map_images`, `brochure_url`, `other_images`, `videos_urls` |
| 3 | `amenities` | Amenities | at least one amenity |
| 4 | `review` | Review & Submit | none |

**Cross-field rule** (`projectRules.ts:88-104`): `available_units` may not exceed
`total_units` — reported against step `details`.

Gating behaviour: `handleNext` validates the current step and blocks; an
`attemptedRef` flag makes errors re-validate live once the user has tried once;
`handleSubmit` re-runs **every** step and jumps to the first that fails, with the
toast title `Incomplete: {step title}`.

**Every field on step 2 is required, including the brochure PDF and at least one
video.** That is unusually strict, and it is the reference.

### 1.5 The insert payload

`BuilderProjectWizard.tsx:493-525`. Coerced through `lib/validation/dbSafe.ts`:
`dbText → ''`, `dbNum → 0`, `dbArray → []` (blank entries dropped),
`dbDate → null` only when genuinely blank.

Two derived fields worth noting:

```ts
master_layout_url: dbText(formData.map_images?.[0]),   // mirrors the first master-plan upload
media_urls: [ ...media_urls, ...other_images, ...map_images ],  // the flattened gallery
```

`builder_id: user.id` is added on insert only. Update is
`.eq('id', editingProject.id).eq('builder_id', user.id)` — an owner check in the
query on top of RLS.

### 1.6 Media uploads

Bucket **`project-media`** — public, 50 MB limit
(`20260409000000_create_project_media_bucket.sql`, `20270302020000:11`).
Policies: public SELECT; authenticated INSERT/UPDATE/DELETE with **no path
restriction**.

| Asset | Path | Picker | Notes |
|---|---|---|---|
| Logo | `logos/{ts}-logo.{ext}` | single image | compressed first |
| Master layout | `master-layouts/{ts}-master-layout.{ext}` | single image | appended to `map_images` |
| Other images | `other-images/{ts}-{rand}.{ext}` | multi image | |
| Videos | `project-videos/{ts}-{rand}.{ext}` | multi video | **50 MB check after compression**, oversize skipped with a toast |
| Brochure | `brochures/{ts}-brochure.{ext}` | **PDF** | uploaded raw, no compression |

Paths are **not** namespaced by user — a flat folder per asset type, collisions
avoided by timestamp + random suffix.

### 1.7 Draft persistence

`localStorage['builder_project_wizard_draft']`. On open, if a draft exists the
wizard shows a "Resume Project?" prompt (fullscreen on mobile) offering *continue*
or *start fresh*. Cleared on successful create.

### 1.8 Dashboard stats

`fetchDashboardStats` (`BuilderDashboardManage.tsx:247-300`):

| Stat | Source |
|---|---|
| Total / active projects, total views | `builder_projects where builder_id` — counted and summed client-side |
| Network connections | `builder_networks where builder_id and status='accepted'` |
| Average rating | `builder_ratings where builder_id` — mean of `rating` |
| Total inventory, sold units | `project_inventory where project_id in (…)` |
| Site visits | `project_visit_bookings where project_id in (…)` |

Plus five chart series and a "Recent Activity" feed, all derived from the same
tables.

> **`builder_ratings` is not `user_ratings`.** The builder dashboard averages
> `builder_ratings`; the Public Profile screen and People Search average
> `user_ratings`. They are separate tables with separate rows, so a builder can
> legitimately show two different ratings in two places. Reported, not changed.

### 1.9 Project sharing

`handleShareProject` (`BuilderProjectsManager.tsx:308-380`): reads the builder's
display/company name, selects `builder_networks` where
`builder_id.eq.{uid} OR member_id.eq.{uid}` and `status='accepted'`, resolves the
*other* party in each row, dedupes, then sends one `notifyProjectShared`
notification per connection. Refuses with a toast when the network is empty.

### 1.10 RLS summary

| Table | Owner policy | Public read |
|---|---|---|
| `builder_projects` | `FOR ALL USING (builder_id = auth.uid()) WITH CHECK (same)` | `FOR SELECT USING (status = 'active')` |
| `project_inventory` | `FOR ALL USING (EXISTS project owned by auth.uid())` | `FOR SELECT USING (status = 'available')` |
| `builder_project_offers` | `FOR ALL TO authenticated USING (auth.uid() = builder_id)` | brokers can view active |
| `builder_networks` | `FOR ALL USING (builder_id = auth.uid())` + members may SELECT | — |
| `builder_ratings` | — | (public read) |
| `project_visit_bookings` | builder may view bookings for their projects | user may create |

Note the public read on `builder_projects` is `status = 'active'` **only** —
`approval_status` is not part of it, so an unapproved active project is publicly
visible. Portal behaviour; not changed here.

---

## 2. Flutter builder flow — current state

| Asset | File | Lines | State |
|---|---|---|---|
| Dashboard screen | `screens/dashboard/builder_dashboard_screen.dart` | 331 | Exists — Analytics / Content Manager / Audience tabs |
| Dashboard stats | `services/builder_dashboard_service.dart` | 121 | Reads projects, networks, `builder_ratings` |
| Stats widget | `screens/widgets/builder_stats_widget.dart` | 56 | Exists |
| Recent projects | `screens/widgets/builder_recent_projects_widget.dart` | 284 | Exists — read-only list |
| Quick actions | `screens/widgets/builder_quick_actions_widget.dart` | 95 | Exists |
| Project read | `services/builder_project_service.dart` | 30 | `getProjects` only; swallows errors → `[]`; uses `print` |
| Project model | `models/builder_project_model.dart` | 46 | **10 of 30 fields** |
| Dispatcher | `core/navigation/manage_dashboard_dispatcher.dart` | 54 | `builder` → `BuilderDashboardScreen` |
| Registration | `screens/profile_completion/builder_registration/` | — | Done |
| Project wizard | — | — | **Does not exist** |
| Project detail | — | — | **Does not exist** |
| Inventory | — | — | **Does not exist** |
| Offers | — | — | **Does not exist** |
| Team | — | — | **Does not exist** |

### 2.1 Two defects in what exists today

1. **"Add Project" creates a property listing.**
   `builder_dashboard_screen.dart:183` — `_onCreate()` pushes
   `AppConstants.postPropertyScreen`, the *listing* wizard. Both the FAB
   (`semanticLabel: 'Add project'`) and the Content tab's
   `createLabel: 'Add Project'` / `emptyActionLabel: 'Add Your First Project'`
   route there. A builder tapping "Add Project" today lands in the property flow
   and writes to `properties`, which no portal builder surface does.
2. **The builder dashboard renders a "My Listings" section**
   (`builder_dashboard_screen.dart`, `MyListingsSection(userId:)`). Builders have
   no listings in the portal model.

### 2.2 What can be reused as-is

- **The whole wizard kit**: `screens/post_property/portal_shell.dart`
  (`PortalProgressCard`, `WizardStep`), `portal_kit.dart` (`PortalCard`,
  `PortalTextField`, `PortalSelect`, `PortalLabelledField`, `PortalCheckbox`,
  `PortalStepHeader`, `PortalValidationSummary`, `PortalReadOnlyBox`,
  `PortalSectionDivider`), `portal_theme.dart`. This is what makes the project
  wizard look like it has always been there.
- **The validation engine**: `listing_validators.dart` — `isBlank`,
  `positiveNumber`, `nonNegativeNumber`, `validPhone`, all ported verbatim from
  `requiredFields.ts`, plus the `ListingRule` / `ListingIssue` types in
  `listing_validation_rules.dart`.
- `image_picker` for images and video; the `_mimeFromExt` + `uploadBinary` +
  `getPublicUrl` upload shape from `PropertyService._uploadMedia`.
- `DashboardTabSelector`, `DashboardContentBody`, `DashboardCard`,
  `DashboardSectionLabel`, `DashboardCreateFab`, `EmptyStateView`, `ScaleTap`.

---

## 3. Gap analysis

| # | Capability | Portal | Flutter | Gap |
|---|---|---|---|---|
| G1 | Create a project | 5-step wizard, 22 fields | **none** | Everything |
| G2 | Edit a project | same wizard, `editingProject` | none | Everything |
| G3 | Delete a project | `.delete().eq('id', …)` | none | Everything |
| G4 | Project media upload | 5 asset types, `project-media` | none | Everything |
| G5 | Full project model | 30 columns | 10 | 20 fields |
| G6 | Project list with actions | edit / delete / share / inventory | read-only list | Actions |
| G7 | Project detail view | `/project/:id` | none | Everything |
| G8 | Inventory | `project_inventory` CRUD | none | Everything |
| G9 | Marketed offers | `builder_project_offers` CRUD | none | Everything |
| G10 | Team | `builder_team_members` | none | Everything |
| G11 | Site visits | read `project_visit_bookings` | none | Everything |
| G12 | Draft persistence | localStorage | none | Everything |
| G13 | "Add Project" target | project wizard | **listing wizard** | Defect §2.1 |
| G14 | No listings for builders | true | "My Listings" section | Defect §2.1 |

### 3.1 One hard blocker

**The brochure PDF cannot be picked with the current dependency set.**
`brochure_url` is a *required* field on step 2 (`mediaRules`), the portal's input
is `accept=".pdf,application/pdf"`, and `pubspec.yaml` has only `image_picker` —
which cannot select a PDF. There is no `file_picker`.

Three ways out, none of which I will choose unilaterally:

- **(a) Add `file_picker`.** One new dependency; matches the portal exactly.
- **(b) Ship the wizard with the brochure field optional**, marked "add from the
  web portal". Mobile-created projects would then be missing a field the portal
  treats as mandatory.
- **(c) Defer step 2's brochure entirely** and block project creation on mobile
  until (a) is approved — not recommended.

**Decision needed → D3 below.**

---

## 4. Implementation plan

Ordered so each phase is independently shippable and testable. Every phase ends
with `flutter analyze` at the 447 baseline, the test suite with no new failures,
a debug build, and a stop for approval.

### Phase B1 — Model + service foundation *(no UI)*

**New files**
| File | Contents |
|---|---|
| `lib/models/project_model.dart` | `ProjectModel` — all 30 columns, `fromSupabase`, derived `coverImage`, `priceRangeLabel`, `areaRangeLabel`, `isActive`, `typeLabel` |
| `lib/core/constants/project_options.dart` | The 8 `project_type` values + labels, the 19 amenities, the 4 `status` values, the 4 inventory statuses — verbatim from §1.3 |
| `lib/services/project_service.dart` | `listMine`, `fetchById`, `create`, `update`, `delete`, `setStatus` |
| `lib/services/project_media_service.dart` | The 5 upload paths of §1.6 + `_mimeFromExt`, self-contained |
| `lib/core/validation/project_db_safe.dart` | `dbText` / `dbNum` / `dbInt` / `dbArray` / `dbDate` — ports of `dbSafe.ts`, the answer to the 24 NOT NULL columns |

**Existing files touched:** none.
`builder_project_service.dart` and `builder_project_model.dart` are left
completely alone — `builder_recent_projects_widget.dart` depends on both. The new
service is a companion, not a replacement. Retiring the old pair is proposed as
optional cleanup in B8.

**Tests:** payload coercion (every NOT NULL column gets a concrete value, dates
stay nullable), the `master_layout_url` mirror, the `media_urls` flatten, the
vocabularies against the CHECK constraints, upload path formats.

### Phase B2 — The project wizard

**New files**
| File | Contents |
|---|---|
| `lib/screens/add_project/project_field_keys.dart` | Field-name constants |
| `lib/screens/add_project/project_validation_rules.dart` | The 5 step rule tables + the cross-field unit check — a direct port of `projectRules.ts` |
| `lib/providers/add_project_provider.dart` | Form state, step index, per-step issues, `attempted` flag, media lists, upload progress, draft load/save, submit |
| `lib/screens/add_project/add_project_screen.dart` | Wizard shell, reusing `PortalProgressCard` + `PortalShell` |
| `lib/screens/add_project/steps/basic_info_step.dart` | title, project_type, location, description |
| `lib/screens/add_project/steps/project_details_step.dart` | units, price range, area range, dates, RERA |
| `lib/screens/add_project/steps/contact_media_step.dart` | website, contact, logo, master layout, brochure, images, videos |
| `lib/screens/add_project/steps/project_amenities_step.dart` | 19 chips + free-text add |
| `lib/screens/add_project/steps/project_review_step.dart` | Read-only summary + submit |
| `lib/screens/add_project/project_submission_confirmation_screen.dart` | Mirrors the listing flow's confirmation |

Draft persistence via `shared_preferences` (already a dependency) under
`builder_project_wizard_draft`, matching the portal's key.

**Existing files touched:** `app_constants.dart` (+2 route constants),
`app.dart` (+2 imports, +2 route cases). Additive only.

**Tests:** the full 5-step gating truth table, the cross-field rule, the
`Incomplete: {step}` jump-to-first-failure behaviour, draft round-trip, the
submit payload, edit-mode prefill.

### Phase B3 — Rewire the dashboard *(the defect fix)*

**Existing file touched — `builder_dashboard_screen.dart`, two edits:**
1. `_onCreate()` → push the new project wizard route instead of
   `postPropertyScreen`.
2. Remove the `MyListingsSection` entry and its label from the Content tab's
   `sections` list.

Nothing else in that file changes — tabs, FAB, analytics, audience, stats,
quick actions and recent projects all stay exactly as they are.

**New file:** `lib/screens/dashboard/widgets/my_projects_section.dart` — the
project list with per-row **Edit / Delete / Share / Manage** actions, replacing
the read-only recent list *in place* (the existing
`builder_recent_projects_widget.dart` is not modified; the new section is added
and the old one stays for now, or is swapped on approval).

> ⚠️ Edit 2 is a **deletion of existing UI**. You told me builders have no
> listings, which I read as approval — but if any builder in production already
> has rows in `properties`, removing this section makes them unreachable from the
> dashboard. **Decision needed → D2.**

### Phase B4 — Project detail / manage screen

`lib/screens/project/project_detail_screen.dart` + route.
Gallery, type/status pills, price and area ranges, units, dates, RERA, amenities,
brochure link (`url_launcher`), website and contact, master layout, videos.
Owner sees Edit / Delete / Manage Inventory; a non-owner sees the public view.

This also un-blocks two things that are currently dead: the `global_search`
RPC's `project` suggestions (dropped in `search_screen.dart` because no such
screen existed) and any project card tap.

### Phase B5 — Inventory *(`project_inventory`)*

Service + provider + list/edit sheet. Fields: `unit_type`, `unit_number`,
`floor_number`, `area_sqft`, `price`, `status`, `amenities`, `features`,
`facing_direction`, `floor_plan_url`. Owner-scoped by the RLS `EXISTS` policy.

### Phase B6 — Marketed offers *(`builder_project_offers`)*

Service + provider + create sheet + list. Fields: `project_id`, `offer_title`,
`offer_description`, `offer_media_urls`, `status`.

### Phase B7 — Site visit bookings *(read-only)*

The builder's view of `project_visit_bookings` across their projects, and the
`totalSiteVisits` stat the dashboard already wants.

### Phase B8 — Team, then cleanup

`builder_team_members`, then the optional retirement of
`builder_project_service.dart` / `builder_project_model.dart` /
`builder_recent_projects_widget.dart` once `my_projects_section.dart` has
replaced them — reported, only performed on approval.

### Explicitly out of scope

- **Network** — `builder_networks` is already covered by the existing network
  screens and the Phase 6 connection work. Not rebuilt.
- **Ratings** — `builder_ratings` is already read by
  `BuilderDashboardService`. A builder-facing ratings *screen* is deferred.
- **Charts** — the portal's five chart cards. The Flutter dashboard already has
  its own Analytics tab; duplicating the portal's charts would fight it.
- **Registration** — already ported.
- Anything touching `properties`, the listing wizard, Search, Home, or the
  profile module.

---

## 5. Decisions needed before B1

| # | Decision | Options | My recommendation |
|---|---|---|---|
| **D1** | Scope for this round | (a) B1–B4 only — a builder can create, edit, list, view and delete projects. (b) B1–B7. (c) All of B1–B8. | **(a)**, then reassess. B1–B4 is the difference between "broken" and "usable"; B5–B8 are additive surfaces that can land one at a time without blocking anything. |
| **D2** | Remove "My Listings" from the builder dashboard | (a) Remove — builders have no listings. (b) Keep it but hide when empty. (c) Leave untouched. | **(a)** if no builder has existing `properties` rows; **(b)** if any might. (b) is the safe default and costs one condition. |
| **D3** | The brochure PDF blocker (§3.1) | (a) Add `file_picker`. (b) Make brochure optional on mobile. (c) Defer. | **(a)**. `brochure_url` is required on the portal's step 2; making it optional means mobile-created projects are second-class, and (c) blocks the whole feature. |
| **D4** | `latitude` / `longitude` | The wizard never collects them; the columns are NOT NULL default 0, so every portal project has 0/0. (a) Match the portal — omit. (b) Add a map picker. | **(a)**. Adding a picker would make mobile projects behave differently from every existing row, and there is no portal UI to mirror. |
| **D5** | Step 2 strictness | The portal requires logo, master layout, brochure, ≥1 image **and** ≥1 video. (a) Reproduce exactly. (b) Relax videos to optional. | **(a)**. It is the reference, and relaxing it lets mobile create projects the portal would reject. Flagging it because it is a heavy ask on a phone. |
| **D6** | Old service/model pair | (a) Leave both, add the companion (safest). (b) Migrate the recent-projects widget to the new model in B3. | **(a)** for B1–B3, revisit in B8. |

---

## 6. Portal defects found — reported, not reproduced

- **PD1 — `latitude`/`longitude` are never collected.** Both are NOT NULL with
  default 0, so every project row sits at 0°,0°. The wizard has no map input and
  the payload omits both.
- **PD2 — public read ignores `approval_status`.** `builder_projects`' public
  policy is `USING (status = 'active')` only, so a project pending approval is
  publicly visible the moment it is created (`status` defaults to `'active'`).
- **PD3 — media paths are not user-namespaced.** Every builder's logos land in
  the same flat `logos/` folder, and the bucket's INSERT policy has no path
  restriction, so any authenticated user can write anywhere in `project-media`.
- **PD4 — two rating tables.** `builder_ratings` (dashboard) vs `user_ratings`
  (public profile, People Search). The same builder can show two different
  averages in two places.
- **PD5 — `BuilderProjectsManager.fetchProjects` re-fetches the user** with
  `supabase.auth.getUser()` even though `useAuth()` already has it.
- **PD6 — the offers query embeds `project:builder_projects(...)`** but the
  delete path (`handleDeleteOffer`) does not scope by `builder_id`, relying
  entirely on RLS.
- **PD7 — `master_layout_url` duplicates `map_images[0]`.** Two columns, one
  value, kept in sync by the client on every write.
- **PD8 — `sanitizeText` does not remove script content.** `utils/sanitize.ts:24`
  strips `</script>` *first*, which leaves the paired `<script>…</script>` matcher
  on `:25` with nothing to match. `<script>bad()</script>x` is stored as
  `<script>bad()x`. Every `dbText` value on the website passes through this, so it
  is not the sanitiser its name implies — the file's own header says server-side
  and RLS protections remain authoritative. No live injection path: React escapes
  by default and the Flutter side renders these values as text, never as HTML.
  Reproduced for parity and pinned by a test.
- **PD9 — `sanitizeText` deletes newlines instead of collapsing them.** A newline
  is `\x0A`, so the control-character strip on `:31` removes it before the
  `\s+ -> ' '` collapse on `:34` can turn it into a space. `'line one\nline two'`
  is stored as `'line oneline two'` — adjacent lines joined with **no separator**,
  not merely flattened. Every multi-line project description created on the
  website is already stored this way.
  **FIXED ON THE FLUTTER SIDE, one-sided divergence approved.** `\x09`–`\x0D`
  are converted to a space before the control-character strip, so the collapse
  behaves as the reference plainly intended and a multi-line description reads
  correctly. This is data corruption rather than a business rule, so it is not
  replicated into new code. The website still mangles its own input — worth
  raising with the portal team as a fix there too. Pinned by
  `test/builder_project_foundation_test.dart`.

---

## 7. What I will not do without being asked

- No schema, SQL, RLS, RPC or Edge Function change.
- No change to `properties`, `PropertyService`, `PostPropertyProvider`, the
  listing wizard, or any of its step files.
- No change to Search, Home, the profile module, or the network module.
- No new design tokens — the wizard kit and `AppColors`/`AppTextStyles` as they
  stand.
- No deletion of any existing file; §Phase B8's cleanup is a report until
  approved.
