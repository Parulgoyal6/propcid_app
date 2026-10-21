# Release Safety

Current release-critical configuration, verified from source on 2026-09-26. No secret values (passwords, keys, tokens) are recorded anywhere in this file — only variable/property NAMES, file existence, and behavior.

## Package / Application Identity

| Platform | Value | Source |
|---|---|---|
| Android `applicationId` / `namespace` | `com.propcid.app` | `android/app/build.gradle.kts:47,61` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.example.propcidApp` — **still the Flutter-generated placeholder** | `ios/Runner.xcodeproj/project.pbxproj:376,556,579` |

**⚠️ Known gap**: the iOS bundle ID does not match the Android `applicationId` and is still the default Flutter placeholder. `ios/Runner/Runner.entitlements`'s own comment confirms this is a known issue blocking Universal Links (Associated Domains capability can't be properly configured against a placeholder bundle ID). Do not "fix" this without explicit instruction — it may be intentionally deferred until iOS App Store listing setup. See `KNOWN_ISSUES.md` KI-14.

## Version / Build Number Source

`pubspec.yaml:19` → `version: 1.0.0+5` (build-name `1.0.0`, build-number `5` — bumped from `+4` on 2026-09-30 alongside the app-icon update below). Both platforms derive from this single source:
- Android: `versionCode = flutter.versionCode`, `versionName = flutter.versionName` (`android/app/build.gradle.kts:64-65`) — not hardcoded in Gradle.
- iOS: `CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"` (`project.pbxproj:369`).

## App Icon

`pubspec.yaml`'s `flutter_launcher_icons` config (updated 2026-09-30, commit `3238b6e`) now generates a full Android 8+ adaptive icon (`adaptive_icon_foreground`/`_background`/`_monochrome`, `adaptive_icon_foreground_inset: 0`, source art under `assets/branding/`) in addition to the legacy square `image_path` icon. No release-safety implication beyond the version bump above — recorded here only because it's an icon/build-config change, not because it changes signing or identity.

## Android Signing Structure (no secret values)

- `android/key.properties` is a **required, gitignored, machine-local release-signing input** (confirmed gitignored via `.gitignore:49` and untracked via `git ls-files`) — not a permanent property of this repository. It is expected to be present only on an authorized release-build machine; its presence and completeness must be checked at release time, not assumed from this document. When present, it holds 4 properties by convention: `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (property NAMES only — no value has ever been read into this or any other document). `android/key.properties.example` is a committed, tracked template with no real values.
- `android/app/build.gradle.kts:10-18` loads `key.properties` if present; does not throw if absent (debug builds work without it).
- `signingConfigs { create("release") { ... } }` (lines 68-83) pulls `keyAlias`/`keyPassword`/`storeFile`/`storePassword` from the loaded properties, each defaulting to `null` if missing.
- **Release builds are fail-closed by design**: `gradle.taskGraph.whenReady` (lines 99-120) fails any task with "Release" in its name if `key.properties` doesn't exist, any required property is blank, or the resolved keystore file doesn't exist on disk. This deliberately prevents a release build from ever silently falling back to debug signing. Debug/profile task graphs are unaffected. **Never relax this check** — see `DECISIONS.md`.
- `buildTypes { release { ... } }`: `isMinifyEnabled = false`, `isShrinkResources = false` (lines 85-96) — no code shrinking/obfuscation is currently applied to release builds.

## Android SDK Versions

`compileSdk = 36`, `targetSdk = 36` (`build.gradle.kts:48,63`). `minSdk = flutter.minSdkVersion` — **not pinned in this repo**, inherited from whatever Flutter SDK version builds the app; the effective numeric value is not independently verifiable from this repository alone. Java/Kotlin target: version 17.

## Android Manifest — Permissions

`android/app/src/main/AndroidManifest.xml`: `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (geolocator "Near Me"), `RECORD_AUDIO` (voice search/speech_to_text), `WRITE_EXTERNAL_STORAGE` scoped to `maxSdkVersion="29"` only.

## Client-Side Secret Handling

The Flutter app bundles `.env` as an application asset (`pubspec.yaml:137`) — any value in it, in source, in a native manifest/plist, or in a `--dart-define`, ships inside the app package and must be treated as recoverable by an end user. Full rule and examples of what must stay server-side in `HIGH_RISK_AREAS.md` → "Client-Side Secrets / `.env` Bundling". The one confirmed concrete instance of this risk materializing in this repo today is the plaintext Google Maps key below.

## ⚠️ Android Manifest — Plaintext API Key

`com.google.android.geo.API_KEY` (a Google Maps API key) is hardcoded in **plaintext** directly in `AndroidManifest.xml` (lines 25-27). The value was not reproduced in this document. Whether it's restricted (by package name/SHA-1 fingerprint, API scope) in the Google Cloud Console cannot be determined from this repository. Flag as a release-security item worth reviewing with whoever owns the Google Cloud project — see `KNOWN_ISSUES.md` KI-15.

## Deep Links / Universal Links

| Scheme/domain | Purpose | Notes |
|---|---|---|
| `com.propcid.app://login-callback` | Email magic-link / Google OAuth callback | Android custom-scheme intent filter |
| `https://propcid.in/login-callback*` (autoVerify) | Google Sign-In App Link | Code comment states this depends on `https://propcid.in/.well-known/assetlinks.json` |
| `propcid://reset-password` | Password reset | |
| `propcid://meta-callback` | Meta/Facebook OAuth callback | Redirect URI must also be registered in the Facebook Developer dashboard (outside this repo) |
| `https://propcid.com/accept-invite*` (autoVerify) | Team invite | **Code comment explicitly states `https://propcid.com/.well-known/assetlinks.json` does NOT yet list this app's real applicationId + signing cert fingerprint** — Android will accept the intent filter but not grant verified-link status yet; falls back to a disambiguation sheet/browser |

iOS side: `Info.plist` declares both custom URL schemes (`com.propcid.app`, `propcid`). `Runner.entitlements` declares `applinks:propcid.com` for the team-invite Universal Link, but its own inline comment states this alone is insufficient — it also needs an Associated Domains capability against the app's *real* (non-placeholder) bundle ID plus a matching `apple-app-site-association` file, neither of which is confirmed in place. No Apple Team ID is committed to `project.pbxproj` (no `DEVELOPMENT_TEAM` key found).

**Do not assume these deep links are fully verified/live in production** — the code's own comments describe partial setup for the `propcid.com`/`propcid.in` domains.

## iOS Release Config

- `IPHONEOS_DEPLOYMENT_TARGET = 13.0`.
- `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"`.
- `CODE_SIGN_STYLE = Automatic` was confirmed only on the `RunnerTests` target, not explicitly found on the main `Runner` target in the sections read — not fully confirmed either way.
- **No `ios/Podfile` was found** — unclear whether CocoaPods was intentionally removed (e.g. Swift Package Manager used instead) or the checkout is incomplete. Verify before assuming CocoaPods is or isn't in use.

## iOS Permission Usage Descriptions

`NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSSpeechRecognitionUsageDescription` — all present with descriptive copy in `Info.plist`. `LSApplicationQueriesSchemes` declares `tez`/`phonepe`/`paytmmp`/`credpay` (UPI app detection for Razorpay checkout).

## Feature Flags at Release

Two committed build-config JSON files select `FEATURE_SUBSCRIPTIONS` / `FEATURE_PAID_COLLABORATIONS` / `FEATURE_META_PUBLISHING` / `FEATURE_VOICE_ASSISTANT` (4th flag added 2026-09-30) at build time via `--dart-define-from-file`:
- `config/features/play_release.json` — all four `false` (the Play Store launch config).
- `config/features/full_development.json` — all four `true` (local/dev).

A build invoked without `--dart-define-from-file` at all gets the code's `defaultValue: false` for every flag — i.e. behaves like the release profile, not dev. Neither JSON file holds a secret (four booleans each) — safe to commit, and both already are. `FEATURE_VOICE_ASSISTANT` disabled means the floating AI orb, the voice-agent provider, and all voice-agent tool registration are skipped app-wide (not just hidden) — see `CURRENT_ARCHITECTURE.md`/`DECISIONS.md`.

**Never flip these defaults or the release JSON's values without an explicit, separate instruction.** Substantial real client-side implementations exist behind these flags (screens, providers, services, Razorpay/Meta OAuth wiring) — this is not placeholder UI. Enabling them exposes user-facing flows and server integrations whose server-side completeness/correctness cannot be independently verified from this repository (the Edge Function source is absent), so release flag changes require explicit verification before shipping, not an assumption that "implemented" means "production-ready end to end." See `DECISIONS.md` and `HIGH_RISK_AREAS.md`.

## Renderer / Compatibility Workaround

`AndroidManifest.xml` sets `io.flutter.embedding.android.EnableImpeller = false` (Skia forced instead of Impeller) — code comment cites video texture corruption observed on some Vivo/MediaTek devices. Do not "modernize" this to Impeller without re-testing on the affected device classes.

## Pre-Release Verification Checklist (compiled from the above — not exhaustive, use judgment)

- [ ] Confirm which `SUPABASE_URL`/`SUPABASE_ANON_KEY` pair in `.env` is intended to be active before any release build (multiple candidates exist, some commented out — see `API_CONTRACTS.md`).
- [ ] Confirm `android/key.properties` is present on the build machine and complete — it is machine-local and gitignored, never assume it's there (Gradle will refuse a Release-named task otherwise — this is expected behavior, not a bug to work around).
- [ ] Confirm the intended `LaunchFeatures` config file (`play_release.json` vs `full_development.json`) is the one actually passed to `--dart-define-from-file`.
- [ ] Re-run `flutter analyze`/`flutter test` fresh rather than trusting the 2026-09-23 snapshot logs in the repo root (see `TEST_MAP.md`/`KNOWN_ISSUES.md` KI-1/KI-2).
- [ ] If touching iOS release config: be aware the bundle ID is still the Flutter placeholder — confirm with the team whether that's expected before this release or a genuine blocker.
- [ ] Do not commit any new plaintext API key to a manifest/plist without confirming it's restricted at the provider (Google Cloud Console, etc.).
