# PropCid Flutter App — Performance Optimization Implementation Plan

**Status: PLAN ONLY — revised after a safety review. No application source code, tests,
dependencies, configuration, assets, or lockfiles were modified to produce this revision.**
Baseline captured: 2026-10-03, branch `fix/artical-LRC-removed` @ commit `f194958`.
Revised: 2026-10-03, following a mandatory safety review of the original draft.

This plan is the output of: (1) direct, read-only baseline inspection of the repository, and
(2) twelve independent, read-only investigation passes, one per suspected problem area. It has
since been revised to correct several places where the original draft overstated what static
code inspection can prove, proposed changes that could alter functionality (result limits,
realtime timing, splash timing), or batched too much unverified change into an "initial" path.
See **"Safety Review Changes"** immediately below for exactly what changed and why. Nothing in
this document should be implemented without a separate, explicit human go-ahead per item, per
the Implementation Safety Process referenced throughout.

---

## Safety Review Changes

This section records what the mandatory safety review changed relative to the original draft,
so the revision history is explicit rather than silently absorbed into the prose below.

**Removed entirely:**
- The recommendation to add `.limit(...)` to `PropertyProvider`'s or `ReelsProvider`'s initial
  global queries (was Module 1, item b). A new limit can drop records, change Home rankings,
  hide liked/saved properties, or alter downstream lists — a functionality change, not a pure
  performance change. **This is now marked prohibited** (see Module 1).
- The claim that the full-screen Reels player uses `VideoViewType.platformView` while the Home
  rail uses `textureView`. **This was factually wrong.** Re-reading the source directly
  (`reels_screen.dart:79`, `reel_controller_manager.dart:28`) shows **both surfaces currently
  use `VideoViewType.textureView`** — see the corrected Module 6 for full evidence and the
  comment/code discrepancy this reveals.

**Reclassified:**
- Every static-analysis finding that was previously labeled a "confirmed bottleneck" is now
  labeled a **"confirmed code-level performance candidate."** Static code inspection can
  confirm a pattern exists (e.g., a broad `context.watch`, an unbounded query, a missing decode
  cap); it cannot prove that pattern is a measurable bottleneck in frame time, startup time,
  memory, or jank. No claim in this document states or implies a change *will* improve a
  measured metric unless a before/after measurement is cited — none exist yet anywhere in this
  plan, since no physical device was available during investigation.
- The fixed 3-second splash delay is reclassified from "deliberate UX, not a bug" (an
  unevidenced conclusion) to **an explicit product decision point requiring separate approval
  if changed** — see Module 1's revised "must not change" section for the two documented
  options.
- The absence of `proguard-rules.pro` is reclassified from implying "guaranteed release-only
  breakage" to a **high-risk unknown requiring release-artifact testing** — dependencies may
  ship their own consumer ProGuard rules that Gradle merges automatically, so the absence of an
  app-level file does not by itself prove R8 will break anything. See Module 12.
- The 10 baseline test failures are reclassified out of a single "all root-caused" bucket into
  four explicit categories (see §2) — three `auth_screen_test.dart` failures were never
  investigated to file:line depth by any of the twelve agents and must not be described as
  root-caused.

**Deferred out of the initial performance path** (left fully documented in their modules below,
but explicitly not scheduled, pending separate approval and in most cases pending profiling
evidence that they matter):
- The ~476-call-site `debugPrint`/`print` logging sweep (Module 1, Module 12).
- Deletion of the two confirmed-dead files `scroll_reveal.dart`/`premium_banner_section.dart`
  (Module 4).
- Broad bundled-asset re-encoding (Module 12).
- Migrating all 20 raw `Image.network()` call sites to `CachedNetworkImage` in one batch
  (Module 2) — narrowed to a single targeted experiment instead.
- `NotificationProvider`'s realtime-subscription deferral by one frame (Module 1) — removed
  from any recommended batch; see below for what proving it safe would actually require.
- All of Module 12's minification/`proguard-rules.pro` authorship work — deferred in full
  until a physical-device release smoke test and a staged/internal distribution channel are
  available; this plan does not propose authoring speculative keep rules.

**Now requires physical-device evidence before any claim of improvement, and in most cases
before implementation at all:**
- Every module's "why it should help" framing (reworded throughout to "hypothesis, pending
  measurement").
- Module 0 is no longer a documentation-only step — it now requires an actual baseline
  performance capture on physical Android hardware (low-end, mid-range, and preferably an
  affected Vivo/MediaTek device) before any other module may proceed to implementation. If no
  device is available, the plan explicitly pauses after test characterization and documentation
  — see the revised Module 0.
- Module 2's narrowed first experiment requires before/after memory and scrolling measurement
  and a visual comparison, with an explicit stop condition if improvement is not measurable or
  image quality visibly changes.

**Must never be implemented without separate, explicit approval beyond this plan:**
- Any change to realtime subscription timing anywhere (notifications, chat, messaging) —
  requires the full ordering/catch-up/dedup/test package described in Module 1, or the current
  timing is preserved exactly.
- Any splash-timing change — requires a separate, explicitly approved UX decision; this plan
  does not authorize changing it as a "performance refactor."
- Any result/pagination limit change anywhere in the app — prohibited outright unless a future,
  separately-proposed architecture can prove exact data and ordering parity and separately
  preserve all liked/saved/activity data; not proposed by this plan.
- Module 12's minification (`isMinifyEnabled`/`isShrinkResources`) — gated on a physical-device
  release smoke test and staged/internal distribution, both currently unavailable.
- Any Reels renderer, Impeller, controller-window, preload-policy, or controller-lifecycle
  change — the `textureView`/comment discrepancy found during this review is reported, not
  fixed, and is explicitly out of scope for this plan to resolve.

---

## 1. Executive summary

The app has already received **one prior, well-executed performance pass** (Home screen —
`test/home_scroll_performance_test.dart`), and that work holds up: all three of its claimed
fixes (scroll-triggered re-animation removal, reels-rail timer-leak fix, keep-alive on
data-backed sections) were independently re-verified against the current code in this
investigation and found genuinely, consistently in place.

The single most-confirmed, lowest-risk **code-level candidate** — independently rediscovered
by six of the twelve investigation passes (Provider rebuilds, Home, Search/Map, Feed,
Messaging, Forms) — is an **over-broad Provider watch pattern**: widgets calling
`context.watch<X>()`/`Consumer<X>` on an entire provider when they only need one field or one
list item's state. The team has already proven a fix for this once, for `CompareProvider` in
the Home rails — this plan proposes extending that same, already-idiomatic `Selector`/
`context.select` pattern to other sites, but **whether this measurably reduces jank/frame time
has not been measured** and must be before any claim of improvement is made.

A second theme is **startup cost**: cold start fires several unbounded, concurrent Supabase
queries from eagerly-constructed providers. The original draft of this plan proposed adding
query limits to reduce this cost — **that proposal has been removed** (see Safety Review
Changes) because a new limit can silently drop records, change rankings, or hide liked/saved
data. The safe version of this idea is making the relevant providers *lazy* (load on first real
use instead of at construction), which changes *when* a query runs, not *what* it returns or
*how much* it returns — but even that requires a full consumer audit before touching anything
(see Module 1).

A third theme is **Android release-build hygiene**: R8 minification and resource shrinking are
currently both off, and no `proguard-rules.pro` exists. The original draft treated this as
near-certain to break the app if enabled naively; the safety review corrected this to a
**high-risk unknown** — dependencies may already ship consumer ProGuard rules Gradle merges
automatically — and the whole area is deferred until a physical-device release smoke test and a
staged distribution channel exist.

A smaller, now-narrowed image-caching gap exists: the `memCacheWidth`/`memCacheHeight`
downscaling pattern used on Home was never extended to other fixed-size thumbnail/avatar
surfaces. The original draft proposed migrating all 20 raw-`Image.network()` sites and several
screens' worth of cards in one pass; this has been narrowed to a single targeted, fully-tested
experiment on one fixed-size, non-Hero surface, with explicit stop conditions.

**During this safety review, re-reading the Reels source directly found that the original
draft's claim about the full-screen player using a different, device-safer video rendering mode
than the Home rail was wrong** — both currently use `VideoViewType.textureView`. The code
contains a doc comment describing the benefits of a different mode (`platformView`) that is not
actually in effect for the value passed. This discrepancy is reported as a fact finding; this
plan does not propose touching the renderer, and resolving the discrepancy (is this a
regression, or was the comment never accurate?) is a separate investigation, not a performance
task.

**Three things were explicitly investigated and found to be fine, worth stating up front so
they are not "fixed" unnecessarily:** the Reels controller lifecycle/window itself (bounded,
leak-free, race-guarded — independent of the viewType discrepancy above); the sliver/keep-alive
architecture on Home; and the realtime-subscription disposal discipline across
messaging/notifications — all already correct.

**Baseline health is good enough to build on:** 0 analyzer errors, 2021/2031 tests passing. The
10 failures are now categorized by confidence level (§2) rather than uniformly declared
root-caused, since 3 of them were never investigated to file:line depth. No physical Android
device or emulator is available in the current tool environment, so **no before/after
performance numbers exist anywhere in this document**, and per the safety review, implementation
of anything beyond test characterization must pause until such a device is available.

---

## 2. Baseline status

| Check | Result |
|---|---|
| Git | Clean working tree, branch `fix/artical-LRC-removed`, HEAD `f194958` |
| Flutter / Dart | 3.44.9 (stable) / 3.12.2 / DevTools 2.57.0 |
| Feature flags | 4 confirmed wired in `LaunchFeatures`: `FEATURE_SUBSCRIPTIONS`, `FEATURE_PAID_COLLABORATIONS`, `FEATURE_META_PUBLISHING`, `FEATURE_VOICE_ASSISTANT`. `config/features/play_release.json` (production) = all `false`. `config/features/full_development.json` = all `true`. Production app ships **11** root providers, not 12 — `VoiceAgentProvider` and all voice-agent tool registration are compiled out when the flag is false. |
| Impeller | Confirmed disabled (`AndroidManifest.xml:21-25`, `EnableImpeller=false`, documented Vivo/MediaTek video-corruption workaround). **Not in scope to change, anywhere in this plan.** |
| Android release build | `isMinifyEnabled = false`, `isShrinkResources = false` (`android/app/build.gradle.kts:92-95`). No app-level `proguard-rules.pro` exists — **this is a high-risk unknown, not proof of certain breakage** (see Module 12). No CI/release pipeline exists (`.github/workflows/`, fastlane, release scripts all absent) — release builds are manual. |
| `flutter analyze` | **572 issues, 0 errors** (569 info, 3 warnings — all `unused_import`: `lib/core/navigation/manage_dashboard_dispatcher.dart:11`, `lib/core/navigation/post_property_route_gate.dart:49`, `lib/screens/social/social_hub_screen.dart:4`). Ran a `pub get` resolve as a side effect; verified `pubspec.lock` was **not** modified. |
| `flutter test` | **2021 passed, 10 failed**, full suite, ~4m36s. "Pre-existing" below means *present on this commit, before any performance implementation begins* — it does **not** mean every one of these was documented in an older recorded baseline; several were discovered fresh during this investigation. |

**Failing-test categorization (per the safety review's required categories — not all 10 are
equally well understood):**

| Category | Tests | Evidence basis |
|---|---|---|
| **Fully root-caused existing failures** (file:line evidence obtained by reading and, where applicable, running the actual code this session) | `notification_centre_test.dart` (4 of 4); `people_search_test.dart` (1 of 1) | See rows below for the specific cause of each. |
| **Genuine product/UI regression** (a real behavior drop, not a test-maintenance issue) | `notification_centre_test.dart` — 3 of its 4 failures | A "N new" unread-count pill was dropped from `NotificationsScreen`'s `_AppBar` during a real-data rewrite; the provider-side unread count is correct and separately tested, but the screen no longer renders it as visible text. |
| **Stale test assumptions** (the product code changed for an unrelated, legitimate reason and the test was never updated) | `notification_centre_test.dart` — 1 of its 4 failures (tolerates a now-absent `BottomNavBar` overflow at 130% text scale; the test's own comment says to delete the tolerance block once this happens); `people_search_test.dart` — 1 of 1 (taps "See all people" without scrolling it into view; a `_buildListingTypeToggle()` section added to `search_screen.dart` after this test was last touched pushed the row below the default test viewport) | Confirmed by running the test and reading both the test file and the current product code; git history confirms the UI addition postdates the test. |
| **Suspected cause requiring separate investigation** (correlated but not verified to file:line depth by any of the twelve investigation passes) | `auth_screen_test.dart` (3 of 3); `reel_share_link_test.dart` (2 of 2) | `auth_screen_test.dart`'s three failures are new relative to earlier session notes and plausibly correlate with the Voice Assistant feature work merged the same day per `CHANGELOG.md`, but **no agent in this investigation read the current `AuthScreen` code against the test's assertions** — this is a hypothesis, not a finding. `reel_share_link_test.dart`'s two failures match a previously recorded issue label from an earlier session, but were not independently re-verified against the current code in this round of investigation. |

None of the above are to be fixed as part of this performance project — per the task's own
instruction, a performance module must never silently "fix" an unrelated existing failure. They
are recorded here as the pre-existing baseline so that after any future module's test run, new
failures can be distinguished from these.

**Profiling feasibility — this is now a hard gate, not a note:** `flutter devices` shows only
`Windows (desktop)`, `Chrome (web)`, `Edge (web)`. Android SDK/toolchain is installed and
licensed (`flutter doctor` green), but **no emulator or physical Android device is currently
attached**, so `flutter run --profile --dart-define-from-file=config/features/play_release.json`
cannot be executed in this tool environment right now. Per the safety review, **this means
implementation of any module beyond Module 0's test-characterization work must pause until a
physical low-end device, a representative mid-range device, and preferably an affected
Vivo/MediaTek device become available.** No performance-measurement field in this document
contains a number — every one explicitly says "not yet measured."

**Existing performance-specific test coverage:** exactly one file,
`test/home_scroll_performance_test.dart`. 116 total `*_test.dart` files exist.

---

## 3. Top confirmed code-level performance candidates (ranked; impact not yet measured)

Static code inspection can confirm a pattern exists. It cannot prove that pattern is a
measurable bottleneck. Every item below is a **candidate for profiling**, not a proven win.

1. **Over-broad Provider watches** causing unrelated-state rebuilds — the pattern is confirmed independently in 6 of 12 areas. Worst single site by code volume: `PostPropertyProvider` (~90 unconditional `notifyListeners()` call sites, watched broadly by the wizard shell **and** all 9 step widgets). Whether this is user-perceptible jank has not been measured.
2. **Eager, concurrent Supabase queries at cold start** from 3–4 providers regardless of which screen the user lands on. Whether this meaningfully delays first-useful-screen time has not been measured. **Reducing the amount of data fetched is prohibited** (see Safety Review Changes) — any fix here can only change *when* a query runs, not *what* it returns.
3. **No `proguard-rules.pro`** — a high-risk unknown for any future minification, not a current runtime cost (minification is currently off). Deferred in full (Module 12).
4. **Image decode-size gaps** on Search/Chat/Compare/People-Search surfaces (pattern already proven safe on Home, just not extended). Narrowed to a single targeted experiment (Module 2) rather than a broad migration.
5. **~476 unguarded `debugPrint` + 10 raw `print()` calls** — deferred out of the initial path; a narrow release-log guard may be proposed later only where profiling shows repeated hot-path logging (see Module 12).
6. **A doc-comment/code discrepancy in the Reels renderer**: `reels_screen.dart`'s own comment describes `platformView`'s device-safety benefits, but the value actually passed is `VideoViewType.textureView` — the same value the Home rail uses by default. This is a fact finding for separate investigation, not a performance task, and this plan does not propose changing it.
7. Map marker/circle full rebuild on every unrelated `PropertyProvider` notification (Search) — candidate, not measured.
8. Sequential multi-file uploads with no progress UI on the highest-traffic upload path (property photos) — a UX/observability candidate, not confirmed as a throughput bottleneck.
9. Three of the ten baseline test issues are genuine product/test-maintenance items unrelated to performance (§2) — recommended as separate tickets, not performance work.
10. Two confirmed-dead files and some oversized bundled assets — deferred cleanup/app-size items (see Safety Review Changes), not scheduled as part of the initial performance path.

---

## 4. Risk matrix

| Risk level | Meaning here | Examples from this plan |
|---|---|---|
| **Low** | Pure internal refactor, same output/contract, existing idiomatic pattern to copy, easy to verify, no claim of measured improvement made | Guard `RoleHomeRouter` debugPrint (M1, if revisited later); `ValueKey` on chat bubbles (M8); per-row Selector reuse of the proven Compare pattern (M3, M5) |
| **Medium** | Touches a widely-used provider/widget across several call sites, or changes rebuild/load timing in a way that needs new tests since none exist today | `FilterProvider`/`PropertyProvider` screen-level Selector narrowing (M3, M5); the single targeted image-decode experiment (M2); one lazy-provider conversion, post-audit (M1) |
| **High — requires physical-device profiling evidence and/or explicit backend/product sign-off before implementation** | Touches a subsystem with documented device-specific history, or requires authoring new security-sensitive config from scratch | Any Reels controller-window/ordering/view-type change (M6 — not proposed by this plan); Module 12's minification work in full |
| **Prohibited (not to be implemented by this plan under any circumstance)** | Would or could change functionality, data, or ordering | Any result/pagination limit reduction anywhere; any realtime-subscription-timing change without the full ordering/catch-up/dedup/test package in Module 1; any automatic splash-timing change |
| **Blocked (needs a product/backend decision this plan cannot make)** | — | DB-native `price_min` server-side budget filtering (M5, explicitly backend); batching `get-chat-media-url` (M8, needs backend contract change); cross-navigation profile cache (M9, conflicts with a documented anti-stale-bleed design choice) |

---

## 5. Module dependency / order table

This table describes the full, documented module set for reference. **It is not the
implementation schedule.** The actual, much narrower, revised first batch is in §12 at the end
of this document — do not treat the ordering below as authorization to proceed through Modules
1–12 sequentially.

| # | Module | Depends on | Why |
|---|---|---|---|
| 0 | Baseline, regression protection, measurement | — | Hard prerequisite for everything; now includes physical-device capture, not just documentation |
| 1 | App shell / startup | 0 | Lazy-provider work requires a full consumer audit first; query limits removed entirely; realtime-deferral removed from any near-term plan |
| 2 | Images / assets | 0 | Narrowed to one targeted, fully-tested experiment |
| 3 | Provider rebuild architecture (cross-app pattern + 2 reference conversions) | 0 | Establishes the pattern Modules 4, 5, 7, 8, 10 would build on, if and when pursued |
| 4 | Home | 0, 3 | Dead-code deletion deferred; rail-sort narrowing depends on Module 3's pattern |
| 5 | Search / Map | 0, 3 | — |
| 6 | Reels | 0 | Lifecycle-observer addition only; the viewType discrepancy is reported, not actioned, by this plan |
| 7 | Feed | 0, 3 | — |
| 8 | Messaging / notifications | 0, 3 | — |
| 9 | Profiles / detail screens | 0 | — |
| 10 | Forms (post-property wizard, article editor) | 0, 3 | Highest-effort Selector application; sequenced last among Selector-pattern modules |
| 11 | Media / uploads | 0 | — |
| 12 | Android release optimization | 0 | Minification work fully deferred pending a release smoke-test capability that does not currently exist |

---

## 6. Module plans

Each module below uses the 17 required points. Wherever the original draft claimed a change
"should help" a specific metric, that language has been replaced with "hypothesis, pending
physical-device measurement" per the safety review. "Performance measurements before/after" is
marked **"Not yet measured — requires the Module 0 physical-device baseline first."** throughout.

---

### Module 0 — Baseline, regression protection, measurement

1. **Current implementation:** No dedicated performance-measurement tooling beyond one test file (`test/home_scroll_performance_test.dart`). No CI. No profiling harness. No physical-device baseline has been captured — only static code inspection and a desktop-only `flutter analyze`/`flutter test` run exist as of this plan.
2. **Exact files/classes involved:** N/A — this module is process and measurement, not application code.
3. **Evidence of the problem:** See §2 — a desktop/static baseline exists; a physical-device performance baseline does not. Without one, no module past this one may claim a measured improvement.
4. **Behavior that must remain unchanged:** N/A — this module makes no application changes.
5. **Proposed work (revised — this is no longer documentation-only):**
   - (a) Write/confirm characterization tests for every behavior any later module might touch (see each module's "existing tests"/"missing tests" fields) — before any later module's implementation.
   - (b) Finalize and publish the exact failing-test baseline using the four-category table in §2, so future runs can be diffed against it precisely.
   - (c) Obtain access to: a low-end Android device, a representative mid-range Android device, and preferably one affected Vivo/MediaTek device. Run the app via `flutter run --profile --dart-define-from-file=config/features/play_release.json` on each.
   - (d) On each available device, capture: cold-start time; first-useful-screen time; UI/raster frame times; janky-frame percentage; rebuild counts for a fixed set of scenarios (Home scroll, Search scroll + one like, Reels scroll + backgrounding, one Post-Property field edit); Search/Chat image-memory behavior during a long scroll; Reels controller count and memory behavior during fast scroll and app backgrounding; the count and timing of network requests fired during the first 2 seconds after cold start.
   - (e) **If no device is available:** stop after (a) and (b). Document the gap explicitly (this document already does, in §2). Do not proceed to implement any module whose "why it should help" field depends on an unmeasured claim, and do not describe any later change as a "verified optimization" — at most, as an implemented-but-unverified code change pending measurement.
6. **Why this is necessary (not "why it should help" — this module produces no performance change itself):** Every other module in this document proposes a change whose actual performance effect is currently unknown. Without this baseline, the project cannot distinguish a real improvement from a null result or a regression.
7. **Exact files expected to change:** New test files only (characterization tests per module, written against the *current*, unmodified behavior); a new `docs/ai-memory/PERF_BASELINE.md` or equivalent capturing the device-measurement results once available. No application source code changes.
8. **Existing tests protecting behavior:** The existing 116-file suite, used as the first layer of regression protection for every later module.
9. **Missing tests needed before implementation:** Characterization tests are themselves the deliverable of this module — see each later module's "Missing tests needed before implementation" field for the specific list.
10. **Performance measurements before/after:** This module produces the "before" — there is no "after" until a later module is actually implemented and re-measured.
11. **Risk level:** Low (no application code changes; pure measurement and test-writing).
12. **Potential regression scenarios:** None from this module itself.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** N/A — no application change to roll back.
15. **Stop conditions:** As stated in point 5(e) — no device available means implementation of any later module pauses here.
16. **Definition of done:** Characterization tests exist for every behavior the first revised batch (§12) will touch; the failing-test baseline is published in the four-category form; either a physical-device performance baseline has been captured, or the plan explicitly records that it has not and implementation is paused pending device access.
17. **Recommended commit boundaries:** One commit per characterization-test file; one docs commit for the baseline capture (or for the explicit pause record, if no device is available).

---

### Module 1 — App shell / startup

1. **Current implementation:** `main.dart` does `WidgetsFlutterBinding.ensureInitialized()` → `await dotenv.load()` → `await Supabase.initialize()` → `runApp(MultiProvider(...))`. The `MultiProvider` constructs 11 providers (production) synchronously; four of them (`PropertyProvider`, `ReelsProvider`, `ProjectsProvider`, `AvailableLocationsProvider`) fire unawaited Supabase queries directly from their constructors. Firebase init and the deep-link handler are already correctly started via `unawaited(...)` *after* `runApp()`. `NotificationProvider`'s realtime-channel subscribe fires synchronously inside the first `ProxyProvider.update` call.
2. **Exact files/classes/methods:** `lib/main.dart:40-110`; `lib/providers/property_provider.dart:98-103`; `lib/providers/reels_provider.dart:121-126`; `lib/providers/projects_provider.dart:27-30`; `lib/providers/available_locations_provider.dart:17-19`; `lib/screens/role_home_router.dart:13-14` (unguarded `debugPrint`); `lib/providers/notification_provider.dart:86`; `lib/screens/splash/splash_screen.dart` (fixed 3-second delay, see point 4).
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by direct code read that these four providers fetch at construction time, unconditionally, regardless of which screen the user opens. Whether this is a user-perceptible cold-start cost has not been measured on any device.
4. **Behavior that must remain unchanged, and two items requiring separate approval before any change:**
   - `AuthProvider` remains the sole decider of post-auth navigation; the onboarding-must-show-first rule; `InviteDeepLinkHandler` must keep running post-`runApp`, checking the cold-start initial link before subscribing live, using the same `AuthProvider` instance from `main()`; `LaunchFeatures.*` must keep `defaultValue: false`; provider registration order must be preserved; `test/widget_test.dart`'s hand-duplicated provider list must be kept in sync with any change to `main.dart`'s `MultiProvider`.
   - **Splash-screen timing — reclassified as an explicit product decision, not a confirmed non-issue.** The original draft asserted the fixed 3-second branded delay was "deliberate UX, not a bug" without evidence. This plan now documents two possibilities without choosing between them: **(i)** preserve the 3-second delay exactly, unconditionally, as today; or **(ii)**, *only as a separately approved UX change outside this performance plan*, move to readiness-gated navigation — a small minimum branding duration plus a maximum fallback timeout — while preserving every existing authentication/onboarding decision point exactly. **This plan does not authorize choosing or implementing either option; it must not be changed as a "performance refactor."**
   - **Realtime-subscription timing — must not be changed without the full safety package below.** The original draft proposed deferring `NotificationProvider`'s subscribe call by one frame via `addPostFrameCallback`. **This is removed from any recommended batch.** A one-frame delay still changes realtime behavior and could miss an event delivered in that window. If this is proposed again in the future, it requires, together, not separately: (1) the initial state load happening first; (2) subscription establishment immediately after; (3) a catch-up/reconciliation read covering the window between (1) and (2); (4) deduplication between the catch-up read and the live subscription; (5) a test that injects an event during initialization and asserts it is neither missed nor double-counted. Absent all five, **the current subscription timing is preserved exactly.**
5. **Proposed optimization (revised — query-limit item removed; lazy-loading item fully gated):**
   - **(a) [PROHIBITED — do not implement]** Adding `.limit(...)` to `PropertyProvider.getProperties()` or `ReelsProvider.getReels()`'s initial fetch. A new limit can drop records entirely, change which properties appear in "New Listings"/Home rankings, hide a property a user has liked/saved/interacted with from lists that currently include it regardless of recency, or otherwise change downstream list membership and ordering. This is a functionality change, not a performance-neutral one, and is explicitly out of scope for this plan. It may only be reconsidered in the future if a separate, dedicated proposal can demonstrate exact data and ordering parity with the current unbounded fetch, and separately and explicitly prove that all liked/saved/activity-relevant data remains reachable regardless of the limit (e.g., via a guaranteed separate fetch path for a user's own liked/saved items) — no such proposal exists today.
   - **(b) [Gated — one provider at a time, post-audit only]** Make eagerly-loading providers lazy (load on first real use instead of at construction) — this changes *when* a query runs, never *what* it returns, so it does not carry the same risk as (a). Before touching **any** provider: produce a complete consumer/call-site matrix listing every screen, badge, rail, router, deep link, and action that reads that provider, confirming none of them assume data is already populated without the user having triggered a load. Any lazy-provider conversion must include, as one unit of work: an idempotent `ensureLoaded()` method; deduplication of concurrent calls to it (e.g., two widgets triggering a load in the same frame must not fire two network requests); explicit loading/error/retry state exposed to callers; `ensureLoaded()` invoked at every valid entry point identified by the consumer audit, including deep-link entry points; safety against calling into a disposed provider on navigation-away; proof that resulting data, ordering, likes, saves, counts, and error behavior are identical to the eager implementation; a rollback switch or a single, easily revertible commit; and characterization tests written against the *current eager implementation first*, before any conversion, so a regression is caught by a test that already existed before the change. **Implement only one provider at a time.** `AvailableLocationsProvider` may be considered first since its usage appears narrower (only the city picker on Search screens), but only after the consumer audit above confirms that assumption — it is not pre-approved. **Do not combine this work with (a) query limits under any circumstance**, including in the same commit or the same module pass.
   - **(c) [Low risk, deferred — see Safety Review Changes]** Guard `RoleHomeRouter`'s two `debugPrint` calls behind `kDebugMode`. Folded into Module 12's logging item rather than done twice.
   - **(d) [Removed — see point 4]** `NotificationProvider` subscription deferral.
6. **Hypothesis, pending physical-device measurement (not a confirmed benefit):** Making the four providers lazy *may* reduce the number of concurrent network requests fired during the first seconds after cold start for users who do not visit Reels/Projects/a location picker. Whether this measurably improves first-useful-screen time is unknown until Module 0's device baseline exists.
7. **Exact files expected to change (for item b, once a single provider is approved post-audit):** That provider's file only, plus every call site identified by its consumer audit, plus its new tests. `lib/screens/role_home_router.dart` for item (c), bundled with Module 12.
8. **Existing tests protecting behavior:** `test/widget_test.dart` (duplicated provider tree — throws `ProviderNotFoundException` if provider identity/registration changes incorrectly); `test/providers/auth_provider_test.dart`, `test/providers/auth_navigation_test.dart`.
9. **Missing tests needed before implementation:** The full consumer-audit output itself (a document, not a test) for whichever single provider is chosen; characterization tests against that provider's current eager behavior (data, ordering, counts) before any conversion; a test proving `ensureLoaded()` is idempotent and dedupes concurrent calls; a deep-link-entry test exercising that provider's data being available when reached via a deep link rather than normal navigation.
10. **Performance measurements before/after:** Not yet measured — requires the Module 0 physical-device baseline first.
11. **Risk level:** (a) Prohibited. (b) Medium, strictly one provider at a time, post-audit only. (c) Low, deferred to Module 12.
12. **Potential regression scenarios:** For (b): a screen elsewhere silently assumes the chosen provider's data is already populated without the user ever visiting the screen that normally triggers its load (e.g., a badge or count on another screen) — this is exactly what the consumer audit exists to catch before any code changes.
13. **Feature-flag requirement:** None strictly required for (b), but a rollback switch (point 5b) is mandatory regardless.
14. **Rollback procedure:** For (b): revert the single commit converting that one provider back to eager construction.
15. **Stop conditions:** If the consumer audit for the first candidate provider finds more than a small, easily-verified number of call sites, or any ambiguity about whether a caller assumes pre-loaded data, stop and do not proceed with that provider — re-scope to a narrower provider or do not proceed with (b) at all this cycle.
16. **Definition of done:** For (b): the chosen provider's data loads identically (same values, same order) whether triggered eagerly (old) or lazily (new) in every scenario covered by its consumer audit and characterization tests; `test/widget_test.dart` and all auth-navigation tests still pass unchanged.
17. **Recommended commit boundaries:** One commit for the consumer-audit documentation (no code change). One commit for the characterization tests (no code change, must pass against current eager behavior). One commit for the single provider's lazy conversion itself, isolated from everything else.

---

### Module 2 — Images / assets

1. **Current implementation:** `cached_network_image` with `memCacheWidth`/`memCacheHeight` (decode-size capping) is used consistently, but **only** on Home-screen sections, via an explicit, deliberate, nullable opt-in parameter on `PropertyCardVertical`/`ProjectCardVertical`. Elsewhere, cards/avatars render without any decode-size cap, and 20 call sites use raw `Image.network()` instead of `CachedNetworkImage` at all.
2. **Exact files/classes/widgets/methods — full candidate list (not all in scope for the first experiment, see point 5):** `lib/screens/search/widgets/property_card_search_grid.dart:115-123`, `property_card_search_row.dart:104-112`, `people_result_card.dart:273-316` (`PeopleAvatar`), `lib/screens/messaging/widgets/chat_avatar.dart:9-54` (`ChatAvatar`), `lib/widgets/property_card_horizontal.dart:62-73`, `lib/widgets/property_card_compact.dart:79-90`, `lib/screens/feed/feed_screen.dart:417-424/672-679`. Worst single site by decode/display ratio: `lib/screens/compare/compare_properties_screen.dart:1310-1318` (`CircleAvatar(radius: 9)` — 18px — with raw `NetworkImage`, zero downscaling). Already-correct reference pattern: `lib/screens/home/widgets/{hero_banner_section,property_rail_section,featured_properties_section,trending_section,...}.dart`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed via repo-wide grep for `Image.network(` (20 hits) and absence of `memCacheWidth`/`memCacheHeight` at the listed sites, contrasted against their presence at 14 Home-section sites. No memory or jank measurement exists for any of these sites.
4. **Behavior that must remain unchanged:** Hero tags/transitions (`property_hero_${property.id}_$index` in `property_detail_screen.dart:610`, flying to `gallery_viewer_screen.dart`); every placeholder/error-widget per site; rendered layout size (`width`/`height`/`BoxFit.cover`) — only decode size may ever change, never display size; the existing opt-in nullable-parameter convention.
5. **Proposed optimization — narrowed per safety review to a single first experiment, not a batch:**
   - **In scope for the first experiment:** exactly **one** fixed-size, non-Hero thumbnail or avatar surface, chosen from the candidate list in point 2, where the required physical decode size (`display dp × device pixel ratio`) can be calculated safely and verified by screenshot. `ChatAvatar` (fixed 48dp default, used identically across 12 files) or `PeopleAvatar` (fixed 56dp) are the most structurally simple candidates and are suggested as the starting point, but the final choice should be confirmed against Module 0's consumer-audit discipline before starting.
   - **Explicitly excluded from this and any near-term batch:** full-screen images; gallery images; zoomable images; any Hero-flight source or destination image (the property-detail carousel and its gallery-viewer destination, and the profile-avatar Hero even though it is currently dead/unreachable code); export/share/QR images (e.g. `visiting_card_sheet.dart`'s existing `precacheImage` call); and any surface that cannot be manually screenshot-validated before/after.
   - **Deferred, not part of any near-term batch:** migrating the other 19 raw `Image.network()` sites; extending the opt-in pattern to `PropertyCardHorizontal`/`PropertyCardCompact`; fixing the 18px Compare avatar; bundled-asset re-encoding. All remain documented here as candidates for a future, separately-scoped pass once the first experiment's results are measured.
6. **Hypothesis, pending physical-device measurement:** Capping decode size on the one chosen surface may reduce image-memory pressure during a long scroll of that surface. This must be measured before/after on a physical device, not assumed.
7. **Exact files expected to change:** The one chosen file only (e.g., `lib/screens/messaging/widgets/chat_avatar.dart`).
8. **Existing tests protecting behavior:** None assert `memCacheWidth`/caching behavior anywhere today.
9. **Missing tests needed before implementation:** A widget test for the chosen surface asserting: the rendered **display** dimensions are unchanged; the placeholder widget renders identically; the error-widget state renders identically; the `CachedNetworkImage`/`ResizeImage` decode width/height is computed from `display dp × devicePixelRatio`, rounded **up** (never down, to avoid visible blur versus current full-res rendering).
10. **Performance measurements before/after:** Not yet measured — this experiment's explicit purpose is to produce this plan's first real before/after numbers (image-memory usage during a scroll of the chosen surface, captured via DevTools on a physical/emulated device) and a manual visual comparison.
11. **Risk level:** Low-Medium — low because it is a single, small, structurally simple, non-Hero surface; medium only because zero existing test coverage means the new tests above are the only safety net.
12. **Potential regression scenarios:** Rounding the computed decode size down instead of up would cause visible blur on high-DPI devices — the test in point 9 exists specifically to catch this before merge, but final confirmation is a manual screenshot comparison.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Single-file revert.
15. **Stop conditions (explicit, per safety review):** **Stop and do not proceed to any further image-decode work if the before/after measurement does not show a measurable improvement, or if the manual visual comparison shows any perceptible image-quality change.** A null or negative result here should pause the rest of Module 2, not be pushed through anyway.
16. **Definition of done:** The one chosen surface has a correctly DPR-aware decode cap; its new tests pass; a before/after memory measurement and a visual comparison both exist and are documented; no regression in display size, placeholder, or error-widget behavior.
17. **Recommended commit boundaries:** One commit: tests first (against current, uncapped behavior — they should pass trivially since no cap exists yet, or should be written to assert the *target* behavior and intentionally fail until the change lands, whichever the implementer prefers to make explicit), then the single-file change, measured and screenshot-compared before being considered complete.

---

### Module 3 — Provider rebuild architecture (cross-app pattern)

1. **Current implementation:** Provider package with broad `context.watch<X>()`/`Consumer<X>` used at screen- and widget-level across most of the app, even where only one field or one list-item's boolean state is actually needed. One narrow, already-proven exception exists: `CompareProvider`'s per-card `Selector<CompareProvider, bool>` in the Home rails, explicitly documented in-code as a prior fix for exactly this class of pattern.
2. **Exact files/classes/widgets/providers/methods:** Confirmed candidates, ranked by code volume: `lib/screens/post_property/post_property_screen.dart:161` + all 9 files under `lib/screens/post_property/steps/*.dart` (handled under Module 10, given its scale); `lib/screens/search/search_results_screen.dart:525-526,725`; `lib/screens/messaging/chat_thread_screen.dart:823`; `lib/screens/reels/reels_screen.dart:337` (low impact). Reference pattern to copy: `lib/screens/home/widgets/trending_section.dart:69-71`, `property_rail_section.dart:93-95`, `featured_properties_section.dart:115`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Independently confirmed by 6 of 12 investigation passes from different angles, each citing the exact watch call site and the exact unrelated `notifyListeners()` call that triggers it. No rebuild-count or frame-time measurement exists yet for any of these sites.
4. **Behavior that must remain unchanged:** The exact value/state displayed must be byte-identical before and after — only rebuild *frequency*, never resulting UI state, may change. Converting a broad watch to a too-narrow `Selector`/`select` is a **correctness regression** (stale UI), not merely a missed optimization — this is the primary hazard throughout this module.
5. **Proposed optimization:** Document the `Selector<ProviderType, T>` / `context.select<ProviderType, T>` conventions as house style, then apply to the two lowest-risk, most broadly reusable sites first: `search_results_screen.dart`'s per-row `isLiked`/`isInCompare`, and `reels_screen.dart`'s single-field reel-action watch. The `chat_thread_screen.dart` split and the full `search_results_screen.dart` screen-level narrowing are higher-effort and would follow only once the pattern is validated and measured on the low-risk sites — not scheduled in this plan's near-term batch.
6. **Hypothesis, pending physical-device measurement:** Narrowing these watches may reduce the amount of UI rebuilt per unrelated state change. Whether this is perceptible to a user has not been measured.
7. **Exact files expected to change (this module's own scope):** `lib/screens/search/search_results_screen.dart` (per-row only), `lib/screens/reels/reels_screen.dart:337`.
8. **Existing tests protecting behavior:** None assert on rebuild counts anywhere in the suite.
9. **Missing tests needed before implementation:** A widget test per converted site that explicitly drives a provider mutation and asserts the specific displayed value still updates correctly.
10. **Performance measurements before/after:** Not yet measured — requires the Module 0 physical-device baseline and a DevTools rebuild-count capture before and after.
11. **Risk level:** Low for the two reference conversions; Medium for anything touching a screen-level watch with many derived values (deferred).
12. **Potential regression scenarios:** A `Selector`'s equality check comparing by object identity instead of by value would silently stop the widget from rebuilding when it should.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-site revert.
15. **Stop conditions:** If a converted site's new widget test reveals the `Selector` ever shows stale data in manual QA, stop and revert that site immediately.
16. **Definition of done:** The two low-risk reference conversions are shipped, tested, and measured (not merely implemented) before being cited as a pattern for other modules.
17. **Recommended commit boundaries:** One commit for the `search_results_screen.dart` per-row conversion + its new test; one commit for the `reels_screen.dart` conversion + its new test.

---

### Module 4 — Home

1. **Current implementation:** A single `CustomScrollView`/`SliverList` rendering 22 sections. All three previously-claimed performance fixes were independently re-verified in this investigation and confirmed genuinely, consistently in place — no action needed on the architecture itself.
2. **Exact files/classes/widgets involved:** `lib/screens/home/home_screen.dart:61-213`; all `lib/screens/home/widgets/*.dart`. Confirmed-dead, unreferenced files: `lib/screens/home/widgets/scroll_reveal.dart`, `lib/screens/home/widgets/premium_banner_section.dart`. Candidate rebuild-scope issue: `lib/screens/home/widgets/property_rail_section.dart:55-57` and `trending_section.dart:24-42` each re-sort their list inside a `Consumer<PropertyProvider>` that rebuilds on any unrelated like/shortlist toggle.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Verified file:line for all 3 prior-fix claims; dead files confirmed unreferenced via repo-wide grep; the sort-in-Consumer finding confirmed by reading `property_provider.dart:588-617`'s unconditional `notifyListeners()`.
4. **Behavior that must remain unchanged:** The exact 22-section order pinned by `test/home_scroll_performance_test.dart`; keep-alive behavior on every section; the single `CustomScrollView`/one-`SliverList` structure; manual-only reel-rail scrolling; the fixed-header notification-badge pulse animation — a deliberate, always-on indicator, not a defect.
5. **Proposed optimization:**
   - **(a) [Deferred — see Safety Review Changes]** Deletion of the two confirmed-dead files. Zero runtime cost either way since nothing references them; this is a cleanup item, not a performance item, and is explicitly moved out of the initial performance path so it does not inflate an early performance diff. May be done as a separate, unrelated hygiene commit at any time, with no performance-plan dependency.
   - **(b) [Candidate, not scheduled in the near-term batch]** Apply Module 3's Selector pattern to `PropertyRailSection`/`TrendingSection`'s outer `Consumer<PropertyProvider>` so an unrelated like/shortlist toggle elsewhere does not force a re-sort of these two rails.
6. **Hypothesis, pending physical-device measurement:** (b) may reduce unnecessary re-sort work on unrelated actions; not measured.
7. **Exact files expected to change:** `property_rail_section.dart`, `trending_section.dart`, `home_screen.dart:124-137` (for b, if pursued later).
8. **Existing tests protecting behavior:** `test/home_scroll_performance_test.dart`, `test/home_reels_categories_test.dart`, `test/home_upgrade_test.dart`.
9. **Missing tests needed before implementation:** A test asserting that toggling a like/shortlist on a property not in the visible rail does not change that rail's rendered order or trigger its sort function, before (b) is implemented.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low, deferred. (b) Medium, deferred.
12. **Potential regression scenarios:** For (b), an incorrectly-scoped `Selector` could stop the rail from re-sorting when a genuinely relevant property changes.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Independent per-item revert.
15. **Stop conditions:** N/A — neither item is scheduled in the near-term batch.
16. **Definition of done:** Not applicable until either item is separately scheduled.
17. **Recommended commit boundaries:** If/when pursued: one commit for dead-file deletion (hygiene, separate from performance tracking); one commit per rail for (b).

---

### Module 5 — Search / Map

1. **Current implementation:** Search results render lazily (already correct). The map widget (`PropertySearchMapWidget`) rebuilds its entire `Set<Marker>`/`Set<Circle>` from scratch on every `build()`, with no memoization. `FilterProvider` is one flat `ChangeNotifier` where every setter calls `notifyListeners()` unconditionally. A compare-mode display filter re-scans the entire loaded result list inside `build()` on every unrelated rebuild.
2. **Exact files/classes/widgets/providers/methods:** `lib/widgets/property_search_map_widget.dart:64-103,180-201`; `lib/screens/search/search_results_screen.dart:525-526,579-592,677-739/744-811`; `lib/providers/filter_provider.dart:52-127`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed — no identity/signature-based memoization exists for marker construction, contrasted with the same file's `didUpdateWidget`, which does correctly gate camera-fit logic on identity.
4. **Behavior that must remain unchanged:** All documented sort rules and tiebreaks; all pagination limits (`searchPageSize=20`, `mapResultsSafetyCap=300`, `priceAwareFetchBatchSize=200`, `nearMeResultCap=100` — **do not reduce any of these, consistent with the prohibition in Module 1**); filter combination semantics; the generation-guard staleness protection; budget-filter semantics.
5. **Proposed optimization (candidates, not scheduled in the near-term batch):** (a) Memoize map markers/circles keyed on data identity/signature. (b) Apply Module 3's pattern to narrow `SearchResultsScreen`'s top-level watch. (c) Memoize the compare-mode display filter.
6. **Hypothesis, pending physical-device measurement:** May reduce rebuild/CPU cost when the map view is active during an unrelated like action; not measured.
7. **Exact files expected to change:** `lib/widgets/property_search_map_widget.dart`, `lib/screens/search/search_results_screen.dart`.
8. **Existing tests protecting behavior:** `test/providers/property_provider_search_test.dart`. No test exists for `FilterProvider`, `PropertySearchMapWidget`, or `SearchResultsScreen`'s rebuild granularity.
9. **Missing tests needed before implementation:** A widget test asserting markers/circles are not recomputed on an unrelated notification with the same data; a test for the memoized compare-filter output matching the unmemoized output.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low. (b) Medium. (c) Low. All deferred pending the near-term batch's results.
12. **Potential regression scenarios:** Using list length instead of a real content signature as a memoization key could miss a same-length content swap.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-file revert.
15. **Stop conditions:** If the new tests cannot reliably detect a memoization bug, reconsider the key before shipping.
16. **Definition of done:** Not applicable until separately scheduled.
17. **Recommended commit boundaries:** One commit each for (a), (b), (c), kept independent, if/when pursued.

---

### Module 6 — Reels

1. **Current implementation — corrected per the safety review's direct re-verification:** `ReelControllerManager` keeps a strictly bounded, windowed set of `VideoPlayerController`s alive (3 for the full-screen feed via `windowRadius: 1`; 1 for the Home rail via `windowRadius: 0`), with eviction-before-init ordering, a generation-counter race guard, and correct disposal in every path. **The original draft's claim that the full-screen player uses `VideoViewType.platformView` while the Home rail uses `textureView` is factually wrong and has been corrected:**
   - `reels_screen.dart:79` explicitly passes `viewType: VideoViewType.textureView`.
   - `reel_controller_manager.dart:28` defaults `viewType` to `VideoViewType.textureView`.
   - `property_reels_section.dart` (the Home rail) does not override `viewType` at all, so it also uses the `textureView` default.
   - **Both surfaces currently use the same value: `VideoViewType.textureView`.**
   - `reels_screen.dart:65-76` contains a doc comment describing, in detail, why the full-screen player is rendered through a native `SurfaceView` (`platformView`) rather than a Flutter texture — citing the exact Vivo/MediaTek green-tearing mechanism this was meant to avoid — but the value actually passed on the next line (`:79`) is `textureView`, not `platformView`. This is a **comment/code mismatch**, not a working differentiation between the two surfaces. The Home rail lacks AppLifecycleState pause handling on the full-screen feed specifically (separately confirmed, see point 5a) — this is unrelated to the viewType finding.
2. **Exact files/classes/methods:** `lib/screens/reels/widgets/reel_controller_manager.dart` (window logic, generation guard, disposal — all independently verified correct, unaffected by the viewType finding); `lib/screens/reels/reels_screen.dart:65-80` (the comment/code mismatch, and the missing `WidgetsBindingObserver`); `lib/screens/home/widgets/property_reels_section.dart` (the rail's own, working `WidgetsBindingObserver` pattern, and its implicit `textureView` default).
3. **Evidence of the problem:** Confirmed by directly reading the current source this session (`Grep` for `VideoViewType`/`viewType` across `lib/screens/reels/` and `lib/screens/home/widgets/property_reels_section.dart`) — not by relying on comments alone, per the safety review's explicit instruction.
4. **Behavior that must remain unchanged (HIGH-RISK surface — do not touch without profiling evidence, and the viewType discrepancy is explicitly not to be resolved by this plan):** Window size/shape; eviction-before-init ordering; the generation-counter race guard; **the current `viewType` value on both surfaces, exactly as found (`textureView` on both)** — this plan does not propose changing it to match the comment's description or for any other reason; `EnableImpeller=false`; mute/volume semantics; the `pauseAll()` vs `releaseAll()` distinction.
5. **Proposed optimization:**
   - **(a) [Candidate, not scheduled in the near-term batch]** Add `WidgetsBindingObserver`/`didChangeAppLifecycleState` to `_ReelsScreenState`, mirroring the Home rail's already-proven pattern, to pause playback when the full-screen feed is backgrounded at the OS level — a gap independent of the viewType finding.
   - **(b) [Candidate]** Add the missing unit/widget tests for `ReelControllerManager`'s window transitions, generation guard, and pause/resume behavior.
   - **(c) [Explicitly not proposed by this plan]** Resolving the `platformView`/`textureView` comment-vs-code discrepancy. This requires someone with the original context (was the comment ever accurate? was this an intentional revert, or an unintentional regression re-exposing a device-specific bug?) to investigate separately. **This plan does not recommend changing the renderer, and flags this explicitly as something that must not be "fixed" as a side effect of any other Reels work in this plan.**
   - **(d) Blocked without physical-device profiling evidence:** any change to window size, eviction/init ordering, the generation guard, or `viewType`.
6. **Hypothesis, pending physical-device measurement:** (a) may stop unwanted audio/battery drain when the app is backgrounded mid-reel; not measured. (c) has no performance hypothesis attached — it is a correctness/investigation item, not a performance one.
7. **Exact files expected to change:** `lib/screens/reels/reels_screen.dart` (for a); new test file(s) (for b). None for (c) under this plan.
8. **Existing tests protecting behavior:** `test/reels_screen_layout_test.dart`, `test/reels_activity_state_test.dart`, `test/home_reels_categories_test.dart`, `test/reel_share_dm_test.dart`, `test/reel_share_link_test.dart` — none exercise `ReelControllerManager`'s window math, disposal ordering, lifecycle behavior, or `viewType`.
9. **Missing tests needed before implementation:** Exactly the gap in point (b), sequenced before (a).
10. **Performance measurements before/after:** Not yet measured — and must be captured specifically on a Vivo or MediaTek physical device given this file's documented device-specific bug history, before (a) or any future (d) item is attempted.
11. **Risk level:** (a) Medium. (b) Low. (c) Out of scope for this plan — not risk-rated here. (d) High — explicitly blocked.
12. **Potential regression scenarios:** For (a), an unstated product requirement for reel audio to continue when backgrounded would make a blanket pause a regression — confirm with product first.
13. **Feature-flag requirement:** None for (a)/(b).
14. **Rollback procedure:** Revert the `WidgetsBindingObserver` addition; it's additive and isolated.
15. **Stop conditions:** If manual testing shows audio/video does not cleanly pause/resume across backgrounding on at least one Android device, stop and do not merge (a).
16. **Definition of done:** For (a)/(b), if pursued: backgrounding the app while a reel plays stops playback and resumes correctly; new window/generation-guard tests exist and pass. The viewType discrepancy (c) is documented and handed off, not resolved, by this plan.
17. **Recommended commit boundaries:** One commit for (b) tests (land first, if pursued); one commit for (a), referencing the new tests.

---

### Module 7 — Feed

1. **Current implementation:** The real content feed (`lib/screens/feed/feed_screen.dart`) merges properties/projects/influencer videos via a single bounded fetch. Each item-type's action row does `context.watch<X>()` on a global provider for just its own liked/saved boolean, so liking one card rebuilds every other currently-built card's action row of the same type. `FeedProvider.visibleItems` recomputes on every access by design/comment.
2. **Exact files/classes/widgets/providers:** `lib/screens/feed/feed_screen.dart` (`_PropertyFeedActions:1070`, `_ProjectFeedActions:1218`, `_VideoFeedActions:1372`); `lib/providers/feed_provider.dart:33-39`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed via direct code read; the `visibleItems` comment explicitly acknowledges the recompute-on-every-read design.
4. **Behavior that must remain unchanged:** The merge/ordering logic; fetch limits (50/50/30 — do not reduce, consistent with the Module 1 prohibition); all documented filter-predicate "quirks"; like/save/comment optimistic-update-with-rollback semantics and sign-in gating.
5. **Proposed optimization (candidates, not scheduled in the near-term batch):** (a) Apply Module 3's pattern to the three action-row widgets. (b) Memoize `FeedProvider.visibleItems`.
6. **Hypothesis, pending physical-device measurement:** May reduce unrelated card rebuilds on a like; not measured.
7. **Exact files expected to change:** `lib/screens/feed/feed_screen.dart`, `lib/providers/feed_provider.dart`.
8. **Existing tests protecting behavior:** **None** — no `feed_*test.dart` file exists anywhere.
9. **Missing tests needed before implementation:** A merge/sort/filter-predicate characterization test (protecting the documented "quirks") must land and pass against the *current, unmodified* code before any change here, given zero existing coverage.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low-Medium, raised specifically by zero existing test coverage. (b) Low.
12. **Potential regression scenarios:** None identified beyond the standard Selector-equality hazard (Module 3, point 12).
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-file revert.
15. **Stop conditions:** Do not implement (a) until the characterization tests in point 9 exist and pass against the current code.
16. **Definition of done:** Not applicable until separately scheduled.
17. **Recommended commit boundaries:** One commit adding characterization tests only (no behavior change); one commit per action-row conversion; one commit for the memoization — all deferred.

---

### Module 8 — Messaging / notifications

1. **Current implementation:** Realtime subscriptions are correctly disposed — no leak found. Batched queries are used correctly for shared-content resolution. Chat message bubbles render via a lazy `ListView.builder` without stable `key:`s, causing unnecessary Element-update churn on visible rows when a new message arrives. `ChatMediaView` resolves a signed URL per image/voice bubble with no caching.
2. **Exact files/classes/widgets/methods:** `lib/screens/messaging/chat_thread_screen.dart:1062,1105,1125,823`; `lib/providers/chat_thread_provider.dart` (dispose, correct; merge/sort logic); `lib/screens/messaging/widgets/chat_media_view.dart:39-93`; `lib/services/chat_media_service.dart:199`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by direct code read, plus by actually running `flutter test test/notification_centre_test.dart` to root-cause its failures (see §2) rather than assuming.
4. **Behavior that must remain unchanged:** Realtime delivery must stay push-based, never polling (this module proposes no change to subscription timing — see Module 1's prohibition on realtime-timing changes, which applies here too); message ordering; merge-not-replace pagination; the unread count must stay derived, never a separate counter field; duplicate-insert guarding; the arrival-cue must remain best-effort/non-blocking.
5. **Proposed optimization (candidates, not scheduled in the near-term batch):** (a) Add `key: ValueKey(message.id)` to chat bubbles. (b) Cache resolved signed URLs with an expiry check. (c) Avoid the full-list `.reversed.toList()` copy on every notify. (d) Apply Module 3's pattern to split header/composer fields from the message-list dependency.
6. **Hypothesis, pending physical-device measurement:** May reduce Element churn per new message; not measured.
7. **Exact files expected to change:** `lib/screens/messaging/chat_thread_screen.dart`, `lib/providers/chat_thread_provider.dart`.
8. **Existing tests protecting behavior:** `test/notification_centre_test.dart` (49 of 53 passing, 4 categorized in §2); `test/chat_thread_report_test.dart`; `test/messaging_collab_hidden_test.dart`.
9. **Missing tests needed before implementation:** A widget test confirming `ValueKey` additions don't change rendered content/order; a unit test for signed-URL cache expiry.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low. (b) Low. (c) Low. (d) Medium.
12. **Potential regression scenarios:** For (d), a callback capturing a stale provider reference if the split is done carelessly.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-item revert.
15. **Stop conditions:** None beyond the standard per-module test gate.
16. **Definition of done:** Not applicable until separately scheduled.
17. **Recommended commit boundaries:** One commit each for (a)/(b)/(c)/(d), kept independent, if/when pursued.

> **Separately flagged, not part of this performance module and not a performance issue:** `_ChatThreadViewState.dispose()` calls `context.read<ChatThreadProvider>()` inside `dispose()`, which Flutter disallows — silently caught by a try/catch, so the "hide an empty DM when you leave without messaging" feature likely never actually fires in production. Recommend a separate functional-bug ticket. Likewise, the "N new" pill regression and the stale `BottomNavBar` overflow-test assertion (§2) are UI/test-maintenance items, not performance work.

---

### Module 9 — Profiles / detail screens

1. **Current implementation:** `PropertyService.getPropertyDetail()` runs 4 sequential round-trips where the final 3 are mutually independent and could run concurrently via `Future.wait` — the same pattern `ProfileProvider` already uses correctly elsewhere. No cross-navigation cache exists anywhere in this area. Only 2 `Hero` widgets exist app-wide; the property-detail-carousel-to-gallery one is live and un-precached; the profile-avatar one is confirmed dead code (no caller supplies the required argument).
2. **Exact files/classes/methods:** `lib/services/property_service.dart:280-336`; `lib/providers/profile_provider.dart:71-74` (reference pattern); `lib/screens/property_detail/property_detail_screen.dart:610,182-215`; `lib/screens/profile/widgets/public_profile_identity.dart:74-76` (dead Hero).
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by direct code read of the dependency chain; no round-trip-count or latency measurement exists yet.
4. **Behavior that must remain unchanged:** `NetworkRelationshipKind`/`classifyRelationship`'s asymmetric-by-design behavior; the live Hero's exact tag format; `profiles_public`/`approval_status` gating throughout; `project_detail_screen.dart`'s deliberate sequential project-then-builder load — do not parallelize this one.
5. **Proposed optimization:**
   - **(a) [Low risk, clearest candidate]** Parallelize `getPropertyDetail()`'s 3 independent trailing queries with `Future.wait`, mirroring `ProfileProvider`'s own existing pattern. This is a same-data, same-shape change — fewer round trips, identical output.
   - **(b) [Candidate]** Precache the next 1-2 property-gallery images before the live Hero transition.
   - **(c) [Blocked — needs a product decision this plan cannot make]** A short-TTL cache for profile/property/project detail fetches, explicitly excluding any connection/relationship/approval-status field from caching — conflicts with `PublicProfileProvider`'s documented anti-stale-bleed design unless a product owner explicitly signs off.
6. **Hypothesis, pending physical-device measurement:** (a) reduces round-trip count, which plausibly reduces latency, but has not been measured.
7. **Exact files expected to change:** `lib/services/property_service.dart` (a); `lib/screens/property_detail/property_detail_screen.dart` (b).
8. **Existing tests protecting behavior:** No test exists for `PropertyDetailScreen` at all — zero screen-level regression coverage for (a) today.
9. **Missing tests needed before implementation:** A test for `getPropertyDetail()` asserting identical output shape/values whether the 3 trailing queries run sequentially or in parallel, before converting (a).
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low. (b) Low-Medium. (c) Medium, blocked pending product sign-off.
12. **Potential regression scenarios:** For (c), caching a connection/relationship field would show a stale badge after the user disconnects elsewhere — excluded from scope for exactly this reason.
13. **Feature-flag requirement:** None for (a)/(b); (c) requires explicit product confirmation, not a flag, before any implementation.
14. **Rollback procedure:** Per-file revert.
15. **Stop conditions:** Do not implement (c) without an explicit product answer to the open question about cross-navigation caching.
16. **Definition of done:** `getPropertyDetail()` makes 2 round-trips instead of 4 with identical output and a passing parity test; (c) remains unimplemented pending product decision.
17. **Recommended commit boundaries:** One commit for (a) + its new test; one commit for (b), if pursued.

---

### Module 10 — Forms (post-property wizard, article editor)

1. **Current implementation:** `PostPropertyProvider` (~90 `notifyListeners()` call sites, all unconditional) is watched broadly both by the wizard shell and independently by every one of its 9 step widgets, so a single keystroke rebuilds the shell chrome and the entire current step's widget subtree. Validation is confirmed to run only on Continue/Publish tap, never per-keystroke. `TextEditingController`s are confirmed correctly created once in `initState`.
2. **Exact files/classes/methods:** `lib/providers/post_property_provider.dart`; `lib/screens/post_property/post_property_screen.dart:161`; `lib/screens/post_property/steps/*.dart` (9 files); `lib/screens/articles/article_editor_screen.dart:204` (smaller-scale, optional secondary candidate).
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by direct code read of every step file's `build()` method and the provider's setter list.
4. **Behavior that must remain unchanged:** All validation rules and their invocation timing, pinned by `test/wizard_end_to_end_test.dart`; the exact payload/DB record shape on submit (`test/post_property_metadata_roundtrip_test.dart`); step order/visibility per category; the confirmation/approval-status branching on submit.
5. **Proposed optimization (candidates, not scheduled in the near-term batch — this is the single largest, highest-effort item in the plan):**
   - (a) Narrow the wizard shell's watch to just the few fields it needs.
   - (b) Narrow each of the 9 step widgets' own watch, one step file at a time, verified against `wizard_end_to_end_test.dart` after each.
   - (c) Add a same-value no-op guard to the hot plain-value setters.
   - (d) Optionally apply the same narrowing to `article_editor_screen.dart`.
6. **Hypothesis, pending physical-device measurement:** (a) and (b) may reduce rebuild scope per keystroke; this has not been measured and this module is explicitly the largest-effort, highest-regression-risk item in the plan, so it should only proceed after Module 3's reference conversions have already been implemented and measured elsewhere.
7. **Exact files expected to change:** `post_property_screen.dart` (a); all 9 step files, one at a time (b); `post_property_provider.dart` (c); `article_editor_screen.dart` (d, optional).
8. **Existing tests protecting behavior:** `test/wizard_end_to_end_test.dart`; `test/post_property_shell_layout_test.dart`; `test/post_property_metadata_roundtrip_test.dart`.
9. **Missing tests needed before implementation:** A widget test per step verifying every field the step's `build()` conditionally branches on still updates correctly after conversion — the dominant risk in this module.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low. (b) Medium-High per step file — sequence last among all Selector-pattern modules, one file at a time. (c) Low. (d) Low, optional.
12. **Potential regression scenarios:** Under-scoping a step's `Selector` could miss a conditional section tied to a field not included in the selected tuple — the dominant risk, and why this module is sequenced last and done one file at a time, never batched.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-step revert — each step file is an independent commit.
15. **Stop conditions:** If any step's `wizard_end_to_end_test.dart` flow fails after that step's conversion, stop immediately, do not proceed to the next step file.
16. **Definition of done:** Not applicable until separately scheduled, after Module 3's pattern has already been validated elsewhere with real measurements.
17. **Recommended commit boundaries:** One commit for (a). One commit per step file for (b) — 9 separate commits, each independently revertable, each run against the full test suite before the next. One commit for (c). One commit for (d) if pursued.

---

### Module 11 — Media / uploads

1. **Current implementation:** Every multi-file upload path uploads sequentially. For project assets this is confirmed **deliberate**, explicitly commented as mirroring the web portal's own sequential loop. Client-side compression values genuinely and intentionally differ per surface. Only chat's EXIF-strip uses `compute()`/isolate; the Instagram-Feed crop/re-encode path runs synchronously on the UI isolate. No progress UI exists for the highest-traffic upload path (property photos).
2. **Exact files/classes/methods:** `lib/services/property_service.dart:1157-1191`; `lib/screens/add_project/steps/contact_media_step.dart:113-116` (deliberate sequential, do not silently change); `lib/services/social_service.dart:547-641`; `lib/services/chat_media_service.dart:334-344` (pattern to copy); `lib/services/influencer_media_service.dart:102-161` (progress pattern to copy).
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by direct code read of every upload/compression call site; no throughput or jank measurement exists.
4. **Behavior that must remain unchanged:** Every compression dimension/quality value exactly as currently set per surface (do not unify); every storage path convention; every service's independently-duplicated MIME-detection table (do not "DRY" these — a silent contract change); all size ceilings; the project-media loop's deliberate sequential-to-match-web behavior.
5. **Proposed optimization (candidates, not scheduled in the near-term batch):** (a) Wrap the Instagram-Feed crop/re-encode in `compute()`. (b) Add staged progress callbacks to the property/project upload loops. (c) Reuse one `ChatMediaService` instance for repeated "Save image" taps. (d) Parallelize `PropertyService._uploadMedia` with bounded concurrency, preserving output ordering and all-or-nothing failure semantics — explicitly flag, do not silently change, the project-media loop's sequential behavior if ever touched.
6. **Hypothesis, pending physical-device measurement:** (a) may reduce UI jank during Instagram-Feed publishing; (d) may reduce multi-photo upload wall-clock time; neither is measured.
7. **Exact files expected to change:** `lib/services/social_service.dart` (a); `lib/services/property_service.dart`, `lib/screens/add_project/steps/contact_media_step.dart` (b); `lib/screens/messaging/widgets/chat_bubble.dart` (c); `lib/services/property_service.dart` (d).
8. **Existing tests protecting behavior:** `test/property_media_upload_test.dart` and siblings cover MIME/size-ceiling pure-function contracts; none test upload concurrency/ordering or timing.
9. **Missing tests needed before implementation:** For (d) — a test asserting byte-for-byte identical output URLs/ordering whether uploads run sequentially or with bounded concurrency, and a test asserting all-or-nothing failure behavior is preserved.
10. **Performance measurements before/after:** Not yet measured.
11. **Risk level:** (a) Low. (b) Low. (c) Low. (d) Medium.
12. **Potential regression scenarios:** For (d), a naive unordered concurrency approach could scramble the `urls` array order, silently changing which photo becomes `main_display_media_url`.
13. **Feature-flag requirement:** None.
14. **Rollback procedure:** Per-item revert.
15. **Stop conditions:** For (d), if the ordering/failure-semantics test cannot be made to pass reliably, do not ship — fall back to sequential.
16. **Definition of done:** Not applicable until separately scheduled.
17. **Recommended commit boundaries:** One commit each for (a), (b) [property], (b) [project media], (c), if/when pursued. (d) as its own, later, separately-tested commit.

---

### Module 12 — Android release optimization

1. **Current implementation:** `isMinifyEnabled = false`, `isShrinkResources = false`. No app-level `proguard-rules.pro` exists. No CI/release pipeline exists. 476 `debugPrint` call sites and 10 raw `print()` calls run unconditionally in release builds; one site logs raw exception content in production. Impeller is confirmed disabled and must stay that way. Release-signing enforcement is correct and pre-existing — not a performance item.
2. **Exact files/config involved:** `android/app/build.gradle.kts:92-120`; `android/app/src/main/AndroidManifest.xml:21-25` (Impeller, do not touch); the 111 files with `debugPrint`, 6 files with raw `print()`.
3. **Evidence of the problem (code-level observation; impact not yet measured):** Confirmed by full read of `build.gradle.kts` and repo-wide searches for `proguard*.pro` and CI config (both zero results). **Corrected per the safety review:** the absence of `proguard-rules.pro` does **not** by itself prove R8 would break the app — Gradle automatically merges consumer ProGuard rules shipped inside dependency AARs (Supabase, Firebase, and others may already provide their own), so the actual risk is a **high-risk unknown requiring release-artifact testing**, not a guaranteed failure.
4. **Behavior that must remain unchanged:** Impeller must stay disabled — no module in this plan touches it. Release-signing enforcement must remain intact. If minification is ever enabled, functional correctness across every reflection-dependent library must be verified empirically on a real release artifact — not assumed safe or assumed broken from static inspection alone.
5. **Proposed optimization — all deferred per the safety review:**
   - **(a) [Deferred]** Gate the 10 raw `print()` and 476 `debugPrint` calls behind `kDebugMode`, combined with Module 1's `RoleHomeRouter` item so it is done once. **Per the safety review, this broad sweep is explicitly moved out of the initial performance path** — it is a log-hygiene/size item, not a measured performance fix, and should not inflate an early performance diff. **A narrowly targeted release-log guard may be proposed instead, but only where physical-device profiling shows a specific call site is on a repeated hot path** (e.g., logging inside a per-frame or per-list-item callback) — this is a much smaller, justified exception to the deferral, not a reason to do the full sweep.
   - **(b) [Deferred]** Re-encode oversized bundled assets — an app-size item, not scheduled in the initial performance path.
   - **(c) [Deferred in full — do not implement]** Authoring a `proguard-rules.pro`. The safety review specifically prohibits creating broad speculative keep rules without the ability to validate them. This remains deferred until a physical-device release-build smoke test capability and a staged/internal distribution channel both exist.
   - **(d) [Deferred, gated on (c) and on infrastructure that does not yet exist]** Enabling `isMinifyEnabled`/`isShrinkResources`.
   - **(e) [Open question, not an action item]** Confirm whether release distribution uses AAB or a universal APK — no CI/release script exists to answer this from static inspection.
6. **Hypothesis, pending physical-device measurement and pending infrastructure that does not yet exist:** (a)/(b) may reduce minor runtime overhead and app size; (d) may meaningfully reduce APK/AAB size but carries release-only-breakage risk that is currently unverifiable in this environment.
7. **Exact files expected to change:** None under this plan's near-term scope — all items in this module are deferred.
8. **Existing tests protecting behavior:** None — zero CI, zero release-build test coverage of any kind.
9. **Missing tests needed before implementation:** For (d) specifically: a mandatory, non-automatable gate — a full physical-device **release** build smoke test covering every major flow (auth/OAuth deep links, chat, push notifications, payments, video upload/compress, property posting) — and a staged/internal distribution channel to run it through, neither of which currently exists.
10. **Performance measurements before/after:** Not yet measured; cannot be measured without the infrastructure in point 9.
11. **Risk level:** (a) Low, but deferred by policy, not by risk. (b) Low, deferred. (c) Medium — deferred until testable. (d) High-risk unknown — deferred until (c) and a release smoke-test/staged-distribution capability exist.
12. **Potential regression scenarios:** Enabling (d) without the ability to verify it on a real release artifact could silently break JSON (de)serialization or native-bridge class resolution in ways invisible to every existing Dart-level test.
13. **Feature-flag requirement:** None — this is a build-configuration change. A staged/internal release track is a prerequisite infrastructure item, not a feature flag.
14. **Rollback procedure:** (a)/(b) per-file revert, if ever done. (c) delete the file, if ever authored. (d) revert `isMinifyEnabled`/`isShrinkResources` to `false` — immediate, simple.
15. **Stop conditions:** Do not proceed to (c) or (d) under any circumstance until a release-build smoke-test capability and a staged distribution channel exist. This is a hard stop, not a soft recommendation.
16. **Definition of done:** Not applicable — this entire module is deferred pending infrastructure this plan cannot create.
17. **Recommended commit boundaries:** N/A until the module is unblocked.

---

## 7. Exact profiling checklist (once a device/emulator is available)

1. Obtain: a low-end Android device, a representative mid-range Android device, and preferably one affected Vivo/MediaTek device.
2. On each: `flutter run --profile --dart-define-from-file=config/features/play_release.json`.
3. Capture, per device: cold-start time; first-useful-screen time; DevTools frame chart (UI + raster thread times, janky-frame %) for Home scroll, Search results scroll + one like tap, Reels scroll + app backgrounding, and one Post-Property wizard field edit; rebuild counts via the widget-rebuild overlay for the same scenarios; image-decode/cache memory during a long Search/Chat scroll; active `VideoPlayerController`/decoder count over time while fast-scrolling Reels and while backgrounding/foregrounding mid-playback; count and timing of network requests fired in the first 2 seconds after cold start.
4. Record all of the above as the Module 0 baseline **before** implementing anything beyond Module 0's characterization tests.
5. Re-capture the same metrics after each individual change (never after a batch of unrelated changes) to attribute any delta correctly.
6. If any touched provider/screen is reachable only behind one of the 4 feature flags, separately confirm reachability and, if reachable, also profile under `--dart-define-from-file=config/features/full_development.json`.
7. For any future Module 12 work: this requires a release-artifact smoke test and staged distribution, not just profile-mode capture — see Module 12, point 9.

## 8. Global rollback strategy

- Every module's changes land in isolated, single-purpose commits — never two modules, and never two high-risk items within a module, combined in one commit.
- Before starting any module: create a checkpoint branch/tag off the current state.
- After each commit: run `flutter analyze` + full `flutter test`, diff against the documented baseline (§2's four-category table), and only proceed if no new issues appear.
- If a regression is found after merge, `git revert` the single offending commit.
- Module 2's narrowed experiment has an explicit stop condition (point 15 of that module) independent of this general strategy: a null or negative measurement result pauses further Module 2 work rather than being pushed through.
- Module 1's lazy-provider item requires its own rollback switch or single-commit revertability as a condition of being implemented at all (point 5b).
- No module in this plan changes a public API contract, DB schema, or backend behavior, so no data migration or backend rollback is ever required for anything in this document.

## 9. Items explicitly excluded or prohibited

- **Any result/pagination limit reduction anywhere** — prohibited outright by the safety review; not proposed by this plan under any module.
- **Impeller enablement** — out of scope permanently (Modules 6, 12).
- **State-management migration** — out of scope permanently.
- **Bulk dependency/Flutter version upgrades** — out of scope; `pubspec.lock` was not and must not be modified.
- **Any backend/DB/RPC/Edge-Function change** — out of scope as required work everywhere; flagged only where relevant.
- **Any realtime-subscription-timing change** (notifications, chat, messaging) without the full ordering/catch-up/dedup/test package described in Module 1 — otherwise current timing is preserved exactly.
- **Any splash-timing change** — requires a separate, explicitly approved product/UX decision; not authorized by this plan as a performance refactor.
- **The ~476-call-site logging sweep, dead-file deletion, broad asset re-encoding, and the full 20-site raw-image migration** — deferred out of the initial performance path as low-value-relative-to-risk for an *initial* batch; each remains fully documented in its module for a possible later, separately-scoped pass.
- **Module 12's minification work in full** — deferred until a physical-device release smoke-test capability and staged/internal distribution exist; do not author speculative ProGuard keep rules in the meantime.
- **The 10 pre-existing failing tests (§2)** — documented and categorized by confidence level, explicitly not fixed as part of this project. The "N new" notification pill is a genuine product/UI regression worth its own ticket; the `BottomNavBar`-overflow and `people_search_test.dart` scroll-into-view failures are stale test-harness assumptions worth their own test-maintenance ticket; the `auth_screen_test.dart` and `reel_share_link_test.dart` failures require separate investigation before anyone claims to know their cause.
- **The `dispose()`-unsafe `context.read` bug in `chat_thread_screen.dart:243`** (Module 8) — a real functional bug, flagged for a separate ticket.
- **Resolving the Reels `textureView`/`platformView` comment-vs-code discrepancy** (Module 6) — reported as a fact finding during this review; fixing it (in either direction) is a separate investigation and decision, not part of this performance plan.
- **Unifying per-service MIME-detection tables or compression quality/dimension values** (Module 11) — each is an intentional, independent, web-portal-parity choice.
- **Cross-navigation caching for `PublicProfileProvider`** (Module 9) — gated on an explicit product decision.
- **Parallelizing the project-media upload loop** (Module 11) — explicitly documented as intentional web-parity; not proposed as required work.

---

## 10. Recommended first implementation batch (revised)

**This supersedes any ordering implied by §5's module table. Per the safety review, this is now
the only sequence this plan recommends for a first pass, and it is deliberately far narrower
than the original draft's "Modules 0, 1, 2" framing. Do not approve the remainder of Module 1 as
one combined batch — each lettered step below is its own, separately gated unit of work.**

**A. Module 0 only.**
- Write the characterization tests needed for steps B and C below (see each module's "Missing tests needed before implementation").
- Finalize the exact failing-test baseline using the four-category table in §2.
- Obtain and run the physical-device performance baseline (low-end, mid-range, preferably Vivo/MediaTek), capturing every metric listed in §7.
- **No production behavior changes occur in this step.**
- **If no device is available, stop here.** Document the gap and do not proceed to B or C.

**B. One targeted Module 2 experiment.**
- Exactly one fixed-size thumbnail/avatar surface (e.g., `ChatAvatar` or `PeopleAvatar` — final choice confirmed, not pre-decided, per Module 2 point 5).
- Tests first: display-dimension, placeholder, error-state, and DPR-aware decode-size tests, written and passing before the implementation change.
- Implementation: add the DPR-aware `memCacheWidth`/`memCacheHeight` to that one surface only.
- Before/after measurement: image-memory usage during a scroll of that surface, captured via DevTools on a physical/emulated device, plus a manual visual comparison.
- **Stop condition: if the improvement is not measurable, or if the visual comparison shows any perceptible image-quality change, stop — do not proceed to a second surface or to the broader Module 2 backlog.**

**C. One lazy-provider experiment.**
- Only after the complete consumer/call-site audit for the candidate provider is done and reviewed (Module 1, point 5b) — not before.
- Exactly one provider (candidate: `AvailableLocationsProvider`, pending audit confirmation — not pre-approved).
- **No result limit involved anywhere in this step** — this step changes only *when* the provider's existing, unmodified query runs, never what it returns.
- Characterization tests against the current eager implementation written and passing first.
- Implementation: add an idempotent `ensureLoaded()`, convert the provider to load on first real use, wire `ensureLoaded()` into every entry point identified by the audit including any deep-link path.
- A single, easily revertible commit (or an explicit rollback switch) is a condition of merging this step at all.
- Exact behavior/data parity (same values, same order, same error behavior) proven by the characterization tests before this step is considered complete.

**Nothing beyond A, B, and C is recommended for implementation by this plan. All other modules
(3–12, and the remainder of Module 1) remain fully documented above for future reference, each
still requiring its own separate approval, its own characterization tests, and — per this safety
review — physical-device measurement before any claim that it improves performance.**
