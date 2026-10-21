# PropCid Mobile — Final Implementation Contract

**Version 2** · 2026-08-04
Supersedes V1 (chat-provided). Governs Phases 10, 11 and 12.
Companion: `PROPCID_MASTER_IMPLEMENTATION_BLUEPRINT_V2.md`

> Phases 1A–9 are **closed**. This contract does not reopen them. Where V1 and
> the delivered code disagree, §F records the reconciliation.

---

## A. Backend — prohibited unless a phase explicitly requires it

### A.1 Standing prohibition

Backend functionality **must not be modified** unless a future phase explicitly
requires it *and* that requirement is approved in writing before work starts.
Absent such approval, the following are forbidden:

- Writing or editing any `.sql` under `supabase/migrations/`
- Modifying anything under `supabase/functions/`
- Altering any table, column, relationship, RLS policy, RPC or trigger
- Inventing a table, column or API shape
- Hardcoding real production data (names, emails, phones, listings, financial
  figures). Clearly-fake placeholders only — use `example.invalid` in tests
- Touching auth / session / RBAC: `auth_provider.dart`, `auth_service.dart`,
  `session_service.dart`, `rbac_service.dart`

### A.2 Verified compliance, Phases 1A–9

- `supabase/` — **zero changes** since the Phase 0 commit
- All six phase-added services are **write-free**
- The only Edge Function call is a read (`billing-history`)
- Column names were verified against `information_schema`, never inferred

### A.3 The one recorded exception

`auth_provider.dart` gained **+15 additive lines** (a cache of the `profiles`
row it already fetches, exposed as an unmodifiable getter, per blueprint §10).
Made during the Profile work, **before this contract governed the phases**. No
auth, session or RBAC behaviour changed. Recorded, accepted, not precedent.

### A.4 Reading production

MCP schema reads (`list_tables`, `information_schema`) are permitted and
encouraged — they are how column names get verified instead of guessed. They are
strictly read-only. No staging project exists (§D.2); this is the accepted
workaround.

### A.5 Never-modify list (unchanged)

Everything under `supabase/` · `auth_provider.dart` · `auth_service.dart` ·
`session_service.dart` · `rbac_service.dart` · `lib/screens/reels/*`,
`reels_provider.dart`, `reels_service.dart` (load-bearing Android video-buffer
workaround) · **every screen not named in the active phase**.

> V1 also listed `lib/screens/profile/*`, `lib/screens/dashboard/*` and
> `lib/screens/articles/*`. Those were superseded in-flight by explicit
> instructions (the dashboard overhaul; the P5/P6 promotion permission). V2
> narrows the list to what is actually inviolable and records the rest in §F.

---

## B. Sources of truth

| Role | Source | Precedence rule |
|---|---|---|
| Functional | React Portal | Behaviour, queries, business rules. React beats any document. |
| Visual | Approved mobile designs | Layout, spacing, type, colour. Design beats an existing Flutter primitive. |
| Target | Flutter app | Owns architecture, navigation, state. |

**When React and the design conflict** (e.g. plan taxonomies, §E-3): implement
the design's visuals over React's data contract, and escalate — do not silently
pick one.

**When React hardcodes a value with no query behind it:** do not reproduce the
figure. Render `—` and keep the row. (Established Phase 6; now binding.)

---

## C. Implementation rules

### C.1 Reuse first
Before creating any widget, provider, service or model, search for an existing
one. Extend additively with defaulted parameters rather than forking. Prefer
promotion (§C.2) over duplication.

### C.2 Promotion protocol
When a widget in a screen folder is needed by another module:
1. move the class **verbatim**; adjust import depth only;
2. leave a one-line `export` shim at the old path;
3. prove type identity in a test (`expect(shared.X, legacy.X)`);
4. delete the private original if one existed — never leave two.

### C.3 No duplicate implementations
Two classes doing the same job is a defect. Coincidental *private* name
collisions between genuinely different widgets are acceptable.

### C.4 Architecture
`Widget → Provider → Service → Supabase`. Provider package only. Screen-scoped
providers unless genuinely global. Every async screen splits into
`XScreen` (provider host) + `XBody` (provider-free, testable).

### C.5 Deferred load (mandatory)
Use `DeferredSectionLoader`, or reproduce it exactly: resolve `userId`, guard
re-loads, defer to `addPostFrameCallback`, re-check `mounted`. Never call a
provider's `load()` directly from `didChangeDependencies`.

### C.6 Honest states (mandatory)
- Failure renders `—` or an explicit error — never `0`, never an empty list
- "Couldn't load X" ≠ "You have no X"
- Never assert account state that has not been read
- Inert controls must look inert and state why

### C.7 No new dependencies without written approval.

### C.8 Money
Confirm the unit per table before formatting. Billing and social-ads store
integer minor units; network tables store `numeric` rupees. Pin it with a test.

### C.9 Secrets
Never select encrypted/token columns. Social reads go through
`social_accounts_safe`.

### C.10 Placeholders
A control that cannot act routes to `ComingSoonScreen` via
`openSectionPlaceholder`. Never a dead button.

---

## D. Verification gates — every phase

### D.1 Required, in order
1. `flutter analyze` — **zero new** issues vs the prior phase's baseline, proven
   by a normalized `(severity|file|rule)` diff that ignores line:col. Comparing
   totals is not sufficient.
2. `flutter test` — all green except the documented baseline failure.
3. `flutter build apk --debug` — succeeds.
4. Written regression checklist: footprint, never-modify areas, route count,
   write-check grep, prior-phase suites.
5. Every new screen probed for overflow at **320×568** with maximal data.

### D.2 Staging
Validation should run against a staging project with fake accounts. **None
exists.** Until one does, verification is read-only against production (§A.4).
This is a known, accepted gap.

### D.3 Superseded tests
When a phase intentionally changes behaviour a prior test asserted, **update the
assertion to the new contract with a comment recording why** — never delete it,
never leave it failing. Precedent: the Social hub (P8) and Network hub (P9)
"opens the placeholder" tests became "navigates to its real route".

---

## E. Open decisions — must be resolved before the phase they block

| # | Decision | Blocks |
|---|---|---|
| 1 | Razorpay mobile strategy | Phase 10 |
| 2 | Meta OAuth mobile redirect strategy | Phase 10 |
| 3 | Plan taxonomy conflict — design ladder vs `planConfig.ts`; `subscriptions.plan` stores React's ids | Upgrade + Features accuracy |
| 4 | Mobile design for Phase 12, **or** written authorisation to derive from `UserProfile.tsx` in the existing design system | Phase 12 |
| 5 | Confirm RLS permits Phase 12's membership writes. **If it does not, Phase 12 is blocked** — §A forbids changing RLS | Phase 12 |
| 6 | Phase 12 search entry point | Phase 12 |
| 7 | Enable `savePreferences` writes | Future |
| 8 | Staging Supabase project | Validation confidence |

Decisions 1, 2, 4, 5 are **hard blocks**. 3, 6, 7, 8 are quality/scope choices.

---

## F. V1 → V2 reconciliation

Corrections found during implementation. V2 is authoritative.

| V1 said | Reality | Resolution |
|---|---|---|
| 7 `comingSoon()` calls in `workspace_destinations.dart` | 4 in `workspace_drawer.dart`, 3 in `more_bottom_sheet.dart` | Corrected |
| Network has no Edge Functions | It has `assign-lead-automatically`, `convert-inquiry-to-network-lead` | Corrected |
| Never-modify included profile / dashboard / articles screens | Superseded in-flight by explicit instructions | §A.5 narrowed |
| Silent on the load-lifecycle hazard | Caused three crashes before the pattern was found | Blueprint §1.1; Contract §C.5 |
| Silent on money units | Three domains, two conventions | §C.8 |
| Silent on the two follower metrics | Profile uses `builder_networks`; Audience uses `followers` — both match React | Blueprint §2.5 |
| Silent on encrypted token columns | `social_accounts_safe` exists for this reason | §C.9 |
| No Global Network Search phase | Present in React, absent from design and app | Phase 12 |

### Assumption corrected mid-project
Phase 3's first attempt assumed the design's Audience/Analytics metrics had no
backing data. They all exist in React `features/analytics/*`. The UI was rejected
and rebuilt. **Lesson, now §B:** verify against React before concluding data
does not exist.

---

## G. Scope of this contract

Governs **Phase 10, Phase 11, Phase 12** only. Phases 1A–9 are closed; their
delivered behaviour is the new baseline. Any change to shipped behaviour is a new
phase with its own approval, not an amendment here.

**Phase 10 carries a heightened standard.** It is the first phase to move money
and the first to write to billing tables. It requires its own risk review beyond
§D, including explicit handling of payment failure, partial state and refund
correctness. `flutter analyze` passing is not sufficient evidence for that phase.
