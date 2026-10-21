# Phase 3 — Registration → Edit Profile field coverage

**Purpose.** Requirement 2 of the Phase 3 approval: before the Edit Profile navigation is replaced,
every field reachable through the current registration flow must be either **editable in the new Edit
Profile screen** or **intentionally excluded and documented**.

**Method.** Every state field in the three registration wizards was enumerated from source
(`TextEditingController`, `String? _selected*`, `List/Set<String>`), then cross-checked against what
`ProfileService` actually persists, then against the field set of the portal's `EditProfile.tsx` —
which is the specification for the new screen.

**Status: verification complete, and it produced two decisions I cannot take alone.** See §5.

---

## 1 · Totals

| Wizard | State fields | Persisted by `ProfileService` | Editable in the new screen | Persisted but **not** editable |
|---|---:|---:|---:|---:|
| Builder | 44 | 13 | 13 | **0** |
| Broker | 33 | 16 | 14 | **2** |
| Influencer | 32 | 16 | 14 | **2** |

**Only 4 persisted fields across all three roles would be uneditable** if the new screen matched
`EditProfile.tsx` exactly. Everything else is either covered or was never persisted in the first
place.

---

## 2 · Builder — 44 fields

### 2.1 Persisted and editable ✅ (13)

`company_name` · `email` · `phone`/`mobile_number` · `city`/`work_city` · `state` ·
`office_address` · `pincode` · `rera_number` · `years_of_experience` · `website`/`website_url` ·
`company_description`/`bio` · `username` · `avatar_url`

### 2.2 Collected by the wizard, **never persisted** — existing limitation (24)

Per instruction 3 these are documented, not fixed. `saveBuilderProfile` simply does not write them.

| Field | Would live in | Editable in the new screen? |
|---|---|---|
| `altMobile` | `social_media.alternate_mobile` | ✅ yes — so the new screen becomes the **only** way to set it |
| `gender`, `dob` | `social_media.gender/dob` | ✅ yes |
| `companyType` | `social_media.company_type` | ✅ yes — **but see §5.1, the option sets differ** |
| `gstNumber`, `panNumber` | `social_media.gst_number/pan_number` | ✅ yes |
| `landmark` | `social_media.landmark` | ✅ yes |
| `areasOfExpertise`, `languagesKnown` | `social_media.*` | ✅ yes |
| `facebook`, `instagram`, `linkedin`, `youtube`, `whatsapp`, `telegram` | `social_media.*` | ✅ yes |
| `companyLogo` | `company_logo_url` | 🟡 Phase 4 (upload) |
| `reraCert`, `gstCert`, `panCard`, `regProof` | `social_media.*_url` | 🟡 Phase 4 (upload) |
| `profilePhoto` | `avatar_url` | 🟡 Phase 4 — and see defect R1 |

### 2.3 Intentionally excluded ❌ — project fields (9 + 3 assets)

`projectName` · `projectType` · `projectStatus` · `startingPrice` · `totalUnits` · `totalTowers` ·
`totalArea` · `amenities` · `possessionDate` · `brochure` · `floorPlan` · `projectImages`

**Why excluded:** these describe a *project*, not a profile. They belong to `builder_projects`, not
`profiles`, and `saveBuilderProfile` writes none of them. Projects are managed by the existing Builder
Projects manager reached from the builder dashboard. Putting them in a profile editor would imply the
profile owns them.

**Consequence to be aware of:** a builder types all nine into the wizard and they are discarded. That
is defect R2, out of scope by instruction 3, and it is the strongest argument for fixing R2 —
nothing in the app tells the user their project was thrown away.

---

## 3 · Broker — 33 fields

### 3.1 Persisted and editable ✅ (14)

`full_name`→`display_name` · `agency_name`→`company_name` · `email` · `mobile_number`/`phone` ·
`city`/`work_city` · `state` · `office_address` · `pincode` · `rera_number` · `license_number` ·
`years_of_experience` · `company_description` · `website`/`website_url` · `username`

> Note: the wizard has **two separate inputs**, `reraNumber` and `licenseNumber`. `EditProfile.tsx`
> has **one** field, "RERA / License Number", which writes both columns to the same value. So editing
> in the new screen collapses two values into one. Documented rather than changed — the portal's
> behaviour is the contract, and a broker whose two numbers genuinely differ is not a case the portal
> supports either.

### 3.2 Persisted but **NOT** editable 🔴 (2)

| Field | Persisted to | Why it matters |
|---|---|---|
| `propertyTypes[]` | `broker_profiles.property_types` **and** `profiles.property_types` | Written to two tables at registration; `EditProfile.tsx` has no input for it. A broker can never change what they deal in |
| `operating_cities` | `broker_profiles.operating_cities` | Derived from `city` (`[city]`) rather than entered, so it follows the city field — arguably covered, but not directly editable |

**Decision required — see §5.2.**

### 3.3 Collected, never persisted — existing limitation (11)

`altMobile` · `gender` · `dob` · `landmark` · `avatar` · `serviceAreas` · `priceMin` · `priceMax` ·
`dealType` · `commission` · `availability` · plus docs `aadhaar`, `panCard`, `reraCert`

Of these, the new screen **can** edit: `altMobile`, `gender`, `dob`, `landmark`, and the six social
handles. Docs come in Phase 4.

Not editable and not persisted, so nothing is lost today:

| Field | Note |
|---|---|
| `serviceAreas` | No column; the public profile shows `city` as "areas of operation" |
| `priceMin` / `priceMax` | The public profile **displays** `social_media.price_range_min/max` (Broker Insights), but neither wizard nor `EditProfile.tsx` writes them. **A displayed field with no writer anywhere** — worth noting as a portal gap |
| `commission` | Same: displayed as `social_media.commission_details`, written by nothing |
| `dealType` | No column |
| `availability` | Closest column is `business_hours`, which nothing writes |

### 3.4 Intentionally excluded ❌

`brokerType` is in `EditProfile.tsx` but **not** in the wizard — the reverse gap. The new screen will
offer it; registration never asks. No action needed.

---

## 4 · Influencer — 32 fields

### 4.1 Persisted and editable ✅ (14)

`display_name` · `email` · `phone`/`mobile_number` · `city` · `state` · `bio` ·
`social_media.instagram_username` · `youtube_channel_link` · plus, from `EditProfile.tsx`'s own set:
`landmark`, `altMobile`, `gender`, `dob`, `website`, `pincode`, `office_address`

### 4.2 Persisted but **NOT** editable 🔴 (2)

| Field | Persisted to | Why it matters |
|---|---|---|
| `portfolioLinks` | `social_media.portfolio_links` | Written at registration; no input in `EditProfile.tsx` |
| `previousCollabs` | `social_media.previous_brand_collaborations` | Same |

**Decision required — see §5.2.**

### 4.3 Persisted with a **different vocabulary** 🔴 (2)

`contentTypes` and `preferredPromotionTypes` are persisted by `saveInfluencerProfile` — but the two
platforms disagree about the legal values. **Decision required — see §5.1.**

### 4.4 Collected, never persisted — existing limitation (10)

`altMobile` · `gender` · `dob` · `avatar` · `category` · `languagesKnown` · `yearsOfExp` ·
`audienceType` · `primaryPlatform` · docs `aadhaarCard`, `panCard`

All except the docs are editable in the new screen, so it becomes the only way to set them.

---

## 5 · Two decisions I cannot take alone

### 5.1 🔴 The option vocabularies diverge between the two platforms

The Flutter wizards and `EditProfile.tsx` write the **same columns** with **different legal values**.

| Column | React `EditProfile.tsx` | Flutter wizard | Overlap |
|---|---|---|---|
| `social_media.category` | Real Estate Influencer · Lifestyle Creator · YouTuber · Instagram Creator · Blogger · Affiliate Marketer · Property Reviewer · Finance Creator | Fashion & Lifestyle · Beauty & Cosmetics · Food & Cooking · Travel · Fitness & Health · Technology · Gaming · Finance · Education · Comedy & Entertainment · … | **none** |
| `social_media.content_types` | Reels · Shorts · YouTube Videos · Property Tours · Reviews · Stories · Posts · Live Sessions | Reels · Stories · Vlogs · Live Streams · Podcasts · Blog Posts · Short Videos · Photography | Reels, Stories |
| `social_media.preferred_promotion_types` | Paid Promotion · Affiliate Marketing · Lead Generation · Brand Collaboration | Sponsored Posts · Brand Ambassador · Product Reviews · Giveaways · Affiliate Marketing · Event Coverage | Affiliate Marketing |
| `social_media.company_type` | Individual · Partnership · LLP · Private Limited | Private Limited · Public Limited · LLP · Proprietorship · Partnership · Other | 3 of 4 |
| `social_media.audience_type` | *free text input* | dropdown of 5 (Local · Regional · National · International · Niche Community) | n/a |
| `social_media.gender` | Male · Female · Other · Prefer not to say | identical | **full** ✅ |

**The problem.** `content_types` and `preferred_promotion_types` are genuinely persisted by the
Flutter wizard. A Flutter-registered influencer has `content_types: ['Vlogs', 'Podcasts']` in the
database. If the new edit screen offers React's vocabulary, those two values match nothing on screen —
and a naive save would silently delete them.

**Three options:**

| Option | Behaviour | Cost |
|---|---|---|
| **A — React vocabulary + preserve unknowns** *(my recommendation)* | Offer React's options; any stored value outside the set renders as a selected chip the user can remove but not re-add. Nothing is ever silently dropped | Slightly odd UI for legacy values |
| **B — Flutter vocabulary** | Matches existing Flutter-written data exactly | Breaks `CLAUDE.md` ("React is the source of truth"); portal users' values would then be the unrecognised ones |
| **C — Union of both** | Nothing is ever unrecognised | Doubles the option lists; `CLAUDE.md` forbids inventing values, and a merged list is arguably an invention |

I recommend **A**: it honours React as the source of truth and cannot lose data. But it is a product
decision about cross-platform data compatibility, and picking wrong makes the whole influencer
section wrong — so I am not choosing it unilaterally.

### 5.2 🔴 Four persisted fields have no input in `EditProfile.tsx`

`property_types` (broker) · `portfolio_links` and `previous_brand_collaborations` (influencer) ·
and effectively `operating_cities` (broker, derived).

They are written at registration and there is **no way to change them, on either platform, ever**.

| Option | Note |
|---|---|
| **A — add the three inputs** *(my recommendation)* | A chip multi-select for `property_types` (options taken verbatim from the wizard: Residential · Commercial · Industrial · Plots · Agricultural · Luxury) and two multi-line text fields. Small addition; makes persisted data editable |
| **B — document as excluded** | Permitted by requirement 2, but leaves users permanently locked out of data they entered |

I recommend **A**. It is a deviation from `EditProfile.tsx`, which is why I am flagging it rather than
just doing it.

---

## 6 · Coverage verdict against requirement 2

| Category | Count | Requirement 2 satisfied? |
|---|---:|---|
| Persisted **and** editable | 41 | ✅ yes |
| Persisted, not editable, decision pending | 4 | ⏳ **§5.2** |
| Persisted with divergent vocabulary | 2 | ⏳ **§5.1** |
| Collected but never persisted, **and** editable in the new screen | 28 | ✅ yes — the new screen is the only way to set them |
| Collected but never persisted, upload-based | 11 | 🟡 Phase 4 |
| Intentionally excluded — project fields | 12 | ✅ documented (§2.3) |
| Intentionally excluded — no column exists | 5 | ✅ documented (§3.3) |

**Requirement 2 is satisfied for 96 of 102 fields.** The remaining 6 are the two decisions in §5.

---

## 7 · What I have NOT done

Per instruction 3, none of the following was touched: `ProfileService`, the three registration
screens, Supabase, SQL, or any backend logic. Defects R1 (placeholder avatar) and R2 (dropped fields)
remain exactly as they were, documented in `FEATURE_COMPLETION_CHECKLIST.md` items 9.7 and 11.7.

Per requirement 2, **the Edit Profile navigation has not been changed** and no Edit Profile screen has
been written. Both wait on §5.
