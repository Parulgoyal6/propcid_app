# People Search — Portal Reference, Flutter Gap Analysis & Implementation Plan

Functional reference: the React portal at `c:\Users\USER\Desktop\Flutter\propcid`.
Nothing in this document proposes a change to Supabase schema, SQL, RLS, RPCs or
Edge Functions. Every query below already exists in the portal.

---

## 1. Portal search flow — every surface that searches people

The portal has **six** distinct people-search implementations. They do not agree
with each other. This matters: "reproduce the portal" requires choosing which one
is the reference, so all six are documented.

| # | Surface | File | Table | Roles | Row filters | Text match | Order | Limit |
|---|---------|------|-------|-------|-------------|-----------|-------|-------|
| 1 | Global search modal — **People** section | `features/search/SearchModal.tsx:112-119` | `profiles_public` | all | *(view)* approved + not blocked | `or(display_name.ilike, company_name.ilike, bio.ilike)` | none | 5 |
| 2 | Search page — "People and companies" block | `pages/Search.tsx:1264-1270` | `profiles_public` | all | *(view)* approved + not blocked | `or(display_name.ilike, company_name.ilike)` | none | 10 |
| 3 | Brokers directory | `pages/BrokersList.tsx:53-59` | `profiles` | `broker`, `agent`, `influencer` | `approval_status='approved'` only | **client-side** `String.includes` on display_name / company_name | none | **none — fetches every row** |
| 4 | Builders directory | `pages/BuildersList.tsx:49-54` | `profiles` | `builder`, `developer` | `approval_status='approved'` only | client-side | none | none |
| 5 | Influencers directory | `pages/InfluencersList.tsx:41-44` | `profiles` | `influencer` | `approval_status='approved'` only | client-side | none | none |
| 6 | People pickers (new chat, user selector) | `features/messaging/NewChatModal.tsx:49-55`, `features/profile/UserSelector.tsx:49-55` | `profiles` | all | `approval_status='approved'` **and** `is_blocked=false` **and** `user_id != self` | `ilike('display_name')` only | none | 10 |

A seventh path returns people but is **not** a people search: the `global_search`
RPC behind the autocomplete dropdown (§1.4).

### 1.1 `profiles_public` — the view surfaces 1 and 2 use

`supabase/migrations/20260421110000_add_user_presence.sql:8-26`:

```sql
CREATE VIEW public.profiles_public AS
SELECT user_id, display_name, avatar_url, user_type, company_name,
       years_experience, specialization, business_hours, website_url,
       social_media, created_at, bio, last_seen_at, is_online
FROM public.profiles
WHERE COALESCE(is_blocked, false) = false
  AND approval_status = 'approved';
GRANT SELECT ON public.profiles_public TO anon, authenticated;
```

The row filter is **inside the view**, which is why surfaces 1 and 2 apply no
filters of their own. The view exposes **14 columns**, and critically **does not
expose** `username`, `work_city`, `city`, `rera_number`, `verification_status`,
`years_of_experience` or `agency_name`.

`security_invoker` was set to `true` on an earlier revision of this view
(`20250825133419:6`), but this migration does `DROP VIEW` + `CREATE VIEW`, which
resets view options — so the deployed view runs with owner privileges and is
readable regardless of the `anon` column grant on the base table.

### 1.2 RLS on `profiles` — two permissive SELECT policies, OR'd

| Policy | Roles | `USING` |
|---|---|---|
| `Authenticated users can view profiles` (`20250806153811:53`) | `authenticated` | `auth.uid() IS NOT NULL` |
| `Anyone can view approved profiles basic info` (`20251208172553:2`) | *(all)* | `approval_status='approved' AND COALESCE(is_blocked,false)=false` |

**A signed-in user can read every profile row, including pending, rejected and
blocked ones.** That is why the directory pages have to pass
`approval_status='approved'` explicitly — and why the three that omit
`is_blocked` leak blocked users (§6, D1).

### 1.3 Column privileges

`20270311000000_profiles_hide_contact_from_anon.sql` revokes the table-level
SELECT grant from `anon` and re-grants 44 named columns. All of
`username`, `work_city`, `city`, `rera_number`, `verification_status`,
`years_experience`, `years_of_experience`, `agency_name`, `approval_status`,
`is_blocked`, `is_active` are granted; `email`, `phone`, `mobile_number` are not.

A column-level grant is not a row filter: naming an ungranted column fails the
**entire** query for that role. This is also true of columns used only in a
`WHERE` clause — so filtering on `approval_status` / `is_blocked` while logged
out is only legal because both are in the grant list. They are.

### 1.4 `global_search` RPC — returns people, but is not usable as the reference

`20260402111500_restore_coordinates.sql:30-160` (v2, the deployed one):

```sql
SELECT prof.user_id AS id,
       COALESCE(prof.company_name, prof.display_name) AS label,
       'builder' AS type, prof.user_type AS description, ...
FROM public.profiles prof
WHERE (to_tsvector(...company_name, display_name, bio...) @@ query_tsquery
       OR prof.display_name ILIKE '%'||original_term||'%'
       OR prof.company_name ILIKE '%'||original_term||'%')
  AND prof.user_type IN ('builder', 'dealer', 'broker')
ORDER BY type, label
LIMIT 20;
```

Four disqualifying properties:

1. `SECURITY DEFINER` with **no** `approval_status` or `is_blocked` filter — it
   returns pending, rejected and blocked profiles to anonymous callers.
2. Roles limited to `builder`, `dealer`, `broker` — no influencer, no individual.
3. `LIMIT 20` applies to the **union** of cities + properties + projects +
   people, so people are routinely crowded out entirely.
4. No pagination, and one flat alphabetical order across all four types.

### 1.5 Ranking and ordering in the portal

**There is none for people.** Not one of the six surfaces calls `.order()`; rows
arrive in whatever order Postgres returns them. The only people ordering anywhere
in the portal is the RPC's `ORDER BY type, label` — alphabetical on
`COALESCE(company_name, display_name)`.

### 1.6 Pagination in the portal

**There is none for people.** Surfaces 1, 2 and 6 use a hard `.limit(5/10/10)`
with no offset. Surfaces 3, 4 and 5 fetch every approved profile of the role and
filter in the browser. No `.range()`, no cursor, no infinite scroll.

### 1.7 Fields returned and rendered

| Field | Surface 1 | Surface 2 | Surfaces 3-5 | Surface 6 |
|---|---|---|---|---|
| `user_id` | ✅ | ✅ | ✅ | ✅ |
| `display_name` | ✅ shown | ✅ shown | ✅ shown | ✅ shown |
| `avatar_url` | ✅ shown | ✗ generic icon | ✅ shown | ✅ shown |
| `user_type` | ✅ shown | ✅ shown as badge | fetched, not shown | ✅ shown |
| `company_name` | ✅ shown ("at X") | ✅ shown | ✅ shown | ✗ |
| `work_city` | ✗ | ✗ | ✅ shown (fallback "India") | ✗ |
| experience | ✗ | ✗ | ✅ `years_experience \|\| years_of_experience` | ✗ |
| `bio` | matched, not shown | ✗ | ✗ | ✗ |
| rating | ✗ | ✗ | ✗ | ✗ |
| verification | ✗ | ✗ | **badge always drawn, not data-driven** (§6 D2) | ✗ |

Surface 2 selects `avatar_url` from the view but renders a generic `<User/>` icon
instead — the avatar is fetched and discarded.

### 1.8 Ratings on a people card — the one portal precedent

Not on any search surface, but `pages/ExploreCity.tsx:210-235` renders a rating
on a builder card, batched:

```ts
const { data: ratingsData } = await supabase
  .from("user_ratings").select("rated_user_id, rating")
  .in("rated_user_id", builderIds);
// sum/count per user → Number((sum / count).toFixed(1)); undefined when none
```

`user_ratings` SELECT policy is `USING (true)` (`20251207160017:19-20`), so this
is readable by anyone. `ExploreCity` also filters people by city server-side:
`.ilike("work_city", '%city%')` with `.limit(20)`.

### 1.9 Navigation

Every people card in the portal navigates to `/profile/${user_id}` →
`pages/UserProfile.tsx`. There is no intermediate screen and no extra argument.

### 1.10 Loading / empty / no-result states

- **Loading**: surfaces 3-5 render 8 pulsing skeleton cards with a circle + two
  bars. Surface 1 renders a centered spinner + "Searching the marketplace…".
- **No query**: surface 1 shows recent searches (localStorage, cap 10) plus
  hardcoded "Popular categories" and "Trending Locations" chips.
- **No results**: surface 1 — "No matches found" / "We couldn't find any results
  for \"q\"" / a "Try another search" button. Surfaces 3-5 — an icon, "No
  brokers found", "Try modifying your filters".
- **Error**: `console.error` only. No user-visible error state on any people
  surface; the list simply stays empty.

### 1.11 Trigger

- Surface 1: 300 ms debounce on every keystroke, fires when `trim()` is
  non-empty; results cleared when the box empties.
- Surface 2: only as a side-effect of a property search submit, and only when
  `searchQuery` or `keyword` is non-empty.
- Surfaces 3-5: one fetch on mount; the search box filters in memory.
- Surface 6: 300 ms debounce, fires at ≥ 2 characters.

---

## 2. Current Flutter search flow

| Concern | Current state |
|---|---|
| Entry | `screens/search/search_screen.dart` — autofocused box, 300 ms debounce, **≥ 3 chars**, AI parse of every submit, voice search, 4 property-type pills, recent searches |
| Suggestions | `PropertyService.globalSearch()` → `global_search` RPC. **`builder` and `project` rows are explicitly discarded** (`search_screen.dart:202-205`) because at the time there was no screen to open them on |
| Submit | AI parse → `FilterProvider` → `Navigator.pushNamed('/search-results')`; the results screen runs the search from its own `initState` |
| Results | `search_results_screen.dart` — list / grid / map, `PropertyProvider.runSearch(reset:)`, `loadMoreResults` at `maxScrollExtent - 300`, `AppConstants.searchPageSize = 20`, `.range()` + `CountOption.exact` |
| People | **Nothing.** No people model, service, provider, screen or card. Zero coverage |
| Public profile | `PublicProfileScreen` exists and is wired at `AppConstants.publicProfileScreen`, taking `{userId, avatarHeroTag?}` |
| Reusable assets | `UserProfile` (52 fields, `effectiveCity`/`effectiveExperience`/`isVerified`/`effectiveRera`/`initials`/`displayTitle`), `UserProfileService.publicColumns` (the anon-grant list), `RatingSummary.fromValues` (identical 1-decimal arithmetic to the portal), `roleBadge`/`roleLabel`/`roleColor`, `EmptyStateView`, `SearchErrorState`, `formatCompactCount`/`formatRating` |

---

## 3. Gap analysis

| # | Requirement | Portal | Flutter today | Gap |
|---|---|---|---|---|
| G1 | People are searchable at all | 6 surfaces | none | **Everything** — model, service, provider, screen, card |
| G2 | Search 4 roles: builder, broker, influencer, individual | only surfaces 1/2/6 cover all roles; the directories split them and reference two roles (`agent`, `developer`) that the `user_type` CHECK constraint forbids | n/a | Need one role vocabulary; drop the dead values |
| G3 | Approved-only, non-blocked | the view does both; the directories do only approval; RLS gives a signed-in user everything | n/a | Must apply **both** filters client-side, since the fields the cards need are not on the view |
| G4 | City / Area on the card | not on the view; directories use `work_city` | n/a | Query the base table, not `profiles_public` |
| G5 | Rating on the card | no search surface does it; `ExploreCity` does, batched | `RatingSummary.fromValues` exists | Add a batched `user_ratings` read per page |
| G6 | Verification / RERA badge | drawn unconditionally — not data-driven | `UserProfile.isVerified`, `effectiveRera` exist | Gate on real data; do not reproduce the defect |
| G7 | Username on the card | never selected by any surface | granted to `anon`; already in `publicColumns` | Add to the select list |
| G8 | Pagination / infinite scroll | none anywhere | property paging pattern exists | Port the property `.range()` + count pattern |
| G9 | Deterministic order | none — arbitrary row order | n/a | **Required by G8**: `.range()` over an unordered query can repeat or skip rows |
| G10 | Loading / empty / no-result / error states | skeletons + spinner; no error state at all | `EmptyStateView`, `SearchErrorState`, skeleton pattern | Build all four; add the error state the portal lacks |
| G11 | Tap → public profile | `/profile/:id` | route exists | Push `AppConstants.publicProfileScreen` with `userId` |

### Two gaps that cannot be closed without changing behaviour

- **G9 (ordering).** The portal's people queries have no `ORDER BY`. Adding
  `.range()` pagination on top of an unordered query is incorrect — PostgreSQL
  makes no row-order guarantee between two such queries, so page 2 can repeat or
  omit rows from page 1. Pagination was explicitly requested, so a total order is
  mandatory. Chosen: `display_name` ascending (the portal's only people-ordering
  precedent, from the RPC's `ORDER BY … label`) with `user_id` ascending as the
  tiebreaker to make the order total.
- **G6 (verification badge).** Reproducing the portal exactly would mean drawing
  a verified shield on every broker, builder and influencer regardless of their
  `verification_status`. The badge is gated on data instead.

Both are recorded as intentional deviations in §5.

---

## 4. Answers to the ten questions

1. **How is people search triggered?** Portal: a 300 ms debounce on the global
   search modal's single box (surface 1), a side-effect of a property search
   submit (surface 2), on mount for the three directories, and a 300 ms debounce
   at ≥2 chars in the pickers. There is no dedicated people-search screen.
2. **Which tables?** `public.profiles_public` (surfaces 1-2) and
   `public.profiles` (surfaces 3-6). Ratings, where shown, come from
   `public.user_ratings`. Nothing else.
3. **Which roles are searchable?** Surfaces 1, 2 and 6 apply no `user_type`
   filter, so all of `builder | broker | influencer | individual | seller |
   dealer` (the current CHECK constraint, `20260326000000:21`). The directories
   filter to `broker|agent|influencer`, `builder|developer` and `influencer`
   respectively — `agent` and `developer` are not valid `user_type` values and
   match nothing.
4. **Which filters?** `approval_status = 'approved'` everywhere;
   `COALESCE(is_blocked,false) = false` on the view and in the pickers only;
   `user_id != self` in the pickers. **`profiles.is_active` is never filtered by
   any people query in the portal** — it is used only for advertisements and
   other tables, so it is not reproduced here.
5. **Ranking / ordering?** None. No people query orders its rows. The RPC's
   `ORDER BY type, label` is the only ordering precedent.
6. **Pagination?** None. Hard `LIMIT 5/10/20`, or fetch-everything-and-filter.
7. **Fields returned?** See §1.7. The view's 14 columns for surfaces 1-2; eight
   named columns for the directories; four for the pickers.
8. **Shown on each card?** See §1.7. Name, role, company, avatar, city and
   experience across the surfaces; never rating, never username, never a
   data-driven verification badge.
9. **Tap → profile?** `navigate('/profile/${user_id}')`, every surface.
10. **States?** See §1.10. Skeletons and spinners for loading; recent searches +
    hardcoded chips for the idle state; a copy-complete no-results state; and no
    error state at all.

---

## 5. Implementation plan

### 5.1 Reference decisions

| Decision | Choice | Why |
|---|---|---|
| Table | `public.profiles` | `profiles_public` omits `username`, `work_city`/`city`, `rera_number`, `verification_status` — four of the eight required card fields. The base table is what surfaces 3-6 already use |
| Row filters | `approval_status='approved'` **and** `is_blocked=false` | Byte-for-byte the view's own predicate, and exactly what `NewChatModal.tsx:53-54` already sends to the base table. Closes G3 without trusting RLS, which grants a signed-in user every row |
| Columns | a subset of `UserProfileService.publicColumns` | That constant *is* the `anon` grant list, so the query is legal signed-in or signed-out |
| Roles | `builder`, `broker`, `influencer`, `individual` as chips; "All" sends no `user_type` filter | "All" reproduces surfaces 1/2/6 exactly. `agent` and `developer` are dropped as dead values |
| Text match | `or(display_name.ilike, company_name.ilike, bio.ilike)` | Surface 1's matcher — the most complete of the six |
| Order | `display_name` asc, then `user_id` asc | See G9 |
| Page size | `AppConstants.searchPageSize` (20) | The constant property search already uses |
| Rating | one batched `user_ratings` read per page | `ExploreCity.tsx:212-215` verbatim, aggregated by the existing `RatingSummary.fromValues` |
| Suggestion source | the new service, **not** `global_search` | The RPC is `SECURITY DEFINER` with no approval/blocked filter (§1.4) |

### 5.2 Files to create

| File | Contents |
|---|---|
| `lib/models/people_search_result.dart` | `PeopleSearchResult` row model + `PeopleSearchPage(rows, totalCount)`; `PeopleRole` vocabulary |
| `lib/services/people_search_service.dart` | `searchPeople()` (filters, matcher, order, `.range()`, exact count) and `fetchRatings()` (batched) |
| `lib/providers/people_search_provider.dart` | query / role / results / paging / loading / error / empty state |
| `lib/screens/search/people_search_screen.dart` | the screen: search field, role chips, paginated list |
| `lib/screens/search/widgets/people_result_card.dart` | `PeopleResultCard` + `PeopleResultSkeleton` |
| `test/people_search_test.dart` | model mapping, filter-string escaping, rating aggregation parity, ordering, paging, card rendering, navigation |

### 5.3 Files to modify — and why a new file will not do

| File | Change | Why it must be this file |
|---|---|---|
| `lib/core/constants/app_constants.dart` | `+ peopleSearchScreen = '/people-search'` | Route names are centralised here; the same additive pattern approved four times already |
| `lib/app.dart` | +1 import, +1 `case` | `onGenerateRoute` is the only route table |
| `lib/screens/search/search_screen.dart` | a `PEOPLE` suggestion group fed by the new service, its tap handler, and a "Search people for …" row | The entry point has to be inside the existing search box. The file's own comment (lines 40-46) says `builder` suggestions are dropped *because no public profile screen existed* — that is no longer true |

Property search is untouched: the property/city suggestion fetch, the AI parse,
voice search, the pills, submit, `FilterProvider`, `PropertyProvider`,
`SearchResultsScreen` and every property widget keep their current code paths.
The people fetch in `_fetchSuggestions` gets its own `try`/`catch` so a people
failure cannot degrade property suggestions (surface 1's per-promise pattern).

### 5.4 Intentional deviations from the portal

| # | Deviation | Reason |
|---|---|---|
| V1 | Deterministic `ORDER BY` added | Correct `.range()` pagination is impossible without it (G9) |
| V2 | Pagination added | Explicitly requested; no portal precedent to copy |
| V3 | Verification badge gated on `verification_status` / `rera_number` | The portal draws it unconditionally (§6 D2) |
| V4 | `is_blocked=false` added to role-filtered queries | The directories omit it and leak blocked users (§6 D1) |
| V5 | Rating shown on a search card | Requested; uses `ExploreCity`'s existing batched query |
| V6 | A visible error state with retry | The portal has none — failures are silent |
| V7 | `.or()` values quoted when they contain PostgREST metacharacters | The portal interpolates raw user text into the filter string (§6 D3) |

### 5.5 Non-goals

City/area **filtering** (the directories' city box, `ExploreCity`'s
`.ilike('work_city', …)`) is not built — city is *displayed*, per the
requirement, but no portal people-*search* surface filters by it. The three
directory screens are separate browse pages and are out of scope.

---

## 6. Portal defects found — reported, not reproduced

- **D1 — blocked users appear in the directories.** `BrokersList`,
  `BuildersList` and `InfluencersList` filter `approval_status='approved'` but
  not `is_blocked`. Because the signed-in RLS policy is `auth.uid() IS NOT NULL`,
  a blocked-but-approved profile is listed to every signed-in visitor.
- **D2 — the verification badge is decorative.** All three directories render
  `<ShieldCheck/>` unconditionally, so every listed broker, builder and
  influencer appears verified regardless of `verification_status`.
- **D3 — the `.or()` filter string is built from raw user input.** e.g.
  `` `display_name.ilike.%${query}%,company_name.ilike.%${query}%` ``. A query
  containing a comma or parenthesis changes the filter's structure rather than
  being matched literally.
- **D4 — `global_search` bypasses RLS.** `SECURITY DEFINER` with no
  `approval_status` / `is_blocked` predicate on its profiles branch, so the
  public autocomplete can surface unapproved and blocked profiles.
- **D5 — two dead role values.** `agent` (`BrokersList`) and `developer`
  (`BuildersList`) are not in the `user_type` CHECK constraint and match nothing.
- **D6 — the directories fetch unbounded result sets.** No `limit`, no `range`;
  every approved profile of the role is transferred and filtered in the browser.
- **D7 — surface 2 discards the avatar it fetched.** `Search.tsx` selects
  `avatar_url` via the view and renders a generic icon.
- **D8 — `BrokersList` lists influencers as brokers.** Its role filter is
  `['broker','agent','influencer']`, so `/influencers` and `/brokers` overlap.

None of these are fixed in the portal by this work; D1, D2 and D3 are simply not
carried into the Flutter implementation (V3, V4, V7).
