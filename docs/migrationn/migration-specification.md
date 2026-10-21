# PropCid Listing Migration — Deep Analysis & Implementation Plan

**Objective:** Make the Flutter listing system a *functional* clone of the React website's listing system (fields, dropdowns, conditional logic, validation, payload, builder-project logic) while Flutter keeps its own visual design language.

**Method:** Every statement below is grounded in the actual source you supplied (React `PropertyWizard`, `BuilderProjectWizard`, the portal's validation layer, and the Flutter `post_property` flow). Where a fact could not be confirmed from source, it is flagged as an open question — nothing is invented.

---

## 0. Headline findings (read this first)

1. **This is a parity-gap job, not a greenfield build.** Flutter already has all 8 wizard steps (`type_selection` → `basic_info` → `dimensions` → `condition` → `amenities` → `legal` → `pricing` → `media_contact`) plus a `review_step`, and already writes the same 4-object persistence contract React uses. So the migration is about *closing field/dropdown/validation gaps*, not rebuilding the wizard.

2. **The two apps use fundamentally different state models.** React's `PropertyFormData` is ~300 explicitly-named fields on one flat interface. Flutter's `PostPropertyProvider` uses ~65 typed fields **plus a loose key-value bag** (`_text` / `_bool` / `_list` maps accessed via `text(key)`, `boolVal(key)`, `listVal(key)`). This is actually convenient for migration — new fields can be added to the bag without changing the class shape — but it means **there is no compiler safety net**: a typo'd key silently produces empty data instead of a build error. Parity must therefore be enforced by a shared key list + validation, not by types.

3. **The persistence contract is shared and already mostly aligned.** Both apps write:
   - `properties` (core columns + a big `metadata` JSONB blob),
   - one category subtable — `properties_residential` / `properties_commercial` / `properties_land` (PG rows also go to `properties_residential`),
   - `property_contact_details`,
   - media to the `property-media` storage bucket, public URLs into `properties.media_urls`.

4. **Two concrete data-contract bugs already exist in Flutter** (found in `property_service.dart::_buildMetadata`, confirmed by its own comments):
   - Flutter writes `metadata.maintenanceAmount`, `metadata.tokenAmount`, `metadata.allInclusivePrice` where React writes/reads `maintenanceAmount` vs Flutter's source field `maintenanceCharges`… the *keys* mostly line up but the **remap is done by hand and is easy to drift**. More seriously, several React keys are written by Flutter under **different names** (see §Gap 2). Any field the React web reads by its canonical key will read empty for Flutter-created listings, and vice-versa.
   - **87 metadata keys that React persists are not written by Flutter at all** (quantified in §Gap 2). These are silently dropped: a listing created in Flutter loses all land legal flags, commercial office/warehouse detail, the entire PG metadata block, builder-project tag snapshot, sale finance/tax block, and the address `addressLine1/2` keys.

5. **Builder Projects is a separate wizard and appears to have NO Flutter equivalent.** React has `BuilderProjectWizard` (5 steps, writes `builder_projects`) + an inventory system (`ProjectInventoryManager`, `AddInventoryItemModal`, `InventoryTableEditor`, `BuilderInventoryManager`). I found no matching Flutter screen/provider/service. **Open question for you: should builder-project creation exist in Flutter at all, or is it intentionally React-only (like the CRM/SEO/admin surfaces)?** Per the architecture, "build on both" is not automatic — confirm before we scope it. Everything about builder projects below is documented but *gated* on your answer.

---

## PHASE 1 — React listing architecture (reverse-engineered)

### Component map (`components/PropertyWizard/`)
- `PropertyWizard.tsx` (~92 KB) — orchestrator. Owns `PropertyFormData`, the dynamic step array, edit-mode hydration from an existing row, media upload, metadata assembly, and all Supabase writes.
- `StepHeader.tsx` — presentational step header.
- `steps/` — 8 step components: `TypeSelectionStep`, `BasicInfoStep`, `PropertyDimensionsStep`, `ConditionStep` (exported as `FurnishingStep`), `AmenitiesStep`, `LegalDetailsStep`, `PricingStep`, `MediaAndFinalStep`.

### State management
Single `useState<PropertyFormData>` in the orchestrator; steps receive `formData` + `updateFormData(partial)`. No Redux/Zustand. Edit mode hydrates `formData` from the `properties` row + its `metadata` + the category subtable + contact row.

### Dynamic step array (the conditional-step rule)
```
stepsRaw = [
  Category, BasicInfo, Dimensions,
  ...(!isLand && !isResidential ? [Condition] : []),   // Condition hidden for land & residential
  ...(!isLand ? [Amenities] : []),                       // Amenities hidden for land
  Legal, Pricing, Media
]
isLand        = propertyType === 'land'
isResidential = propertyType === 'residential'
```
So the visible step set is category-dependent:
| Category | Visible steps |
|---|---|
| land | Category, BasicInfo, Dimensions, Legal, Pricing, Media (no Condition, no Amenities) |
| residential | Category, BasicInfo, Dimensions, Amenities, Legal, Pricing, Media (no Condition) |
| commercial / pg / others | all 8 |

### Validation layer (`src/lib/validation/`)
- `propertyListingRules.ts` — **the single source of truth for required fields**, one rule set per step, each rule guarded by an `applies(data)` predicate that mirrors the JSX conditionals. This file *is* the parity spec; §Phase 6 reproduces it.
- `projectRules.ts` — required fields for the builder-project wizard (+ a cross-field rule: `available_units ≤ total_units`).
- `requiredFields.ts` — generic engine + reusable validators (`positiveNumber`, `nonNegativeNumber`, `validEmail`, `validPhone`, `validPincode`) + `summariseIssues`.
- `dbSafe.ts` — null-safe coercers (`dbText→''`, `dbNum/dbInt→0`, `dbBool→false`, `dbArray→[]`, `dbJson→{}`, `dbDate→null`, `dbUuid→null`) and `fillMetadata(meta, form, keys[])`. **Deliberate design rule: nothing reaches Postgres as NULL except `date` columns and FKs.** Flutter must match this or it will re-introduce the NULL-row problem the comments describe.

### Persistence contract (`PropertyWizard.tsx` submit)
1. Upload each `mediaFiles[i]` → `compressMedia` → `storage.from('property-media').upload(fileName)` → collect `getPublicUrl`. Merge with `existingMediaUrls`.
2. Build `metadata` (see §Phase 6 / Gap 2 for the exact key set).
3. Insert/Update `properties`:
   - Columns: `user_id, title, description, location(=location||addressLine1), latitude, longitude, price(=headlinePrice||price), area, area_unit, rate_per_area, available_from, amenities, hashtags, media_urls, main_display_media_url, property_type(=listingType), category, residential_subtype, project_id, metadata, status:'active'`.
   - `category` enum map: `{'pg/Co-living':'pg_coliving', others:'others', land, residential, commercial}`.
   - `property_type` column holds the **listing type** (`rent`/`sell`/`lease`), NOT the category. (This naming is confusing but is the real contract — Flutter already matches it.)
4. Category subtable insert/update (branch on `propertyType`):
   - **residential | pg** → `properties_residential`: `bedrooms, bathrooms, built_up_area_sqft, carpet_area_sqft, balconies, furnished, parking_spaces, floor_number, total_floors, age_of_property, facing_direction`.
   - **commercial** → `properties_commercial`: `built_up_area_sqft, carpet_area_sqft, washrooms, parking_spaces, floor_number, total_floors, power_load_kw, furnished, cafeteria(=guardRoom), conference_rooms(=numberOfCabins)`.
   - **land** → `properties_land`: `area_sqft, boundary_wall, water_source, road_width_ft, soil_type, slope_percentage(=0)`.
5. `property_contact_details`: `contact_phone, contact_email`.

---

## PHASE 2 — Every step (React)

| # | Step (title) | Purpose | Key inputs |
|---|---|---|---|
| 1 | **Category** (`TypeSelectionStep`) | Pick category + listing type | `propertyType` (land/residential/commercial/pg/Co-living/others), `listingType` (rent/sell/lease) |
| 2 | **Basic Info** (`BasicInfoStep`) | Headline, description, category-specific subtype, full address + map pin | `title, description`; subtype selects; `addressLine1/2, city, state, pincode, landmark, latitude, longitude` (Google Places autocomplete) |
| 3 | **Dimensions** (`PropertyDimensionsStep`, ~89 KB — the largest) | Area + all size/structural fields, category-branched | area/unit, carpet/built-up/super-built-up, BHK, beds/baths/balconies, floors, land dimensions (front/back/left/right + units, khasra, FSI/FAR, soil), commercial `buildingInventory` block, PG room structure |
| 4 | **Condition** (`ConditionStep` / `FurnishingStep`) | Furnishing + condition; commercial building condition; PG housekeeping | `propertyCondition, availableFrom, furnishedType`, commercial `buildingAge/ownershipTypeBuilding`, PG `linenChangeFrequency/roomCleaningFrequency` |
| 5 | **Amenities** (`AmenitiesStep`, ~47 KB) | Amenity multiselects + commercial facilities + PG rules | category-specific amenity lists (see Phase 3) |
| 6 | **Legal** (`LegalDetailsStep`) | Ownership/legal; land ownership; PG quiet hours; ownership docs upload | `ownershipType, ownerName` (land), legal boolean flags, `quietHours` (PG) |
| 7 | **Pricing** (`PricingStep`, ~44 KB) | Price/rent/deposit/brokerage; commercial lease terms; PG per-bed pricing | branched heavily by listing type & category (see Phase 6) |
| 8 | **Media & Final** (`MediaAndFinalStep`) | Photos/videos by category, contact block, hashtags | `mediaFiles` (categorised), `contactName/Phone/Email, whatsappNumber, bestTimeToCall, hashtags`; PG `ownerManagerName, alternateNumber` |

---

## PHASE 3 — Categories & their option/amenity sets (verbatim from source)

**Categories:** `land` (Land / Plot), `residential`, `commercial`, `pg/Co-living`, `others`.

**Residential subtypes** (`residentialSubTypeGroups`):
- *Apartment group* (`APARTMENT_SUBTYPES`, drives the apartment vs house layout + `isApartment`/`isHouse` validation): `Flat`, `Independent / Builder Floor`, `Studio / Service Apartment`.
- *House group*: `Raw / Independent House`, `Villa / Kothi`, `Duplex House`, `Triplex House`, `Pent House`, `Bungalow`, `Farm House`.

**Land:** `landSubtype` = `land` | `plot`. `landTypeOptions` = Agriculture/Residential/Commercial/Industrial/Institutional Land. `plotTypeOptions` = Residential Plot, Commercial Plot. `landUseMasterPlanOptions` = Agriculture, Residential, Commercial, Industrial, Institutional / IT park, Parking Zone / Transport Hub, Others. `landSoilTypes` = Alluvial, Black, Red, Laterite, Sandy, Clay, Loamy, Silty (…). Land ownership (`landtypes`) = Freehold, Leasehold, Power of Attorney, Co-Operative Society.

**PG:** `pgtype` = Boys PG, Girls PG, Co-ed PG, Co-living Space, Student Housing, Working Professional PG, Hostel. `buildingTypeOptions` = Apartment, Independent House, Individual Building, Villa, Hostel Building, Gated Community Society, Others.

**Amenity lists (Phase 5 rendering depends on these):**
- `residentialSocietyAmenityList` (44 items), `residentialFlatAmenityList` (22), `residentialParkingAmenityList` (4), `residentialTenantPreferenceList` (Family/Bachelor/Company Lease/Pets/Smoking/Vegetarians Only — booleans `familyAllowed` etc.).
- `commercialSuitableForList` (12), `commercialOfficeBuildingAmenityList` (19), `commercialRetailWarehouseAmenityList` (9), `commercialWashroomList` (washrooms/westernSeats/indianSeats), `commercialParkingList` + `commercialOtherParkingList`.
- `PgRoomAmenityList` (13 boolean ids), `PgCommonAreaAmenityList` (14), `PgSafetyAndSecurityList` (4), `PgTenantRulesList` (8 boolean ids).
- `OtherGeneralAmenitiesList` (12) for `others`.

*(Full item strings are in the source arrays; §Phase 10 points each list at its Flutter target file so nothing is retyped from memory.)*

**Select option enums pulled from steps** (must match verbatim):
- Facing: North/South/East/West.
- Area units: `sq_ft, sq_mtr, sq_yd, acres, yards, ft, m`.
- BHK: `1 RK, 1 BHK, 2 BHK, 3 BHK, 4+ BHK`.
- Property condition / project status: New, Resale, Under Construction, Off-Plan, Other.
- Ownership: Freehold, Leasehold, Joint Venture, Co-ownership.
- Commercial subtypes seen: Business Center, Commercial Complex, Corporate Tower, IT Park, Individual Building, Mixed Use.
- PG cleaning/linen frequency: Daily, Alternate Days, Weekly, Fortnightly, On Demand.
- Media image categories: default = interior, exterior, amenities, floor_plan, property_video, other; land = sajra, land_video, land_images, other.

---

## PHASE 4 — Dropdowns (source of each)
All the option lists above are **static constants defined inline in the step files** (not API-driven), except:
- **Address / landmark** fields use **Google Places Autocomplete** (`useGoogleMapsLoader`) and set `latitude`/`longitude` from the picked place.
- **Builder-project tag** (`projectId`) is populated from the user's own `builder_projects` rows.
No other dropdown is API-driven. This matters for Flutter: everything except the map picker can be a hard-coded constant table (keep it in **one shared Dart constants file** so it can't drift from React).

---

## PHASE 5 — Conditional logic (authoritative list)
The conditional *visibility* is encoded in two places and Flutter must honour both:
1. **Step visibility** — the dynamic step array (§Phase 1): Condition hidden for land+residential; Amenities hidden for land.
2. **Field visibility within a step** — encoded as the `applies` predicates in `propertyListingRules.ts`. The full predicate set is reproduced in Phase 6 (it *is* the conditional spec). Representative rules:
   - `isLand` → land dimensions (front/back/left/right, khasra, FSI/FAR, floors allowed, height, soil), land ownership, `landUseMasterPlan` (only when `listingType==='rent'`).
   - `isResidential` → BHK, bedrooms, bathrooms, balconies, property condition; `isApartment` adds `floorNo` + society charges; `isHouse` adds `builtUpArea`.
   - `isCommercial` → the nested `buildingInventory` block (building name/code/type/total floors, working days/hours, lift count, security guards, parking counts, maintenance) + plot & super-built-up area; **no `area` field of its own** (mirrors super-built-up into `area`) — so never require plain `area` for commercial.
   - `isPg` → PG name/type/status/building type, room types, food/housekeeping, tenant rules, per-bed/per-room pricing; PG rent uses `monthlyRentPerBed`/`monthlyRentPerRoom` **instead of** `price`.
   - Listing-type branches: `sell` → finance/tax/registration + `ratePerArea` (not for PG); `rent`/`lease` → deposits, lock-in, maintenance, tenant prefs; commercial rent/lease → lease duration, escalation %, CAM, fit-out.

---

## PHASE 6 — Validation spec (reproduce this exactly in Flutter)

This is the contract. Below is the required-field matrix straight from `propertyListingRules.ts` (`✔` = required when its guard is true). Validators: `+` positive number, `0+` non-negative, `@` email, `☎` phone, `#` pincode.

**Step 1 Category:** `propertyType` ✔, `listingType` ✔.

**Step 2 Basic Info:** `title` ✔, `description` ✔; address block `addressLine1(||location)` ✔, `city` ✔, `state` ✔, `pincode` ✔#, `landmark` ✔, map pin (`latitude`+`longitude` together) ✔. Category subtype selects: land→`landSubtype`,`landType`; residential→`residentialSubType`; commercial→`commercialSubType`,`furnishedType`; pg→`pgPropertyType`,`buildingType`,`pgPropertyName`,`propertyStatus`.

**Step 3 Dimensions:** `area` ✔+ (all except commercial), `areaUnit` ✔.
- Land: `front/back/right/left` ✔, `surveyNumber`(Khasra) ✔, `fsiFarAllowed` ✔, `floorAllowed` ✔, `heightRestriction` ✔, `soilType` ✔, `landUseMasterPlan` ✔ (rent only).
- Residential/PG/others: `carpetArea` ✔+; house adds `builtUpArea` ✔+. Residential: `bhkType` ✔, `bedrooms` ✔0+, `bathrooms` ✔0+, `balconies` ✔0+, `propertyCondition` ✔; apartment adds `floorNo` ✔0+; residential/pg add `totalFloors` ✔0+.
- Commercial `buildingInventory`: `buildingName` ✔, `buildingCode` ✔, `buildingType` ✔, `totalFloorsBuilding` ✔+, plus `plotArea` ✔+, `superBuiltUpArea` ✔+.
- PG: `facing` ✔. `availableFrom` ✔ (land/residential).

**Step 4 Condition:** `propertyCondition` ✔, `availableFrom` ✔; commercial `buildingAge` ✔, `ownershipTypeBuilding` ✔; PG `linenChangeFrequency` ✔, `roomCleaningFrequency` ✔.

**Step 5 Amenities:** residential/others `amenities` ✔ (≥1); PG `pgAmenities` ✔ (≥1); commercial `businessType` ✔ (if `currentBusinessRunning`), `workingDays` ✔, `buildingWorkingHours` ✔, `liftCount` ✔0+, `securityGuards` ✔0+, `maintenanceCharges` ✔0+, `totalCarParking` ✔0+, `totalBikeParking` ✔0+.

**Step 6 Legal:** land `ownershipType` ✔, `ownerName` ✔; PG `quietHours` ✔.

**Step 7 Pricing:** `price` ✔+ (except PG non-lease); PG rent `monthlyRentPerBed||monthlyRentPerRoom` ✔; PG sell `totalSalePrice` ✔+ & `occupancyRate` ✔; rent/lease `securityDeposit` ✔; `tokenAmount` ✔ (all); `lockInPeriod` ✔ (rent/lease, not PG-sell); `ratePerArea` ✔+ (sell, not PG); apartment rent/lease `societyCharges` ✔ else `maintenanceCharges` ✔ (non-apartment, non-land, rent/lease); commercial rent/lease `leaseDuration`✔, `leaseEscalationPercent`✔, `camCharges`✔, `fitOutPeriod`✔; commercial sell `roiEstimate`✔, `currentRentalIncome`✔; PG rent `foodCharges`✔, `laundryCharges`✔; `brokerage` ✔ (all).

**Step 8 Media & contact:** ≥1 photo ✔; PG `ownerManagerName`✔, `alternateNumber`✔☎; `contactName`✔, `contactPhone`✔☎, `contactEmail`✔@, `whatsappNumber`✔☎, `bestTimeToCall`✔, `hashtags`✔.

> **Note on Flutter's current validation:** `PostPropertyProvider`'s `isStepNValid` getters are far looser than this — e.g. `isStep5Valid`/`isStep6Valid` return `true` unconditionally, Step 2 checks only title/location/city/subtype, Step 3 checks only area+BHK+beds+baths. Bringing Flutter to parity means porting the whole rule table above, ideally as a **direct Dart translation of `propertyListingRules.ts`** so the two never diverge.

---

## PHASE 7 — Builder Projects (React) — *scope-gated, see Finding #5*

`BuilderProjectWizard.tsx` — 5 steps keyed `basic / details / media / amenities / review`.
- **basic:** `title, project_type, location(city), description`.
- **details:** `total_units`+, `available_units`0+, `price_range_min/max`+, `area_sqft_min/max`+, `completion_date, possession_date, rera_number`. Cross-field: `available_units ≤ total_units`.
- **media:** `website_url, contact_number`☎, `logo_url, map_images`(master plan), `brochure_url`(PDF), `other_images, videos_urls`.
- **amenities:** ≥1 from `COMMON_AMENITIES` (19 items).
- **review:** none.

`PROJECT_TYPES`: plotted_development, group_housing, integrated_township, gated_community_plots_villas, farm_houses, service_apartment, commercial_spaces, office_spaces.

Writes `builder_projects` via `dbText/dbNum/dbArray/dbDate` (same NULL-free discipline), incl. `master_layout_url = map_images[0]` and a merged `media_urls`. Also has an **inventory subsystem** (`ProjectInventoryManager`, `AddInventoryItemModal`, `InventoryTableEditor`, `BuilderInventoryManager`, `PublicProjectInventory`) writing tower/unit inventory — a whole second contract. **Not analysed field-by-field here because its inclusion in Flutter is unconfirmed.** Confirm scope and I'll produce the same depth for it.

---

## PHASE 8 — Flutter listing surface (as-is)
- Screen: `screens/post_property/post_property_screen.dart` (dynamic step array, edit mode via `_editingPropertyId`).
- Steps: `steps/{type_selection, basic_info, property_dimensions, condition, amenities, legal_details, pricing, media_contact, review}_step.dart`.
- Provider: `providers/post_property_provider.dart` — `_currentStep`, ~65 typed fields, `_text`/`_bool`/`_list` key-value bag, `isStepNValid` getters, `submit(service, userId)`.
- Service: `services/property_service.dart` — `create/updateProperty`, `_buildMetadata`, `_insert/_upsertCategoryData`, `_insert/_upsertContactDetails`, media upload to `property-media`. Reads back with the same subtable joins.
- Models: `models/property_model.dart`, `property_detail_bundle.dart`.
- No builder-project listing flow found.

---

## PHASE 9 — Gap analysis

### Gap 1 — Structure/steps: **near parity.** All 8 steps + review exist; step-visibility logic exists. Verify Flutter's hide rules match §Phase 1 exactly (Condition hidden land+residential; Amenities hidden land).

### Gap 2 — Fields/persistence: **the main gap.** Programmatic diff of metadata keys (React `fillMetadata` + direct assigns vs Flutter `_buildMetadata`):

- React persists **99** metadata keys; Flutter writes **41**.
- **87 React keys are NOT written by Flutter** (silently lost on Flutter-created listings):
  `addressLine1, addressLine2, areaPerFloor, back, backUnit, bankLoanApproved, bossChairs, boundary, builderName, buildingInventory, buildingType, carpetArea, commercialSubType, commercialType, courtCasePending, dispute, employeeChairs, financeStatus, floorAllowed, front, frontUnit, fsiFarAllowed, gstApplicable, heightRestriction, heightRestrictionUnit, isPgListing, jamabandiAvailable, khataAvailable, landSizeUnit, landSubtype, landType, landUseMasterPlan, left, leftUnit, lockingPeriod, mutation, mutationAvailable, numberOfCabins, ocCertificate, originalCategory, otherTax, ownerName, ownerResiding, ownershipType, parkingType, pattaAvailable, pgBathroomType, pgFloorNumber, pgFoodAvailable, pgGateClosingTime, pgHouseRules, pgLiftAvailable, pgNoticePeriod, pgParkingType, pgPossessionDate, pgPropertyName, pgPropertyType, pgRentAmount, pgRoomType, pgSecurityDeposit, pgServices, pgSharingType, pgTenantType, plotArea, plotAreaUnit, plotNumber, possessionDate, priceType, projectId, projectLocation, projectName, propertyStatus, propertyTax, registrationTitle, registryAvailable, right, rightUnit, roadWidth, soilType, spaceDetails, superBuiltUpArea, surveyNumber, tenantPreference, vegNonVeg, waterSource, waterTax, workDesks`
- **Flutter-only keys / key-name mismatches** (React readers won't find these): `allInclusivePrice` (React: `allInclusivePriceToggle`), `availabilityStatus, constructionAge, electricityBackup, gasPipeline, internetAvailability, numberOfLifts, openParking, reraRegistered, solarPower, waterAvailability` (+ others that may be legitimately Flutter-extra). Each needs a decision: rename to the React key, or confirm it's an intentional Flutter-only extension.

> Whole feature blocks missing from Flutter persistence: **all land legal/zoning flags**, **commercial office/warehouse detail + `buildingInventory`**, **the entire PG metadata block** (`pg*`, `pgHouseRules`), **builder-project tag snapshot** (`projectId/projectName/builderName/projectLocation`), **sale finance/tax block**, and the **address lines**.

### Gap 3 — Dropdowns/options: must be verified list-by-list against §Phase 3. Highest-risk mismatches are enum *values* that get written to the DB (facing, area units, BHK, condition, ownership, PG frequencies) — a differing string breaks web filters/reads.

### Gap 4 — Validation: **large gap** (§Phase 6 note). Flutter validation is far looser and several steps are no-ops.

### Gap 5 — Builder Projects: **absent in Flutter** — scope decision required.

---

## PHASE 10 — Implementation plan (incremental, Claude-Code-executable)

Ordered so each step is independently shippable and testable. Security/data-integrity first (per architect priorities).

**Task 0 — Establish shared ground truth (do first).**
- Create `flutter_app/lib/screens/post_property/listing_constants.dart`: port *every* option array from §Phase 3 verbatim (categories, subtypes, land/pg types, all amenity lists, select enums, media categories). One file, so it can't drift.
- Create `flutter_app/lib/screens/post_property/listing_field_keys.dart`: the canonical metadata key list, copied 1:1 from the React key set in Gap 2. This becomes the allow-list the provider writes through.
- *Risk:* enum-string typos silently break web reads. *Test:* unit test asserting the Dart constant lists equal the React arrays (paste React arrays into the test as expected values).

**Task 1 — Fix the existing data-contract bugs (highest priority, small).**
- In `property_service.dart::_buildMetadata`, rename every mismatched key to its React canonical name (`allInclusivePriceToggle`, etc.), or document each as intentional-Flutter-extra. Confirm `maintenanceAmount`/`tokenAmount` mapping against how the web reads them.
- *Test:* create a listing in Flutter, open it in the React web app (edit mode), confirm all previously-mapped fields hydrate; and vice-versa.

**Task 2 — Port the validation table.**
- Translate `propertyListingRules.ts` → `flutter_app/lib/.../listing_validation_rules.dart` (rule = field key + label + `applies(provider)` predicate + optional validator), and replace the `isStepNValid` getters with a rules-driven check that returns the first offending field per step (mirrors `validatePropertyStep`).
- Reuse existing `Validators` for phone/email/pincode/number; add `positive`/`nonNegative`/`percent` to match.
- *Test:* table-driven tests per category×listingType asserting the same steps pass/fail as React for identical input.

**Task 3 — Close field gaps by category (one PR per category).** For each of land → residential → commercial → PG → others:
- Add missing inputs to the relevant Flutter step file (using Flutter's own widgets/design), writing to the canonical keys from Task 0.
- Extend `_buildMetadata` to persist that category's missing keys (from Gap 2), plus the category-subtable columns React writes.
- Wire edit-mode hydration for the new keys (read back from `metadata`/subtable), mirroring how the provider already hydrates in `applyEditingData`.
- *Target files:* `steps/basic_info_step.dart`, `property_dimensions_step.dart`, `condition_step.dart`, `amenities_step.dart`, `legal_details_step.dart`, `pricing_step.dart`, `media_contact_step.dart`, plus `providers/post_property_provider.dart` and `services/property_service.dart`.
- *Highest-effort:* commercial `buildingInventory` (nested object) and the full PG block incl. `pgHouseRules`.
- *Risk:* PG rows persist to `properties_residential` — keep that mapping. Don't add DB columns; everything extra goes to `metadata` (additive, non-destructive).

**Task 4 — Media parity.** Ensure Flutter uploads to `property-media`, sets `main_display_media_url`, supports per-photo category tags (default vs land category sets), and merges existing URLs on edit. Confirm compression behaviour is acceptable on mobile (React uses `compressMedia`).

**Task 5 — Builder Projects (only if confirmed in scope).** Mirror `BuilderProjectWizard` as a Flutter wizard + provider + service writing `builder_projects` with the same NULL-free discipline and the `available_units ≤ total_units` rule. Inventory subsystem is a separate follow-up. **Blocked on your scope answer.**

---

## PHASE 11 — UI rules (reaffirmed)
Do **not** copy React's inline styles/Tailwind. Flutter keeps its Material widgets, colours, typography, spacing, animations, and mobile navigation. Only *functionality* (fields, options, conditions, validation, payload) matches. Where React uses a `Select`, Flutter uses its existing dropdown/chip pattern; where React uses inline-styled cards, Flutter uses its own card style.

---

## PHASE 12 — Final QA checklist
- [ ] Every React field has a Flutter input **and** is persisted under the canonical key (Gap 2 list drained to zero).
- [ ] Every dropdown's option strings match §Phase 3 verbatim (enforced by Task 0 test).
- [ ] Validation matches §Phase 6 for all category×listingType combos (Task 2 tests green).
- [ ] Step-visibility matches §Phase 1.
- [ ] `metadata` + subtable + contact payloads match React for a fixed sample of each category (round-trip Flutter→web and web→Flutter).
- [ ] No NULLs written except `date`/FK columns (dbSafe discipline preserved).
- [ ] Media uploads to `property-media`, `main_display_media_url` set, categories tagged.
- [ ] Builder-project parity — **only if in scope** (else explicitly marked React-only).
- [ ] Flutter retains its own visual identity throughout.

---

## Open questions for you (need answers before Task 3/5)
1. **Builder Projects in Flutter — yes or no?** (Finding #5.) If yes, does inventory come too?
2. For the Flutter-only metadata keys in Gap 2, which are intentional Flutter extensions vs accidental renames I should fix to the React key?
3. Can you confirm the current `properties` / `properties_*` / `builder_projects` schemas match what these wizards write? The wizard payloads are my source; a fresh schema dump would let me verify column names/types before we write migrations (none should be needed — everything extra is additive JSONB — but worth confirming).