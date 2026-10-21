# PropCid Listing Migration — Final Architecture Review

**Verdict up front:** The Migration Specification is *directionally* correct and its per-category reconciliation stands, but it is **not yet complete**. This from-scratch re-read of the source uncovered **five new issues not in the spec**, one of which is a **data-destruction bug** severe enough that it must be fixed before any other migration work touches edit mode. Implementation should **not** begin on the category tasks until the spec absorbs the items below. I do not recommend the "no gaps remain" sign-off.

All findings are cited to source; nothing is asserted from memory.

---

## The five new findings (not in the current spec)

### NEW-1 (CRITICAL — data destruction). Flutter edit-mode overwrites the metadata blob and drops all bag-only keys.
Evidence:
- Flutter **write** path flushes the entire key-value bag into metadata: `meta.addAll(provider.allTextFields); meta.addAll(provider.allBoolFields); …allListFields` (`property_service.dart::_buildMetadata`). Good — the plumbing writes everything the UI collected.
- Flutter **edit hydration** (`post_property_provider.dart::applyEditingData`) reads only ~40 *named* metadata keys into typed fields. It **never re-populates `_text`/`_bool`/`_list` from `metadata`.**
- Flutter **update** builds a fresh blob and writes `.update({'metadata': metadata})` — a **full column replace**, no merge.
- React **update** does the opposite: `const metadata = editingProperty?.metadata ? { ...editingProperty.metadata } : {}` (PropertyWizard.tsx:1561) — it **spreads the existing blob first**, so untouched keys survive.

**Consequence:** any listing that carries bag-only metadata (every commercial `buildingInventory`, the whole PG block, land legal/zoning, office/warehouse features, etc.) **loses those keys the first time it is edited in Flutter**, because they were never loaded into the form and the fresh blob overwrites them. A Web-created listing edited once in the App is silently gutted. This also violates the "no destructive DB changes" ground rule — and it already ships.

**Required fix (must precede category work):** either (a) hydrate the full `metadata` blob back into the bag on edit (`meta.forEach((k,v)=> route to _text/_bool/_list)`), **and/or** (b) make Flutter update merge onto the existing blob (`{ ...existingMetadata, ...newMetadata }`) exactly like React. Do **both** for safety. Add a round-trip regression test: Web-create → App-edit → assert no metadata key lost.

### NEW-2 (HIGH). The true React metadata surface is ~340 keys, not the 99 the spec implies.
Evidence: React writes metadata from three sources — the explicit per-section `fillMetadata` calls, **plus a ~200-key `missingMetadataFields` catch-all** (PropertyWizard.tsx:1664) fed to `fillMetadata`, plus direct `metadata.X =` assigns. Total distinct keys ≈ **340**. My earlier "99 / 87-missing" number counted only the explicit calls and understated the surface.

**Why it still isn't 340 gaps:** because Flutter's bag-flush (NEW-1) *does* persist any key the UI sets. So the real gap = **(keys the Flutter UI never collects)** + **(hard-coded key renames, NEW-3)** + **(the empty-write semantics, NEW-4)** — not 309 raw keys. The spec's category tables already enumerate the *user-visible* missing fields correctly; what's missing is the explicit statement that **the parity target is the full `missingMetadataFields` list**, and that any React key not surfaced by a Flutter input will simply be absent (acceptable as `undefined` only if readers tolerate it — see NEW-4).

**Required fix:** add the verbatim `missingMetadataFields` list to the shared key file (T0) as the authoritative metadata allow-list, and check every category's inputs against it, not against the smaller diff.

### NEW-3 (HIGH). Three hard-coded key renames in Flutter shadow/collide with the bag flush.
Evidence (`_buildMetadata`): `meta['maintenanceAmount'] = provider.maintenanceCharges`, `meta['tokenAmount'] = provider.bookingAmount`, `meta['allInclusivePrice'] = provider.allInclusivePriceToggle`. Meanwhile React's canonical keys are `maintenanceCharges`, `tokenAmount`, `allInclusivePriceToggle`.
- `allInclusivePrice` ≠ React `allInclusivePriceToggle` → Web never reads it. Hydration also reads the wrong key (`meta['allInclusivePrice']`), so it's at least self-consistent within Flutter but invisible to Web.
- `maintenanceCharges` (React key) vs Flutter writing `maintenanceAmount` — if the bag ever also carries `maintenanceCharges`, **two keys represent one value** and readers disagree.
- Because these are written by named code *after* — actually *before* — the bag `addAll`, a bag key of the same name could overwrite them (ordering risk).

**Required fix:** delete the renames; write React's canonical keys only; fix hydration to match. Covered by spec A7/T1 but the **collision/ordering risk** and the hydration side were not spelled out — add them.

### NEW-4 (MEDIUM — read-time parity). Blank-value semantics differ: React writes typed-empty, Flutter omits.
Evidence: React `fillMetadata`/`dbSafe` writes **every** listed key with a concrete empty (`''`/`false`/`[]`) so the key always exists. Flutter writes bag keys only when set, and several named writes are guarded by `if (x.isNotEmpty)`. So Web-created rows have `metadata.someField = ''`; App-created rows **omit the key**.

**Consequence:** any reader that does `metadata.foo.trim()` or `metadata.foo.length` (not `metadata.foo?.…`) will throw or misbehave on App-created rows. This is a latent cross-platform read bug that won't appear until a Web component reads an App-created listing.

**Required fix:** decide one contract and apply it both sides. Safest = match React: have Flutter write typed-empty for the full allow-list (mirror `fillMetadata`). Add to T1.

### NEW-5 (MEDIUM). `headlinePrice` PG mirroring and `mediaCategories` are undocumented payload behaviours.
Evidence:
- React computes `headlinePrice` for PG: `sell → totalSalePrice`, `rent → monthlyRentPerBed || monthlyRentPerRoom`, else `price`, and writes it into the **`price` column** so PG cards/search don't show "Price on Request" (PropertyWizard.tsx ~1746). Flutter writes `provider.price` straight through. If Flutter's PG pricing (per P6) doesn't mirror the per-bed/sale value into `price`, **every App-created PG listing shows a wrong/zero headline price in both apps' feeds and sorts wrong in search.**
- Both apps write `metadata.mediaCategories` (a parallel array of per-URL categories) — Flutter already does this. Good, but the spec never named it; it must stay in sync with `media_urls` **order** or the category→image mapping corrupts. React builds it as `[...existingMediaUrls.category, ...mediaFiles.category]`; Flutter builds it from `mediaItems` only — **on edit, existing URLs' categories may be lost** (ties back to NEW-1).

**Required fix:** replicate the PG `headlinePrice` mirror in Flutter's PG pricing task (P6); and ensure `mediaCategories` is assembled as `existing + new` in the same order as `media_urls`, preserved across edit.

---

## Answers to the 14 questions

**1. Is anything still missing?** Yes — NEW-1 through NEW-5 above. Within the already-documented scope, the category field/dropdown/validation gaps are captured. The newly-missing items are: full metadata hydration on edit, the `missingMetadataFields` allow-list, blank-value semantics, PG headline-price mirroring, and the media-category ordering guarantee.

**2. Is any React behaviour still undocumented?** Yes: (a) the `missingMetadataFields` catch-all write (NEW-2); (b) React's non-destructive `{...editingProperty.metadata}` merge on update (NEW-1); (c) the PG `headlinePrice` mirror into the `price` column (NEW-5); (d) `metadata.mediaCategories` and `metadata.buildingInventory = dbJson(...)` always-object writes; (e) hashtag behaviour — React extracts `#tags` from **both** description and the hashtags field, de-dupes, and `sanitizeTagsArray`s them; Flutter's `_parseHashtags` must match this extraction or `hashtags[]` diverges. Add (e) as a small item.

**3. Is any dropdown still not compared?** A few beyond the spec's list need an explicit value-level check against React SelectItems before coding: commercial `commercialType`/`commercialSubType` full option sets (spec flagged "Commercial Land" as verify-then-add — still open); `buildingClass` (A/B/C), `propertyOn` (Basement…Second Floor+), `spaceDetails` (Entire Building/Particular Floor/Co-working), brokerageType, `leaseDuration`/min-period option lists, PG `bedType`/`roomTypes`, and unit dropdowns for land dimensions (`frontUnit`/`backUnit`/etc.). These are enumerated in `PropertyFormData` but their option arrays live inside the step JSX and should be extracted verbatim into the shared constants file, not hand-typed.

**4. Is any field still not mapped?** With NEW-1/2 fixed, the mapping *mechanism* covers everything (bag + named). The open mapping risks are the 3 renamed keys (NEW-3) and any field whose Flutter bag key name differs from React's — this must be audited key-by-key against `missingMetadataFields`, because a mis-keyed bag entry persists silently to the wrong name with no error (the bag has no schema).

**5. Is any metadata key still unmapped?** Effectively yes until NEW-2/NEW-4 are applied: keys the Flutter UI doesn't yet collect are simply absent, and blanks are omitted rather than typed-empty. After T0 (allow-list) + the category input work + NEW-4, the set closes.

**6. Is any validation still missing?** Beyond the spec's "port `propertyListingRules.ts`": the **exact validator internals** must be ported verbatim, not approximated — `PATTERN.PINCODE=/^\d{6}$/`, `PHONE=/^\+?[\d\s-]{8,15}$/`, `EMAIL`, and crucially `isBlank` semantics (**boolean is never blank; `false` counts as answered; empty object/array/File handling**) and `positiveNumber` stripping `[^\d.-]` before parsing. A subtly different `isBlank` or phone regex will pass/fail different inputs than the Web, breaking step-gating parity. Also the builder-project cross-field rule (`available_units ≤ total_units`) — only relevant if Part C proceeds.

**7. Is any conditional rendering still missing?** The step-level (A2) and `availableFrom` (A3) cases are documented. Two field-level ones to add explicitly: `landUseMasterPlan` is required **only when `listingType==='rent'`** for land (easy to miss); and commercial has **no `area` field** (mirrors `superBuiltUpArea`), so any Flutter code requiring `area` for commercial is a false-fail. Both are in the validation rules but should be called out as rendering rules too.

**8. Is any API payload still unmatched?** Yes, three: (a) PG `headlinePrice`→`price` mirror (NEW-5); (b) the destructive-vs-merge update behaviour (NEW-1); (c) blank-value typed-empty writes (NEW-4). The core column set (`properties`, the three subtables, `property_contact_details`) matches. Confirm subtable column mappings once more during coding — e.g. commercial maps `cafeteria=guardRoom`, `conference_rooms=numberOfCabins`; residential maps `age_of_property=buildingInventory.buildingAge`; land sets `slope_percentage=0`. These non-obvious mappings must be preserved exactly.

**9. Is any edit-mode hydration still missing?** **Yes — this is the biggest gap (NEW-1).** Flutter hydrates only named keys, not the bag; and does not merge existing metadata on update. Until fixed, edit mode is lossy and destructive. This must be the first fix.

**10. Is any media behaviour still unmatched?** Beyond A4 (`property_video`) and A5 (land category set): `mediaCategories` must be assembled as existing+new in `media_urls` order and preserved on edit (NEW-5); `main_display_media_url` must be set (React uses the star-selected `mainDisplayMediaUrl` or `allMediaUrls[0]`; Flutter uses `allUrls.first` — acceptable but confirm the star-picker exists in App or the user can't choose a main image, a parity gap vs Web's star UI); and React runs `compressMedia` before upload — confirm App compression is equivalent enough not to change stored file expectations.

**11. Is any Builder Project integration still unmatched?** Unchanged and correctly gated: the **tag** (A8) is in scope; the full `BuilderProjectWizard` + inventory subsystem remain **undecided (Part C)** and therefore unmatched by design. No new finding, but the decision is still blocking and should be made before it becomes an afterthought — note the inventory system writes its own tables/contract that nothing in Flutter reads or writes today.

**12. Anything that would cause data inconsistency after deployment?** Yes, ranked:
- **NEW-1** metadata loss on App edit of rich (esp. Web-created) listings — *silent, destructive, cross-platform.* Highest risk.
- **NEW-3** `allInclusivePrice` (and any mis-keyed bag entries) invisible to Web — inconsistent reads.
- **NEW-4** missing-vs-empty keys crashing/again-misreading strict Web readers.
- **NEW-5** PG listings with wrong headline `price` and mis-ordered media categories.
- Enum drift (`sq_m` vs `sq_mtr`, residential subtype strings) causing filter/read mismatches — already in spec but they *are* live data-consistency risks.

**13. What regressions are most likely?**
- Re-saving an existing App listing wipes metadata (NEW-1) — the #1 regression; will hit real production rows immediately.
- Tightening validation (T2) blocks saves that used to succeed (e.g. now-required `carpetArea`, `ownershipType`, commercial building block) — expected but will surface as "I can't publish anymore" reports; needs a data-backfill or grandfathering plan for editing old rows that legitimately lack new-required fields.
- Renaming residential subtype strings orphans existing rows whose `residential_subtype` holds the old App strings (`Studio Apartment`, `Row House`) — they won't match React's `isApartment`/`isHouse` sets, changing which fields/validation apply on edit. Needs a value-migration/alias map.
- Changing `area_unit` `sq_m`→`sq_mtr` orphans existing App rows written as `sq_m` in Web filters. Needs a read-time alias or one-time data update.
- Media-category array desync on edit (NEW-5) mislabels existing photos.

**14. Which implementation order minimizes risk?**
1. **NEW-1 fix first (edit hydration + merge-on-update).** Nothing else touches edit mode until this lands, or every subsequent test corrupts data. Ship with the round-trip regression test.
2. **T0 shared constants + full `missingMetadataFields` allow-list**, with the verbatim option arrays and validator internals (Q6) and value-alias maps for the subtype/area-unit migrations (Q13).
3. **T1 data-contract fixes** (NEW-3 renames, NEW-4 typed-empty, `sq_mtr`, subtype strings) — additive/corrective, guarded by the round-trip test.
4. **T2 validation port** (verbatim engine + rules) — but gate the newly-required fields so **editing pre-existing rows that lack them isn't blocked** (grandfathering), to avoid the Q13 regression.
5. **T3 step-visibility + `availableFrom` placement**, **T4 media** (incl. NEW-5 media ordering + main-image picker), then **T5 builder tag**.
6. **T6–T10 category field closure**, ordered by blast radius/least-coupled first: **Residential → Others → Land → PG → Commercial** (Commercial last: it carries the nested `buildingInventory` object, the most new surface and the highest hydration risk). Include the PG `headlinePrice` mirror (NEW-5) inside the PG task.
7. **T11 pricing-common.**
8. **Part C** only after the scope decision.

---

## Sign-off statement
**Functional gaps remain.** Specifically NEW-1 (destructive edit-mode metadata loss), NEW-2 (full metadata allow-list), NEW-3 (key renames + collision), NEW-4 (blank-value semantics), and NEW-5 (PG headline price + media-category ordering), plus the verbatim-validator and enum-migration details under Q6/Q13. The Migration Specification should be amended to incorporate these — most importantly, **NEW-1 must be fixed before any edit-mode-touching work begins.** Once the spec is updated with these items and the value-alias/grandfathering plans, implementation can safely proceed in the order in Q14.

No implementation code was produced, per instructions.