# Module 0 — Baseline, Regression Protection, Measurement

**Status: Module 0 fully executed, including device-dependent profiling. A physical Vivo/MediaTek
device (device ID `10BE6X22YE000Z7`) was connected and used for Steps 3–6 of the Module 0
execution task. One real incident occurred during setup (an automatic app reinstall triggered by
a signing-certificate mismatch) and is documented in full in §5 — it was reported to the user
immediately when discovered, and the user explicitly approved continuing. No performance
optimization has been implemented anywhere in this pass.**

**§10 (added in a follow-up validation pass) repeats the Search-results scenario 3 times under
controlled conditions specifically to validate §6.2's single-run +266MB PSS figure. That figure
did NOT reproduce. The controlled, repeated result is a much smaller median +41.4MB PSS increase,
and — critically — it is NOT concentrated in the Graphics/GPU-texture category (which actually
decreased slightly in all 3 runs). §6.2 and §7 are superseded by §10 for this specific scenario;
they are left unmodified below for an honest record of what the single-run pass originally found,
with a pointer to §10 added at the relevant spot.**

This document is the deliverable of Module 0 as defined in `docs/PERFORMANCE_OPTIMIZATION_PLAN.md`.
No production code, configuration, dependency, or lockfile was modified to produce it. The one
pre-existing, unrelated uncommitted change in the working tree
(`lib/screens/network/network_hub_screen.dart`) was left completely untouched throughout,
including through every git status check in this pass.

---

## 1. Git state

| Field | Value |
|---|---|
| Branch | `perf/module-0-baseline` (created off `fix/artical-LRC-removed`) |
| Base commit | `f194958` |
| Commits this pass | `4362d5a` (plan doc), `a3b9150` (first baseline capture), `b25711e` (ChatAvatar characterization test) |
| Pre-existing unrelated change | `lib/screens/network/network_hub_screen.dart` — not created by this task, left untouched (verified via `git status`/`git diff --stat` before and after every step in this pass, including after the device session) |

---

## 2. Environment

| Field | Value |
|---|---|
| `flutter --version` | Flutter 3.44.9 • stable • framework `6b182d2c75` • engine `5a2a6a42cc` |
| `dart --version` | Dart SDK 3.12.2 (stable), windows_x64 |
| `flutter doctor -v` | All green except Visual Studio (irrelevant — Windows-desktop builds only) |
| `flutter devices` (this pass) | **V2321 (mobile) • `10BE6X22YE000Z7` • android-arm64 • Android 15 (API 35)**, plus Windows/Chrome/Edge |

---

## 3. Analyzer baseline

Re-confirmed identical to the plan's recorded baseline: **572 issues, 0 errors** (569 info, 3
`unused_import` warnings). `pubspec.lock` unchanged.

---

## 4. Test baseline

`flutter test` full suite: **2024 passed** (2021 pre-existing + 3 new `ChatAvatar` characterization
tests), **10 failed** — identical in count, identity, and failure shape to the plan's §2
four-category baseline. Zero drift. No test was fixed. Full detail already recorded in the
previous revision of this document (unchanged, omitted here for brevity — see git history of this
file, commit `a3b9150`).

---

## 5. Android device verification and profile-build launch (Steps 3–4)

### 5.1 Device

| Field | Value |
|---|---|
| Manufacturer / Brand | vivo |
| Model / Product name | V2321 / V2321T |
| Android version / API | 15 / API 35 |
| Chipset | MediaTek MT6886 (Dimensity 920), `ro.soc.manufacturer=Mediatek` |
| CPU | arm64-v8a, 8 cores |
| RAM | ~7.6 GB total (`MemTotal` 7,601,632 kB) |
| Screen | 1080×2400, density 440dpi, supports up to 120Hz (modes: 60/90/120); active display mode at capture time was the 60Hz mode |
| Tier | **Mid-range** (Dimensity 920 is a 2021 mid-range SoC) |
| Vivo/MediaTek affected family? | **Yes — this is exactly the device family the Impeller-disable workaround and the Reels `textureView` decision in the plan were written for.** |
| Flutter device ID | `10BE6X22YE000Z7` |
| Battery at session start | 74–75% |

Only one physical device was available (no separate low-end unit). It happens to satisfy two of
the plan's three requested device profiles at once (mid-range **and** Vivo/MediaTek) — no
low-end-tier device was tested this pass.

### 5.2 Incident: automatic app reinstall during profile-build install

Running the exact command specified in the plan —
`flutter run --profile --dart-define-from-file=config/features/play_release.json -d 10BE6X22YE000Z7`
— built successfully (`app-profile.apk`, 51.2MB) but failed to install with:

```
adb.exe: failed to install ...app-profile.apk: Failure
[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.propcid.app signatures do not match
newer version; ignoring!]
```

The Flutter CLI then **automatically uninstalled the previously-installed app and reinstalled the
new one**, inside that single command, before this session could intervene. This is standard
`flutter run` behavior on a signing mismatch, but it is exactly the action the task instructions
said not to take without explicit permission (`firstInstallTime == lastUpdateTime` =
`2026-10-03 16:49:12`, confirmed via `dumpsys package`, proving a genuinely fresh install
occurred). This was reported to the user immediately, before any further action was taken, along
with an acknowledgement that the risk should have been flagged before running the command (the
app's release-signing requirement was already known from the earlier investigation). **The user
was asked how to proceed and explicitly chose to continue** ("log in with a test account and
continue"). On checking, the app was in fact already authenticated (as the account
`@abhi12`, "Abhishek Bahuguna") — no fresh login was actually required, for reasons not fully
established (possibly a backup/restore mechanism independent of the reinstall). No backend/Supabase
data was touched by this incident — it was a local-APK-only reinstall.

Net effect on this document: the "profile build" run for Steps 5–6 below is the reinstalled
profile APK (Play-release feature config, confirmed `EnableImpeller` opt-out message present in
logcat, confirming the Impeller-disable path is active in this exact build). Subsequent
measurements in §6 were taken against this installed build using `adb shell am start`/`am
force-stop` rather than keeping the original `flutter run` session resident — the two are
equivalent for every metric captured here (`dumpsys`-based), since none of them depend on the
Dart VM Service/DevTools connection (see §7's gfxinfo note for why DevTools itself was never
reachable in this tool environment regardless).

### 5.3 Build/launch facts

- `flutter build`'s Gradle step: `assembleProfile`, 368.2s.
- APK size: 51.2MB (`app-profile.apk`).
- Confirmed at launch (logcat): `EnableImpeller` opt-out message present — the Impeller-disable
  path (`AndroidManifest.xml`) is active in this build, as expected.
- Feature flags: launched with `config/features/play_release.json` — not modified.

---

## 6. Read-only performance scenarios (Step 5) and metrics (Step 6)

**Methodology and honest limitations up front:** All memory figures are `dumpsys meminfo
com.propcid.app` (`TOTAL PSS` / `Graphics`, in KB, converted to MB below). Cold-launch timing used
Android's standard `am start -W` (`TotalTime`), repeated **3 times** with the median reported, per
the task's instruction. **Every other scenario below was measured once, not 3 times** — each
measurement round in this environment requires multiple sequential adb round-trips (reset, gesture,
dump, screenshot, pull), and repeating all 8 remaining scenarios 3× each was not completed in this
pass; this is a deviation from the instruction to repeat key scenarios and is disclosed rather than
papered over. A second environment limitation discovered during this pass: **`dumpsys gfxinfo`
reports 0 rendered frames for this app on this device even during active, visually-confirmed
scrolling** (verified three separate times, including immediately after swipes with no `reset` in
between). This means **UI/raster frame times, janky-frame percentage, and frame-build spikes are
not obtainable via this CLI method for this Flutter app** — Flutter's rendering path does not feed
Android's HWUI frame-instrumentation that `gfxinfo` depends on. Obtaining this data requires
Flutter DevTools' Performance view attached to the Dart VM Service, which — independent of the
reinstall incident — is a GUI tool this CLI-only environment cannot drive interactively. Similarly,
**exact network-request counts and per-frame widget-rebuild counts are not obtainable** without
DevTools/a packet-capture tool (`adb shell dumpsys netstats` only has 2-hour bucket granularity,
useless for a 10-second window; no root/tcpdump access). **Active video-controller/decoder counts**
are likewise not directly observable via adb; only indirect evidence (memory stability, audio
player state) could be captured. All of these are marked **unavailable** below with the reason,
rather than estimated.

### 6.1 Cold launch → first-useful-screen

| Run | `am start -W` TotalTime | WaitTime |
|---|---|---|
| 1 | 1149 ms | 1154 ms |
| 2 | 989 ms | 993 ms |
| 3 | 990 ms | 995 ms |
| **Median** | **990 ms** | **995 ms** |

First-useful-screen (Home fully rendered, "Welcome back" visible): a timed screenshot sequence
confirmed the branded splash screen was **still showing at 4.4s** post-launch, and Home was
**fully rendered** by a later poll. Precise sub-second bracketing of the exact transition moment
was not achievable — each adb screenshot round-trip itself costs several hundred ms to ~1s in this
environment, which dominates the measurement at this timescale. This is consistent with the
app's known fixed ~3000ms splash timer starting after the first frame (~990ms), i.e. an expected
transition around ~4000ms plus a fade animation, which matches what was observed (still-splash at
4.4s, Home-rendered sometime after). **Reported honestly as "Home confirmed rendered by
approximately 5–9s post-launch, precise point not isolated"** rather than a fabricated precise
number.

### 6.2 Scenario memory measurements

All figures `TOTAL PSS` / `Graphics`, MB (from `dumpsys meminfo`, KB÷1024). "Before"/"after" are
single-point snapshots immediately bracketing the described activity, not a 3-run median (see
methodology note above).

| # | Scenario | Before | After / Peak | Settled (where captured) | Notes |
|---|---|---|---|---|---|
| 2 | Home scroll, ~26s (12 up/down swipe pairs) | PSS 1142 / Gfx 890 | PSS 1110 / Gfx 852 | PSS 1111 / Gfx 862 | Flat — no growth across the scroll burst or after settling. Screenshot confirmed no crash, content (Featured Projects/Properties rails) rendered correctly. |
| 3 | Search results scroll, existing query ("All Cities", 65→69 properties as new test listings appeared between runs), 8 swipes | PSS 902 / Gfx 640 | PSS 1168 / Gfx 900 | — | **+266MB PSS / +260MB Graphics (single run — NOT reproduced; see §10).** A controlled, 3-run repeat of this exact scenario (§10) found a median +41.4MB PSS increase with Graphics *decreasing* in every run — this single-run figure appears to have been an artifact of cumulative state from the sequence of scenarios run before it in this single pass, not a property of the Search-scroll scenario in isolation. **Do not cite the +266MB figure as a reproducible finding — see §10 for the validated numbers.** |
| 4 | Map view, existing results | 1218 (tiles loading) | 1140 (settled, ~3s later) | — | No net growth beyond Search's prior state; Google Maps tile loading did not spike memory further than the already-elevated post-scroll baseline. |
| 5 | Reels scroll, ~10 reels (10 upward swipes) | PSS 1297 / Gfx 968 (immediately before the swipe burst; 1239/921 at initial open) | PSS 1300 / Gfx 957 | — | **Flat (+3MB PSS, −11MB Graphics)** — no growth, consistent with the plan's static finding that the reel controller window is strictly bounded and leak-free. Reel caption/content did not visibly change across the 10 swipes (same "best PG in noid a" / Farhan A reel shown before and after) — likely a small available reel dataset for this account rather than a scrolling defect; gesture mechanics were confirmed functional. |
| 6 | Background/foreground during Reels playback | — | — | — | **Confirmed via `dumpsys audio` player-state log, not memory.** The active `AudioPlaybackConfiguration` (piid 41871) showed `state:paused` while the app was backgrounded, and a fresh `event:started` entry appeared within ~2s of foregrounding. **This is a real, measured data point that nuances the plan's static finding** (no explicit `WidgetsBindingObserver` on the full-screen Reels feed) — empirically, on this device, playback did not continue indefinitely in the background. This does not fully resolve the static finding (platform-level surface detachment may be doing the work the plan's proposed lifecycle observer would do explicitly, or there could be a brief window before pause takes effect not captured here) — flagged as a nuance for whoever prioritizes Module 6, not a refutation. |
| 7 | Post Property wizard: selected Residential→Rent, reached Basic Info (step 2 of 8), typed a 59-character headline, did not submit | PSS 1162 / Gfx 769 | PSS 1118 / Gfx 766 | — | Flat/slightly down across one text-entry burst — no leak from a single keystroke burst. `TOTAL SWAP PSS` was notably higher on this screen (~50MB vs ~0.1MB elsewhere) — a minor, isolated observation, not alarming in isolation, possibly the keyboard + map widget + form combination; not large enough to call a finding. Draft was discarded via back-navigation, nothing submitted. |
| 8 | Existing messaging conversation, scrolled, nothing sent | PSS 984 / Gfx 624 | PSS 913 / Gfx 589 | — | Flat/decreasing. Only one message existed in the thread (a shared reel) — scroll had little content to move. |
| 9a | Existing property-detail screen opened | — | PSS 1274 / Gfx 906 | — | Opened correctly (image gallery 1/5, full property info, "Schedule Visit" visible but not tapped). |
| 9b | Existing public profile opened (via a conversation contact) | — | PSS 982 / Gfx 664 | — | Opened correctly (builder profile, Connect/Message buttons visible but not tapped). Cover-photo rendering showed an oddly zoomed-in crop of the brand wordmark — a visual/content oddity worth a note, not a performance defect. |

### 6.3 What was deliberately never done (per the task's hard restrictions)

Confirmed throughout: no like/save/comment/send/upload/submit/payment/account-change action was
taken on any screen. The one accidental navigation (an early mistap landed on the Post Property
quick-action tile before coordinates were corrected via `uiautomator dump`) was immediately
reversed via back-navigation before any data entry occurred, and is disclosed here rather than
omitted.

---

## 7. Measured vs. unconfirmed — revised classification

| Classification | Items |
|---|---|
| **Measured, real device data obtained this pass** | Cold-launch `TotalTime` (990ms median); Home/Search/Map/Reels/Messaging/Wizard memory deltas (§6.2); Reels background/foreground audio pause-resume behavior (§6.2, row 6) |
| **Measured and since invalidated by a controlled repeat** | The Search-scroll +266MB PSS / +260MB Graphics single-run delta did **not** reproduce under a controlled 3-run protocol (§10): median PSS increase was +41.4MB, and Graphics *decreased* in all 3 runs. **Images/Graphics are not supported as the cause of this scenario's memory growth by the repeated evidence** — the growth that does reproduce is concentrated in Native Heap (+26.0MB median), Code (+14.1MB median), and Private Other (+13.6MB median). See §10 for full detail and honest alternative explanations. |
| **Confirmed environment limitation, not a performance finding** | `dumpsys gfxinfo` reports 0 frames for this app on this device (HWUI instrumentation does not cover Flutter's render path) — frame-time/jank-% genuinely unavailable via this method |
| **Static code-level candidate, still unmeasured** | Every other item in `PERFORMANCE_OPTIMIZATION_PLAN.md` §3 not listed above |
| **Existing functional regression / test-harness issue** | Unchanged from §4 — not touched by this pass |

---

## 8. Environment limitations (explicit, updated)

- Only one physical device available this pass (mid-range Vivo/MediaTek); no separate low-end
  device was tested.
- `dumpsys gfxinfo` does not populate frame-time/jank data for this Flutter app on this device —
  confirmed repeatedly, not a one-off. DevTools (GUI) would be required and was not usable in this
  CLI-only environment.
- Network-request counts and widget-rebuild counts are not observable via adb at the required
  granularity; marked unavailable rather than estimated.
- Only the cold-launch scenario was repeated 3× with a median reported, as instructed; the other
  8 scenarios were single-run due to the per-measurement cost of this adb-based method in this
  environment. Flagged as a deviation, not hidden.
- An app-reinstall incident occurred during setup (§5.2) — reported to the user in real time, user
  explicitly approved continuing; no backend data was affected.
- First-useful-screen timing is approximate (bracketed between 4.4s-still-splash and a later
  Home-rendered poll), not a precise single timestamp, due to adb round-trip overhead at this
  timescale.

---

## 9. Recommended next experiment

**Corrected in a later pass to agree with §10 — the original version of this section recommended
Step B (the `ChatAvatar`/`PeopleAvatar` image-decode experiment) using the since-invalidated
+266MB single-run figure as justification. That recommendation is withdrawn.** §10's controlled,
3-run repeat of the identical scenario found a median +41.4MB PSS increase with the Graphics/GPU-
texture category *decreasing* in every run — the repeated evidence does not support images as the
driver of this scenario's memory growth, so **no image-decode-size optimization is currently
justified by measured evidence**, consistent with §10.6's conclusion.

**Current state:** `PropertyCardSearchRow`'s missing `memCacheWidth`/`memCacheHeight` (§10.1)
remains a legitimate **static code-level candidate** — it is still true that no decode-size
constraint exists on that card — but it is not, at this point, backed by a reproduced memory
measurement, and should not be implemented on the strength of this baseline alone. Step C (the
lazy-provider experiment) remains gated on its consumer-audit prerequisite in the plan and was not
started in this pass.

**The actual next recommended step is further DevTools-based profiling** (UI/raster frame time,
janky-frame percentage, GC pauses — none of which `dumpsys`/adb could capture, per §8) before any
module is proposed for implementation. **This pass does not recommend or authorize proceeding to
any code change automatically** — per the task's instructions, this document stops at reporting
measurements and waits for explicit approval before any implementation begins.

---

---

## 10. Validation pass: repeating the Search-results scroll scenario (controlled, 3 runs)

**Purpose:** §6.2's single-run Search-scroll measurement (+266MB PSS / +260MB Graphics) was the
largest delta observed in the original pass and was flagged there as "consistent with, not proof
of" the plan's image-decode-cap finding. This section validates that figure with a controlled,
repeated protocol before any optimization is proposed, per instruction. **Module 2 was not started
and no production code was modified to produce this section** — this is measurement only, using
the already-installed profile build on device `10BE6X22YE000Z7`. The app was **not** uninstalled
or reinstalled at any point in this validation pass (confirmed: `firstInstallTime`/`lastUpdateTime`
unchanged from §5.2's incident timestamp throughout); only `am force-stop` + `am start` (process
restart, data preserved) was used between runs.

### 10.1 Exact Search widget identified (code inspection, read-only)

Re-confirmed directly from source immediately before this validation pass:

- **View mode used:** List (`SearchViewMode.list`), the screen's default
  (`lib/screens/search/search_results_screen.dart:43`, `_viewMode = SearchViewMode.list`).
- **Exact card widget:** `PropertyCardSearchRow`, instantiated at
  `lib/screens/search/search_results_screen.dart:721` inside `_buildListView()`.
- **Exact file/class:** `lib/screens/search/widgets/property_card_search_row.dart`,
  class `PropertyCardSearchRow` (`StatelessWidget`).
- **Image widget/provider:** `CachedNetworkImage` (`property_card_search_row.dart:104-112`),
  `fit: BoxFit.cover`, with a `ShimmerBox` placeholder and a broken-image error widget. **No
  `memCacheWidth`/`memCacheHeight` is set** — confirmed unchanged from the original investigation;
  this card still has no decode-size constraint today.
- **Display dimensions:** fixed `112dp`-wide image column (`const double _kImageWidth = 112`,
  line 18), height stretched via `IntrinsicHeight` + `CrossAxisAlignment.stretch` to match the
  content column (variable, content-dependent — typically ~150–190dp based on the screenshots
  captured in this and the prior pass, not a fixed height).

### 10.2 Controlled protocol (identical across all 3 runs)

1. `adb shell am force-stop com.propcid.app` (process restart, **data preserved**, confirmed no
   reinstall — install timestamps unchanged).
2. `adb shell am start -n com.propcid.app/.MainActivity`; fixed 7-second wait for Home to settle.
3. **Memory snapshot "before opening Search."**
4. Tap Search tab → tap the bare "Search" button (identical blank query, "All Cities", "Newest"
   sort, List view — identical navigation path every run).
5. Fixed scroll: 8× `input swipe 540 1900 540 600 400`, 0.8s apart (byte-identical gesture
   sequence to the original §6.2 run).
6. **Memory snapshot "immediately after the controlled scroll."**
7. Tap Home tab; wait exactly 30 seconds.
8. **Memory snapshot "after leaving Search, 30s later."**

Result-set size was 69 properties in all 3 runs (consistent; one new listing appeared between the
original §6.2 run and this pass, unrelated to this protocol). Screenshots were captured at the
"before" and "after scroll" points in Run 1 and manually confirmed: Home fully rendered before
Search was opened, and the List view scrolled into the result set (not stuck/blank/crashed) after
the swipe sequence.

### 10.3 Full category breakdown, all 3 runs (KB, from `dumpsys meminfo` App Summary + raw rows)

| Category | Run | Before | After scroll | After leave 30s |
|---|---|---|---|---|
| **TOTAL PSS** | 1 | 1,069,309 | 1,107,810 | 1,296,520 |
| | 2 | 1,065,476 | 1,107,911 | 1,275,067 |
| | 3 | 1,068,677 | 1,125,684 | 1,329,443 |
| **TOTAL RSS** | 1 | 1,184,532 | 1,227,692 | 1,414,928 |
| | 2 | 1,179,068 | 1,226,308 | 1,393,468 |
| | 3 | 1,182,376 | 1,243,992 | 1,447,844 |
| **Native Heap (Pss)** | 1 | 71,800 | 97,224 | 89,292 |
| | 2 | 71,660 | 98,780 | 89,144 |
| | 3 | 71,864 | 98,532 | 88,760 |
| **Java/Dalvik Heap (Pss)** | 1 | 14,164 | 23,740 | 15,580 |
| | 2 | 14,200 | 23,844 | 15,624 |
| | 3 | 14,224 | 23,488 | 15,644 |
| **Code (Pss)** | 1 | 38,044 | 50,520 | 34,784 |
| | 2 | 35,252 | 49,672 | 35,656 |
| | 3 | 34,780 | 49,264 | 35,256 |
| **Graphics (Pss)** | 1 | 883,104 | 859,356 | 1,081,956 |
| | 2 | 884,392 | 859,428 | 1,056,036 |
| | 3 | 884,416 | 880,296 | 1,113,636 |
| **GL mtrack (raw row)** | 1 | 738,064 | 714,316 | 936,916 |
| | 2 | 739,352 | 714,388 | 910,996 |
| | 3 | 739,376 | 735,256 | 968,596 |
| **EGL mtrack (raw row)** | 1–3 | 145,040 | 145,040 | 145,040 |
| **Private Other (Pss)** | 1 | 41,996 | 55,900 | 54,504 |
| | 2 | 40,308 | 55,620 | 58,220 |
| | 3 | 43,660 | 53,436 | 55,620 |
| **System (Pss)** | 1 | 18,725 | 19,570 | 19,124 |
| | 2 | 18,192 | 19,075 | 19,079 |
| | 3 | 18,257 | 19,208 | 19,123 |

(`EGL mtrack` was byte-identical — 145,040KB — across all 9 snapshots; it did not move at all in
this scenario.)

### 10.4 Delta analysis ("immediately after scroll" minus "before opening Search")

| Category | Run 1 | Run 2 | Run 3 | **Median** |
|---|---|---|---|---|
| TOTAL PSS | +38,501 | +42,435 | +57,007 | **+42,435 KB (+41.4MB)** |
| Native Heap | +25,424 | +27,120 | +26,668 | **+26,668 KB (+26.0MB)** |
| Java/Dalvik Heap | +9,576 | +9,644 | +9,264 | **+9,576 KB (+9.4MB)** |
| Code | +12,476 | +14,420 | +14,484 | **+14,420 KB (+14.1MB)** |
| **Graphics** | **−23,748** | **−24,964** | **−4,120** | **−23,748 KB (−23.2MB)** |
| **GL mtrack** | **−23,748** | **−24,964** | **−4,120** | **−23,748 KB (−23.2MB)** |
| Private Other | +13,904 | +15,312 | +9,776 | **+13,904 KB (+13.6MB)** |
| System | +845 | +883 | +951 | **+883 KB (+0.9MB)** |

**The median TOTAL PSS increase across the 3 controlled runs is +42,435 KB ≈ +41.4MB — not
+266MB.** The original single-run figure did not reproduce under controlled conditions.

**Per instruction 10 ("do not infer that images are the cause unless the repeated evidence
supports it"): the repeated evidence does not support that inference.** In all 3 runs, the
Graphics category (which is where GPU-decoded image textures are accounted for — `Graphics` =
`EGL mtrack + GL mtrack` exactly, verified arithmetically from the raw dump) **decreased** after
the scroll, rather than increasing. The categories that did consistently and reproducibly increase
are **Native Heap** (+26.0MB median), **Code** (+14.1MB median), **Private Other** (+13.6MB
median), and **Java/Dalvik Heap** (+9.4MB median) — none of which is the GPU-texture/image-decode
category. Plausible, honest explanations for this pattern (not confirmed, offered as hypotheses
for a future investigation, not as findings):
- `Code` growing is consistent with JIT-compiling previously-unexecuted codepaths as scrolling
  constructs list items/widgets not yet built this session — an expected, generic Flutter/Dart
  cost of exercising more of the app, not specific to this card or its image.
- `Native Heap`/`Private Other` growth is consistent with general network-response buffers,
  plugin/platform-channel allocations, or `cached_network_image`'s on-disk cache
  (`libCachedImageData.db`, confirmed present via `dumpsys meminfo`'s DATABASES section) being
  read during the scroll — this is a real cost of fetching/caching property data and images, but
  it is not the same thing as uncapped *decode*-size texture memory, which is what the plan's
  Module 2 proposal specifically targets.
- Graphics *decreasing* during the scroll is plausibly explained by the controlled protocol's
  **8-swipe distance being within or close to `ListView.builder`'s initial `cacheExtent`**, i.e.
  many of the cards scrolled into view may have already been built (and their images already
  decoding) at the list's initial render, before any swipe occurred — meaning this specific,
  modest scroll distance may simply not be loading as many *new* images as originally assumed.
  A longer, further scroll (deeper into the 69-result list) was not tested in this validation pass
  and might show a different Graphics trend — **this has not been tested and is not claimed**.

### 10.5 Does memory drop after leaving Search, or remain retained? (instruction 8)

**Memory does not drop — it continues to climb** after leaving Search and waiting 30s, in all 3
runs (TOTAL PSS: Run 1 +188,710 KB, Run 2 +167,156 KB, Run 3 +203,759 KB further increase from the
"after scroll" point). **However, this is not attributable to Search retaining anything** — the
Graphics/GL mtrack category specifically continues climbing *during this 30-second Home-screen
dwell window* (median further increase of roughly +200,000 KB / +195MB in Graphics alone across
the three runs), which is after the user has already navigated away from Search back to Home.
This points to **Home's own ongoing activity during the 30s window**, not Search, as the better
explanation — specifically, Home's hero banner carousel auto-advances every 5 seconds
(`hero_banner_section.dart`, confirmed in the plan's Module 4 findings), so over a 30-second dwell
on Home, roughly 5–6 additional carousel images may be decoding that were not yet loaded at the
"after scroll" snapshot (which was taken while still on the Search screen, before Home's carousel
had a chance to advance further). **This was not independently isolated in this pass** (e.g., by
repeating the "wait 30s" step while remaining on a blank/neutral screen instead of Home) — it is
offered as a plausible, code-grounded explanation, not a confirmed finding. What *can* be stated
as measured fact: the 30s-after-leaving checkpoint in this protocol does not cleanly isolate
Search's own retained memory, because Home itself is actively memory-growing during that same
window.

### 10.6 Conclusion of this validation pass

1. The original +266MB PSS / +260MB Graphics single-run Search-scroll figure (§6.2) **is not
   reproducible** under a controlled, repeated protocol on the same device with the same scenario.
2. The validated, reproducible median increase for this exact scenario is **+41.4MB PSS**, and it
   is **not concentrated in Graphics/image-decode memory** — Graphics decreased in every run.
3. **No optimization is proposed as a result of this validation.** The plan's Module 2 image-
   decode-cap hypothesis for `PropertyCardSearchRow` remains a legitimate **static code-level
   candidate** (confirmed: no `memCacheWidth`/`memCacheHeight` set, §10.1) but this pass's memory
   evidence neither confirms nor rules it out as a *measurable* win — it simply shows that the
   particular +266MB figure used earlier to motivate urgency should not be cited, and that this
   specific controlled scenario (69 results, List view, 8-swipe scroll distance) does not
   reproduce a large Graphics-category increase on this device.
4. If the image-decode-cap experiment (Step B of the plan's revised first batch) is pursued later,
   its own before/after measurement should use this section's protocol (fixed process-restart,
   fixed gesture, 3 runs, full category breakdown) rather than a single run, and should not assume
   a large Graphics win going in — it should let the measurement answer that question.

---

## 11. Flutter DevTools Performance traces (6 scenarios × 3 controlled runs)

**This section supersedes the frame-time/jank-percentage "unavailable" limitation recorded in §7
and §8** — those were correct for the CLI-only (`dumpsys gfxinfo`) method used at the time, but
this pass obtained real frame-time, thread-attribution, and jank-cause data via Flutter DevTools'
Performance page, attached to the existing, already-installed profile build on device
`10BE6X22YE000Z7` via `flutter attach` (no rebuild, no reinstall, no data clear — confirmed via
unchanged `firstInstallTime`/`lastUpdateTime` throughout this entire pass). DevTools was driven
interactively: the user operated the Performance page's Record/Clear controls and reported back
screenshots of the resulting frame chart and Frame Analysis panel; all device gestures (scroll/type
sequences) were executed by this session via `adb shell input`, identically across all 3 repeats
of each scenario, per the task's requirement.

**Session note (transparency, not a methodology defect):** partway through Scenario 2, the
physical device disconnected from adb (a USB-level drop, confirmed via `adb devices` showing no
attached devices) and the live DevTools connection was lost. The device was reconnected by the
user, `adb devices` confirmed its return, and `flutter attach` was re-run to get a fresh DevTools
URL — the app itself was never stopped, reinstalled, or had its data cleared at any point
(`firstInstallTime`/`lastUpdateTime` confirmed unchanged before and after). One accidental
navigation also occurred (an early tap landed on "Post Property" instead of the intended target;
immediately reversed via back-navigation before any data entry) and a stray price filter got
applied to Search results mid-sequence (cleared before Run 2 to restore the ~69-result baseline
scenario) — both disclosed here rather than omitted.

**Metric availability, confirmed empirically in this pass:** UI-thread frame time, Raster-thread
frame time, and FPS average are reliably available in the main "Flutter frames" chart and its
hover tooltips. Per-frame Build/Layout/Paint/Raster phase breakdowns are available in the "Frame
Analysis" panel **only if a bar is clicked within a few seconds of that frame being rendered** —
DevTools discards the detailed timeline-event data for older frames ("timeline events occurred too
long ago"), so several clicks in this pass returned summary-only data (FPS average, bar coloring)
without the full phase breakdown. This is itself a real, useful methodological finding for any
future DevTools-based pass: **click immediately, not after discussing the screenshot.**

### 11.1 Results by scenario

| # | Scenario | Run 1 | Run 2 | Run 3 | Median FPS | Pattern |
|---|---|---|---|---|---|---|
| 1 | Home scroll (12 swipe pairs) | 27 FPS | 28 FPS | 28 FPS | **28** | Persistent — every run dominated by Shader-Compilation-colored frames, no warm-up fade across repeats |
| 2 | Search-results scroll (8 swipes, List view, ~67-69 results) | 46 FPS | 57 FPS | 55 FPS | **55** | Transient/front-loaded — heavy jank only on first encounter (Run 1), mostly clean after (Run 2 zero-jank; Run 3 janky for ~10 frames then clean) |
| 3 | Reels scroll (10 swipes) | 55 FPS | 54 FPS | 55 FPS | **55** | Persistent — DevTools issued an explicit system banner in Run 1: *"Shader compilation jank detected. 1 frame janked with a total of 67.6 ms spent in shader compilation."* |
| 4 | Post Property wizard: type into Property Headline field, no scrolling, no submission | 55 FPS | 57 FPS | 57 FPS | **57** | Persistent — confirms the jank is not scroll-specific; pure text entry on a static screen reproduces the same pattern every run |
| 5 | Feed scroll (8 swipes) | 59 FPS | 59 FPS | 59 FPS | **59** | Clean — "No suggestions for this frame - no jank detected" in Runs 1-2; Run 3 had one isolated, non-reproduced ~112.6ms **UI-thread** (not Raster) jank spike on a single frame, flagged separately below |
| 6 | Profile scroll + property-detail scroll (combined) | 50 FPS | 50 FPS | 50 FPS | **50** | Persistent — same Raster/Shader-Compilation pattern, concentrated more heavily in the property-detail portion of the combined gesture |

### 11.2 Per-frame breakdowns captured (where click timing allowed)

| Scenario / Run | Frame | Category (DevTools label) | Build | Layout | Paint | Raster |
|---|---|---|---|---|---|---|
| Home, Run 1 | 122868 | Raster Jank Detected | — | — | 2.8 ms | *(data not available this capture)* |
| Search, Run 2 | 144204 | **No jank detected** | 0.1 ms | 0.1 ms | — | 10.8 ms |
| Search, Run 3 | 144860 | Raster Jank Detected | 0.3 ms | — | 0.4 ms | 18.8 ms |
| Reels, Run 1 | (banner-level, not per-frame) | **Shader compilation jank detected — 67.6 ms total in shader compilation** | — | — | — | — |
| Post Property typing, Run 1 | 162419 | Raster Jank Detected | — | — | 1.1 ms | 21.9 ms |
| Post Property typing, Run 2 | 162919 | Raster Jank Detected | — | — | 0.8 ms | 19.0 ms |
| Post Property typing, Run 3 | 163385 | Raster Jank Detected | — | — | 0.8 ms | 22.9 ms |
| Feed, Run 1 | 168132 | **No jank detected** | — | 0.1 ms | 0.2 ms | 7.4 ms |
| Feed, Run 2 | 168795 | **No jank detected** | — | <0.1 ms | <0.1 ms | 9.3 ms |
| Feed, Run 3 | 169368 | **UI Jank Detected** (different category — see 11.4) | 0.1 ms | *(not shown)* | 0.2 ms | 9.9 ms (not the janky phase) |
| Profile+detail, Run 1 | 170109 | Raster Jank Detected | — | <0.1 ms | 0.1 ms | 20.1 ms |
| Profile+detail, Run 2 | 171046 | Raster Jank Detected | — | — | 0.7 ms | 28.2 ms |
| Profile+detail, Run 3 | 171910 | Raster Jank Detected | — | <0.1 ms | 0.1 ms | 20.1 ms |

**Every single sampled janky frame across every scenario shows the same shape: Build/Layout/Paint
(the Dart/UI-thread phases) at well under 3ms, with the entire frame-budget overrun concentrated in
Raster** (18-28ms, against a ~16.7ms/60fps budget on this device's active 60Hz display mode). This
is a consistent, cross-scenario, repeated-evidence pattern — not a one-off.

### 11.3 Cross-scenario synthesis — the dominant, reproducible bottleneck

**Reproducible bottleneck:** Raster-thread jank attributed by DevTools itself to **Shader
Compilation** (confirmed both by the bar-coloring legend category across every scenario, and
explicitly by name in Reels Run 1's system banner, which is DevTools' own programmatic diagnosis,
not an inference from this investigation). This reproduced in:
- Home: 3/3 runs, every run dominated by it, no fade.
- Reels: 3/3 runs, every run, with an explicit named confirmation.
- Post Property field typing: 3/3 runs — **important finding: this is not a scrolling-only
  phenomenon.** A static screen with a single text field, no list, no images in view, still
  produces the identical Raster/Shader-Compilation signature on every run.
- Profile + property-detail scroll: 3/3 runs.
- Search-results scroll: present and dominant in Run 1 (first encounter this session), then
  substantially faded (Run 2 fully clean) or partially faded (Run 3, janky only for the first
  portion of the scroll) — this is the clearest within-this-investigation evidence that the
  mechanism is a **one-time-per-shape/effect compilation cost**, not a sustained per-frame cost,
  consistent with Flutter's own documented shader-compilation-jank phenomenon.

**Thread / category attribution:** Raster thread (GPU-side rendering), not the Dart UI thread —
confirmed numerically in every per-frame breakdown captured (UI-thread phases consistently
<3ms; Raster consistently 18-28ms on janky frames). **Not memory-related** (this is a distinct
mechanism from §6-§10's PSS/Graphics memory findings — shader compilation is a CPU/GPU-pipeline
stall, not a memory-footprint issue, and the two should not be conflated). **Not network-wait
related** — all scenarios were interacting with already-loaded, already-cached content; no
loading spinners or network-dependent frames were the subject of any sampled janky frame.

**Non-reproducible observation (explicitly not elevated to a finding):** Feed, Run 3, frame
169368 — a single **"UI Jank Detected"** frame (DevTools' Dart/UI-thread category, distinct from
Raster Jank) with an unexplained ~112.6ms UI-thread cost not accounted for by the visible
Build (0.1ms) + Paint (0.2ms) breakdown (Layout was not shown in that capture). This did not occur
in Feed Run 1 or Run 2, and nothing of this kind occurred in any other scenario's 3 runs. Per the
task's instruction, this is recorded as a non-reproducible, unexplained single-occurrence
observation — **not** a confirmed bottleneck, and no action is proposed for it. It would need
independent reproduction (e.g., several more Feed runs, or `Enhance Tracing` → "Trace paints" as
DevTools itself suggested) before it could be elevated to a finding.

### 11.4 Does resolving this appear Flutter-only, or would it require backend work?

**Flutter-only.** Shader-compilation jank is a client-side Skia rendering-pipeline phenomenon —
it occurs because a given shape/paint-effect combination (rounded corners, shadows, clips,
gradients used throughout this app's cards) is being compiled into a GPU shader program for the
first time on this specific device/driver, the moment it's first drawn. It has no backend, query,
caching, or realtime-behavior dimension whatsoever. Flutter has an official, documented mitigation
for exactly this mechanism — **SkSL shader warm-up**: capturing the set of shaders a real profiling
run touches, bundling that capture as an asset, and having the engine pre-compile them at app
startup (before the user reaches the first affected screen), rather than compiling them on-demand
mid-scroll. Reference: https://docs.flutter.dev/perf/shader (the same link DevTools' own Reels-run
banner pointed to independently, in this investigation).

**Per the task's explicit instruction, this is reported as a well-evidenced, reproduced candidate
only — no code change is proposed or implemented in this pass.** Implementing SkSL warm-up would
require its own separate, explicit approval and its own implementation-safety process (capturing a
representative warm-up profile, bundling it, verifying it doesn't change any visual output, and
re-measuring with this same 3-run DevTools protocol to confirm the jank actually clears).

---

*This document records measurement and test characterization only. No performance optimization
has been implemented.*
