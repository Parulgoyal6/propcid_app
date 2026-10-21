# Phase 1 · Stage 2A Impact Report — Public Profile from the Chat Thread header

**Date:** 2026-08-05
**Phase class:** 🟢 FE-ONLY (additive)
**Risk:** Low–Medium — two existing files, additive only
**Status:** complete, verified, awaiting approval

Scope as approved: wire the Public Profile from the Chat Thread header **only**. Search, Property
Details and the Messages list interaction are untouched. Group/channel chats unchanged.

---

## 1 · Files created

**None.**

## 2 · Files modified — 2

### 2.1 `lib/screens/messaging/chat_thread_screen.dart` — 5 hunks, all additive

| # | Change |
|---|---|
| a | `+ import '../../core/constants/app_constants.dart';` (first import, alphabetical) |
| b | `ChatThreadScreen`: `+ final String? participantUserId;` and `this.participantUserId` on the constructor — **optional, null default** |
| c | `ChatThreadScreen.build`: passes it to `_ChatThreadView`, nulling it when it equals the signed-in user |
| d | `_ChatThreadView`: `+ final String? participantUserId;` + constructor param; passes it to `_Header` |
| e | `_Header`: `+ final String? participantUserId;` + constructor param, `+ _openProfile()`, `+ _maybeTappable()`, and those two wrappers applied to the avatar and the title column |

**Pre-edit state of the header's tap surface** — the avatar and title were **inert**; the only
gesture in `_Header` was the back button:

```dart
              const SizedBox(width: 12),
              ChatAvatar(
                avatarUrl: avatarUrl,
                initials: initials,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
```

So this **adds** a gesture where none existed. No existing gesture was re-pointed (R19.1).

### 2.2 `lib/screens/messaging/messages_list_screen.dart` — 2 hunks

One line added to each of the two 1:1 `ChatThreadScreen` call sites:

- `_startNewChat` → `participantUserId: recipient.userId,`
- `_openConversation` → `participantUserId: conversation.otherParticipant?.userId,`

**`_openChannel` is deliberately untouched** — it passes nothing, so a channel thread's header
stays inert. Verified by reading it: `ChatThreadKind.channel`, `channel.name`, `channel.initials`,
no participant.

## 3 · How each of your constraints is met

| Constraint | How |
|---|---|
| Preserve all existing gestures | The back button is untouched. The avatar and title had **no** gesture; one was added. Nothing was re-pointed. |
| Preserve Hero animations | **No Hero was added.** See §5.1 — this is a deliberate omission, not an oversight. |
| Preserve navigation arguments | `participantUserId` is optional with a null default. Every existing caller compiles unchanged and behaves identically. `_openChannel` passes nothing. |
| Preserve business logic | No provider, service, query or message-loading path touched. `ChatThreadProvider`, `MessagingService` and `MessagingProvider` are untouched. |
| Only new behaviour = opening PublicProfileScreen | The only added code paths are the tap handler and the optional parameter that feeds it. |
| Opens only when `participantUserId` exists | `_maybeTappable` returns the child **unwrapped** when it is null or empty — no `GestureDetector` is constructed at all, so the null case is structurally identical to the original. |
| Group/channel unchanged | `_openChannel` passes no participant → header inert. |

Two guards beyond what was asked:

- **Self-thread guard** — if `participantUserId == currentUserId`, `build` nulls it, so a thread
  with yourself never offers a profile tap.
- **Empty-string guard** — a blank id is treated as absent, so a malformed row cannot push a
  profile screen that would immediately show "Profile not available".

## 4 · Layout safety

The `Row`'s structure is unchanged. Specifically, `_maybeTappable` wraps the **child of**
`Expanded`, not the `Expanded` itself, so the Row's flex distribution is byte-identical. The
avatar wrapper adds no size: `GestureDetector` is a single-child layout-transparent widget.

## 5 · Deviations

### 5.1 No Hero flight — deliberate
`PublicProfileScreen` accepts `avatarHeroTag`, and the thread header's avatar **is** unique on
screen, so a Hero would be legal under R19.4. It was still omitted:

1. It would require wrapping the existing `ChatAvatar` in a `Hero`, changing existing render
   structure for a purely decorative gain.
2. The flight is visually awkward: a 38 dp flat circle into an 88 dp circle carrying a 4 dp ring
   and a verified badge.

Adding none is the safest reading of "preserve Hero animations". It can be added later once the
screen has been seen on a device.

### 5.2 No automated test — and why
Stage 2A has **no test coverage**, which I want to state plainly rather than imply otherwise.

`ChatThreadScreen.build` early-returns a spinner when `AuthProvider.userId` is null:

```dart
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      return const Scaffold(... CircularProgressIndicator());
    }
```

`userId` is only populated by a real Supabase session, `AuthProvider` exposes no setter and no
injection seam, and giving it one would modify an existing file outside the approved scope. So the
header cannot be rendered in a widget test without changing production code.

**This makes Stage 2A the first change in this workstream verified only by inspection and by
`flutter analyze`.** It needs a device pass — see §8.

## 6 · Backend interaction

**None.** No query, RPC, table or bucket is touched. The tap issues a `Navigator.pushNamed` to an
already-registered route.

## 7 · Verification

| Gate | Baseline | Stage 1 | Stage 2A | Result |
|---|---|---|---|---|
| `flutter analyze` | 447 (0 err) | 447 | **447** | ✅ 0 new; **no issues in either edited file** |
| `flutter test` | 540 / 1 | 629 / 1 | **629 / 1** | ✅ no new failures (no tests added — §5.2) |
| `flutter build apk --debug` | — | ✓ | **✓ built** | ✅ PASS |
| `git status --short` | 69 M | 69 M | **69 M, no new entries** | ✅ both files were already `M`; nothing new appeared |

### Regression checklist — §6 Messages

| Item | Result |
|---|---|
| 6.1 conversation list, unread counts | ✅ untouched |
| 6.2 1:1 thread send/receive | ✅ no provider/service change |
| 6.3 channel thread | ✅ `_openChannel` untouched; header inert |
| 6.4 realtime arrival | ✅ untouched |
| 6.5 Chats/Channels tabs | ✅ untouched |
| 6.6 thread opens with `{userId}` | ✅ both call sites still pass their existing args |
| **6.7 thread header layout/actions preserved** | ✅ back button untouched; Row flex unchanged; verified by inspection — **not** by device (§5.2) |
| §14.1–14.3 routing | ✅ route was registered in Stage 1; no route table change here |
| §16.1–16.3, 16.9, 16.10, 16.12 | ✅ |

## 8 · Known issues / follow-ups

| # | Item |
|---|---|
| 1 | **Not verified on a device.** Both the Public Profile screen (Stage 1) and this tap are now reachable but unseen. This is the single highest-value next action. |
| 2 | No Hero flight (§5.1) — optional polish |
| 3 | No automated coverage (§5.2) — would need an `AuthProvider` seam, out of scope |
| 4 | Still no safety commit; rollback remains file-level |

## 9 · Rollback

No files to delete. Remove seven additive hunks:

**`chat_thread_screen.dart`** — the `app_constants` import; the `participantUserId` field +
constructor param on `ChatThreadScreen`, `_ChatThreadView` and `_Header`; the argument passed in
`ChatThreadScreen.build` and in the `_Header(...)` call; `_openProfile` and `_maybeTappable`; and
the two wrappers around `ChatAvatar` and the title `Column` — restoring the block quoted verbatim
in §2.1.

**`messages_list_screen.dart`** — the two `participantUserId:` lines.

**Do not use git**: both files were already dirty before this phase.

## 10 · Approval requested

Stage 2A is complete. **Stopping — no further entry point will be wired until the audit below is
approved.**

The requested audit is delivered as `docs/PROFILE_ENTRY_POINT_AUDIT.md`. Its headline: of the
16 surfaces that display a user, **one** more is safe to wire without a UX decision, and it is a
file I already own. Everything else needs either a UX decision from you, a model/query change, or
new UI.
