# PropCid Flutter — Safe Implementation Rules

Binding for every phase of the User Profile migration. These rules outrank convenience, elegance and
my own judgement about what "should" be cleaned up. Where a rule and a nicer design conflict, the
rule wins.

---

## R1 · All changes must be additive

New files, new classes, new methods, new optional parameters, new `case` branches, new constants.

**Additive means:** existing code paths execute exactly as before. If a behaviour a user could
observe today changes, the change is not additive — regardless of how the diff looks.

- ✅ Append a method to a service; the existing methods are untouched.
- ✅ Add an **optional** named parameter with a default that preserves current behaviour.
- ✅ Add a `case` to `onGenerateRoute`.
- ❌ Change an existing method's signature, return type, or nullability.
- ❌ Make an existing optional parameter required.
- ❌ Reorder, rename or "tidy" existing members while nearby.
- ❌ Reformat an existing file wholesale — it buries the real change and defeats review.

## R2 · Do not replace existing implementations

If a capability already exists, call it. Do not write a second, better one beside it.

- `AuthService.updateProfileFields()` is the generic `profiles` writer → `ProfileWriteService`
  **delegates** to it, it does not issue its own `.update()`.
- `AuthService.getUserProfile()` is the own-profile read → `UserProfileService.fetchOwn()`
  **delegates** to it.
- `calculateProfileCompletion()` is the completion checklist → consumed read-only, never re-derived.
- `profileSlug` / `profilePath` / `profileShareUrl` / `profileQrImageUrl` already exist → reused.
- `EmptyStateView`, `AppActionButton`, `MetricCardGrid`, `DashboardCard`, `SegmentedTabPill`,
  `ScaleTap`, `PropertyCardCompact`, `SectionHeader` already exist → reused.

Two implementations of one rule is how the two platforms silently diverge. If an existing primitive
is *nearly* right, extend it with an optional parameter or wrap it — do not fork it.

## R3 · Do not modify backend functionality

No change to any server-side behaviour, in any phase, for any reason.

## R4 · Do not modify Supabase, SQL, RLS, Edge Functions, RPCs, APIs or schema

Untouchable paths:

```
supabase/**            *.sql             supabase/migrations/**
supabase/functions/**  supabase/config.toml
```

No `CREATE`, `ALTER`, `DROP`, `GRANT`, `REVOKE`, `CREATE POLICY`, or function definition. No new
migration file. Existing RPCs may be **called**; never redefined.

## R5 · Do not modify existing business logic unless absolutely required

"Absolutely required" means: **the approved feature cannot be delivered any other way.** It does not
mean easier, tidier, or more correct.

The five edits that pass this test are pre-identified and individually approvable:
**A-1** (Phase 3 edit entry point) · **A-2** (Phase 4 cover render) · **A-4** (Phase 7 settings
persistence) · **A-5** (Phase 7 voice-tool destination) · **P8-4** (Phase 8 verified condition).

Anything not on that list is out of bounds. In particular, these known defects stay broken:

| Ref | Defect | Why it stays |
|---|---|---|
| **R1-defect** | `'placeholder_profile.jpg'` written to `avatar_url` | modifies an existing write path; also needs a data fix (backend) |
| **R2-defect** | Registration wizards discard ~17 of ~30 fields, incl. all `social_media` for builder/broker | modifies existing write logic |
| **R5-defect** | `edit_profile_dialog` reports a save that never persists | superseded, not repaired |
| **R6-defect** | `broker_profiles` written but never read | removing the write changes behaviour |
| **R7-defect** | `approval_status: 'pending'` silently discarded by the DB trigger | harmless; touching it is not required |

Finding one of these while working nearby is **not** authorisation to fix it. Report it.

## R6 · Existing methods must never change behaviour

For every method that exists today: same name, same parameters, same return type, same side effects,
same error behaviour, same output for the same input.

Explicitly protected, because other modules depend on their exact contracts:

| Method | Contract that must hold |
|---|---|
| `AuthService.getUserProfile()` | returns `null` on error — never throws |
| `AuthService.updateProfileFields()` | `debugPrint` + `rethrow` |
| `NetworkService.getAcceptedCount()` | same count, both sides of the relationship |
| `RatingsService.getRatingSummary()` | 1-dp average; `(0, 0)` when unrated |
| `ProfileViewService.getCount()` | exact head count, no rows pulled |
| `calculateProfileCompletion()` | identical percentage for an identical row |
| `ProfileStatsRow._StatTile.formatCount()` | `2.3K` / `1.2M` thresholds unchanged |
| `AuthProvider.profileRow` | unmodifiable view |
| `profileSlug()` / `profilePath()` | identical strings — a drift produces 404s |

If a method needs different behaviour, **add a new one**. Never edit in place.

## R7 · Prefer creating new files over editing existing ones

Decision order:
1. New file — always preferred.
2. Append to an existing file — acceptable when the new member genuinely belongs with its siblings
   (a query beside its sibling queries) and the file has no unrelated dependents.
3. Edit existing code — only the five A-items in R5, only with written approval.

The bias exists because a new file cannot regress anything: nothing imports it until you say so.

## R8 · If an existing file must be edited, explain why before editing it

Before the edit, state in the chat:

1. **File** and the precise change.
2. **Why it cannot be a new file** — the alternative and why it is worse.
3. **What else reads this file** — every dependent screen/provider/test.
4. **Risk level** and the specific regression it could cause.
5. **Rollback** — the exact hunk to revert, with the pre-edit content captured verbatim.

Then wait. For the five A-items, that explanation is already written in `IMPACT_ANALYSIS.md`; the
approval is still required.

## R9 · Run `flutter analyze` after every phase

```
flutter analyze
```

Gate: **no new issues versus the recorded baseline** — measured 2026-08-05 as
**447 issues (0 errors, 0 warnings, all `info`)**, saved to
`docs/impact-reports/baseline-analyze.txt`. Those pre-existing `withOpacity` deprecations and lint
infos are not this migration's to fix; fixing them would be an unrequested change to existing code
(R5).

A new issue is a blocker, not a note. Fix it inside the phase or roll the phase back.

## R10 · Ensure the project builds after every phase

```
flutter test                    # no NEW failures vs. baseline: 540 pass / 1 fail
flutter build apk --debug       # must complete
```

`flutter test` is the real regression harness — the 13 listing-parity tests,
`post_property_metadata_roundtrip_test`, `search_bar_parity_test`, the four
Network/Social/Billing tests and `widget_test` (which carries the second provider tree).

**Baseline is 540 passing / 1 failing**, not a clean sweep. The single failure —
`phase8_social_test.dart` → "windows are relative to now" — is a pre-existing time-bomb
(`createdAt` hardcoded to `2026-08-03`, asserted against `DateTime.now()` windows) and is
diagnosed in the Regression Protection Checklist §0. Do not fix it without approval; do not let it
mask a real regression either — the count must stay exactly 540/1.

A phase that introduces a *new* failure is not complete, even if the new feature works.

## R11 · Generate an Impact Report after every phase

`docs/impact-reports/PHASE_N_IMPACT_REPORT.md`, using the §E template in `IMPACT_ANALYSIS.md`.
It must include the verbatim pre-edit content of every existing-file hunk, because — given the
uncommitted working tree — that report **is** the rollback mechanism.

## R12 · Stop and wait for approval after every phase

No phase begins because the previous one succeeded. Report, then stop:

- what shipped
- verification results
- regression checklist results
- deviations
- what the next phase needs decided

---

## R13 · Rollback must never use git *(added from repository analysis)*

The working tree carries **69 modified, 4 deleted and 103 untracked paths, none committed** (HEAD
`ca41a46`). Therefore:

```
❌ git checkout .     ❌ git reset --hard     ❌ git stash     ❌ git clean -fd
```

Each would destroy weeks of uncommitted work. **Every rollback is file-level:** delete the phase's
new files, revert its recorded hunks.

This also means **no phase may delete an existing file** until a safety commit exists — which is why
P8-5 (the three dead `*_profile_screen.dart` files) is gated on it.

Recommended, and your call to run:
```
git add -A && git commit -m "checkpoint: pre-User-Profile-migration working state"
```

## R14 · No new dependencies

`pubspec.yaml` and `pubspec.lock` are untouchable. Everything in the spec is built from packages
already declared: `image_picker`, `share_plus`, `cached_network_image`, `shimmer`, `flutter_animate`,
`photo_view`, `url_launcher`, `shared_preferences`, `supabase_flutter`, `google_fonts`, `provider`.

This is why Phase 4 ships without a crop UI: `image_cropper` would breach this rule and needs native
config besides. If a feature truly needs a package, stop and report.

## R15 · No design-token changes

`app_colors.dart`, `app_text_styles.dart`, `app_theme.dart` are read-only for this migration.
`app_constants.dart` may gain constants; no existing value may change.

`AppTheme.inputDecorationTheme` is specifically off-limits — it sets `filled: true` plus a 2 dp
`#5B50E8` `enabledBorder`/`focusedBorder` at r14, and every form in the app inherits it.
`search_bar_parity_test.dart` guards it and will fail if it is touched.

Any borderless `TextField` must null **all six** border slots *and* set `filled: false` — the
recipe in `search_bar_widget.dart`. `border: InputBorder.none` alone does not work, because Flutter
resolves `enabledBorder`/`focusedBorder` first whenever the field is enabled or focused.

## R16 · Platform config is out of scope

`AndroidManifest.xml`, `Info.plist`, Gradle files, entitlements: untouched. Both existing deep-link
intent-filters stay exactly as they are.

This bounds the spec's `/profile/{role}/{slug}/{userId}` web-link entry: the app has no such handler
today, adding one is a manifest change, so it is **reported, not implemented**.

## R17 · Never fabricate data

If a column does not exist or is not readable, the UI does not show that information.

- No hardcoded "Quick Response", "Best Deals", "Client Focused" — the portal's tiles have no data
  behind them and are dropped.
- No response-time badges, online/last-seen indicators, mutual-connection counts, or endorsements.
- No placeholder `@handle` when `username` is empty — the row is omitted.
- A failed query renders `—`, never `0`. A zero is a claim; an em dash is an absence.
- Loading renders a shimmer, never `0`.

## R18 · Reproduce the portal's data contracts exactly

Where behaviour is already established server-side or by the portal, copy it — do not improve it.

- The public-profile column list is the portal's **verbatim**. Requesting
  `phone`/`email`/`mobile_number` while anonymous **errors** under the current grant.
- `social_media` writes merge existing keys first.
- Paired columns are written together.
- Dropdown values are copied from `EditProfile.tsx` — never invented (`CLAUDE.md`).
- `builder_networks` writes **upsert** on `(builder_id, member_id)`, recipient as `builder_id`.
- `user_type`, `user_role`, `is_blocked`, `approval_status` are omitted from owner update payloads —
  the DB trigger reverts them silently, so sending them produces a fake success.

## R19 · Entry-point wiring adds navigation and nothing else

Every existing screen that gains a Public Profile navigation must preserve **all** existing
gestures, Hero animations, navigation arguments and business logic. The only new behaviour is
opening `PublicProfileScreen` when the user taps the appropriate profile target. No other UX change.

Consequences, in order of how easily they are broken:

1. **Never re-point an existing gesture.** If the element is already inside a tap target — a
   list row that opens a thread, a card that opens a property — then making the avatar open a
   profile *changes what that tap does today*. That is a UX change, not an addition, and it
   requires separate explicit approval. Prefer targets that are currently **inert**.
2. **Never add a new tap target that did not exist.** If a screen shows no avatar and no name,
   there is nothing to tap; adding one is new UI, which R19 forbids. Report it instead.
3. **Never nest a gesture inside an existing one** to "keep both". The inner detector wins for
   that region, silently removing the outer behaviour there.
4. **Hero tags must be unique on screen.** Two widgets sharing a tag makes Flutter throw
   *"There are multiple heroes that share the same tag"*. Only attach an avatar Hero where the
   source is unique in the visible tree — a detail header, not a list where one user can appear
   on several rows. When in doubt, pass no tag: the push then simply has no flight.
5. **Never change an existing route's arguments.** Add an optional parameter with a null default
   so every existing caller compiles and behaves identically; pass the new value only from the
   call sites being wired.
6. **Verify the id actually identifies the person shown.** A denormalised display column is not
   a foreign key. Navigating from a name to an unrelated id opens the wrong profile — worse
   than no navigation at all.

One host screen per approval, each with its own R8 justification and its own Impact Report.

---

## Pre-flight checklist — per phase

Before starting:
- [ ] Previous phase approved in writing
- [ ] Baseline captured (`flutter analyze`, `flutter test`, `git status --short`)
- [ ] This phase's Impact Analysis section re-read
- [ ] Every existing-file edit named, justified (R8), and approved
- [ ] Every open decision for this phase answered

Before reporting complete:
- [ ] Only declared files changed (`git status --short`)
- [ ] `flutter analyze` — no new issues
- [ ] `flutter test` — all pass
- [ ] `flutter build apk --debug` — passes
- [ ] Regression checklist §16 + the phase's §18 scope walked
- [ ] Impact Report written, with pre-edit content for every hunk
- [ ] No `supabase/`, `pubspec`, manifest or theme-token change
- [ ] Provider trees in sync
- [ ] **Stop. Await approval.**
