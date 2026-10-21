# Blueprint Addendum — Phase 12: Global Network Search & Public Profile

**Status:** Specified, not started
**Added:** 2026-08-04, after the Phase 9 project audit
**Amends:** PROPCID Master Implementation Blueprint (additive only)

> **This addendum does not modify any existing phase.** Phases 1A–9 are delivered
> and approved as written. Phase 10 (Transactional flows) and Phase 11 (Drift
> cleanup) keep their existing meaning and numbering. This is a new, separate
> phase appended to the plan.

---

## Why this phase exists

The Phase 9 audit confirmed the mobile app has no equivalent of the React
portal's **Global Network Search** flow:

> search profiles → open public profile → Join Network → Message

Phase 9 delivered *My Networks*, which ports `NetworkMemberships.tsx` — the list
of connections the user **already has**. That is the back half of networking.
The discovery half — finding a person you are not yet connected to, viewing
their public profile, requesting to join their network, and messaging them — was
never in scope, because the Claude Design contains no screens for it.

Verified absence at time of writing:

| Source | Present? | Evidence |
|---|---|---|
| React Portal | **Yes** | `SearchModal.tsx`, `UserProfile.tsx` (2,033 lines) |
| Claude Design | **No** | No `sc-if` screen for user search or public profile; 7 keyword probes returned 0 |
| Master Blueprint | **No** | §9 scoped Network to the accepted-connection count only |
| Final Contract | **No** | Phases 5–9 name Articles, Network/Social/Upgrade routing, Subscription, Social leaves, Network leaves |
| Flutter app | **No** | `profiles_public` is read for messaging recipients and project tagging only |

---

## Scope

Four capabilities, in dependency order.

### 12.1 — People search
Extend global search to match people, as `SearchModal.tsx` does.

- Source: `supabase.from("profiles_public").or(display_name.ilike, company_name.ilike, bio.ilike).limit(5)`
- Read-only.

### 12.2 — Public profile screen
Port `pages/UserProfile.tsx` to mobile.

- Header: avatar, display name, role badge, company, bio, verification
- Counters: network connections (`builder_networks`, accepted, either side)
- Tabs: **Properties** | **Networks** (React's `activeTab` values)
- Read-only.

### 12.3 — Join Network
The relationship state machine from `UserProfile.tsx`.

| State | Meaning | Control |
|---|---|---|
| `none` | no relationship | **Join Network** |
| `pending_sent` | you requested | **Cancel request** |
| `pending_received` | they invited you | **Accept** / **Decline** |
| `connected` | accepted both ways | **Connected** (inert) + Message |

Resolution order (`UserProfile.tsx:264-307`): read `builder_networks` first; if
absent, read `builder_network_invitations` for a pending **or** accepted row, and
disambiguate `pending_sent` vs `pending_received` by comparing `builder_id`
against the current user.

**This is the first write surface since Phase 4.** Writes required:
- Join → `insert` into `builder_network_invitations` (`UserProfile.tsx:634`)
- Accept → transition to `connected` (`:720`), consistent with
  `NetworkMemberships.tsx:186`'s `upsert` onto `builder_networks`
  with `onConflict: 'builder_id,member_id'`
- Cancel / Decline → back to `none` (`:671`)

### 12.4 — Message
Open a thread with the profile owner. **Already available** — Phase 4 shipped
`MessagingService.startConversation(withUserId)` over the `start_conversation`
RPC. This is wiring only.

---

## Non-negotiable: contact-detail gating

`UserProfile.tsx:2024-2025` exposes `phone` and `email` **only** when
`networkStatus === "connected"` or the viewer is the profile owner.

This is a privacy rule, not a display preference. The mobile implementation must
reproduce it exactly, and it must be covered by an explicit test that a
non-connected viewer never receives contact details. Prefer enforcing it at the
query layer (do not select the columns) over hiding them in the widget tree.

---

## Reuse inventory

Phases 1–9 already provide most of the parts. Build nothing that exists.

| Need | Reuse |
|---|---|
| Screen chrome | `NetworkScreenShell`, `DashboardHeaderBar` |
| Section state | `AsyncSection<T>`, `DeferredSectionLoader` |
| Profile/Networks tabs | `SegmentedTabPill` |
| Result rows | `ManageListTile`, `NetworkStatusPill`, `NetworkDetailRow` |
| Empty / error states | `EmptyStateView` |
| Buttons | `AppActionButton` (`solid` / `outline` / `danger`) |
| Search field | the pattern in `SocialLeadsBody` / `new_chat_sheet.dart` |
| Network reads | extend `NetworkService` (as Phases 6 and 9 did) |
| Message action | `MessagingService.startConversation` — no new code |

**Do not reuse `MessagingService.searchRecipients` verbatim.** It queries
`profiles` (not `profiles_public`), matches `display_name` only, and applies
`approval_status`/`is_blocked` filters. React's global search uses the public
view across three fields. Treat it as a reference, and consider consolidating the
two search paths as part of this phase rather than adding a third.

---

## Out of scope

- Editing another user's profile (never permitted)
- Following/followers — the `followers` table remains unused, per the standing
  decision to keep using accepted `builder_networks`
- Property/project search — already delivered
- Bulk invitations — `BuilderNetworkInvitations.tsx` is a separate surface

---

## Open decisions (must be resolved before implementation)

1. **No design exists.** This is the first phase without a Claude Design
   reference. Either (a) commission mobile designs for people-search and public
   profile, or (b) authorise deriving them from `UserProfile.tsx`'s layout
   rendered in the established mobile design system. **(b) is a deviation from
   the standing rule that the design is the visual source of truth and needs
   explicit sign-off.**
2. **Writes resume.** Phases 5–9 were strictly read-only. This phase performs
   membership writes. Confirm that is intended, and that the existing RLS on
   `builder_networks` / `builder_network_invitations` is sufficient — the
   contract forbids modifying RLS, so if current policies do not permit these
   inserts from the app, the phase is blocked pending a backend decision that
   sits outside this workstream.
3. **Search entry point.** React exposes people search inside a global
   `SearchModal` alongside properties and projects. Mobile has a property-focused
   search screen. Decide: add a People section to existing search, or a dedicated
   Network ▸ Find People entry from the Network hub.
4. **Deep links.** React serves six URL shapes for a public profile. Decide
   whether mobile needs deep-link parity (share/QR already generate profile
   links — see `profile_link.dart`).

---

## Acceptance criteria

Same gates as every prior phase:

- `flutter analyze` — zero new issues vs the Phase 11 baseline
- `flutter test` — all green except the known `widget_test.dart` baseline
- Debug APK builds
- No Supabase schema, SQL, RLS, Edge Function, auth or RBAC change
- No overflow at 320×568 on every new screen
- Explicit test: a non-connected viewer never receives phone or email
- Explicit test: all four network states render their correct control
- No duplicate search implementation left behind (see reuse note above)

---

## Sequencing

Phase 12 is **not blocked** by Razorpay or Meta OAuth, unlike Phase 10. The
number is an identifier, not a priority: if you want this before the
transactional work, it can run immediately once the four decisions above are
settled. Its only hard dependency is Phase 4 (messaging), which is delivered.
