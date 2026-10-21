# T0 — shared ground truth generators

These scripts parse the React website source and emit the Dart ground-truth
files for the listing migration. They exist because CLAUDE.md forbids inventing
dropdown values or metadata keys, and because a single mistyped enum string
silently breaks web filters and reads with no compile error to catch it.

**Do not hand-edit the generated files.** Change React, re-run, re-test.

## Generated

| Output | Contents |
|---|---|
| `lib/screens/post_property/listing_constants.dart` | every option/amenity list, select enum, media category, area-unit table |
| `lib/screens/post_property/listing_field_keys.dart` | the 339-key metadata allow-list, `missingMetadataFields`, nested-object and project-tag key sets |

Two files in the same directory are **hand-written**, because they encode
judgement rather than extractable fact:

- `listing_value_aliases.dart` — legacy→canonical value maps (an alias is a
  decision about intent, not a fact in the source)
- `listing_validators.dart` — a direct port of `requiredFields.ts`

## Running

Run from the directory that contains both `FLUTTER-APP/` and `propcid/`
(the React checkout), in this order:

```sh
python FLUTTER-APP/scripts/t0/extract_arrays.py    # const option arrays
python FLUTTER-APP/scripts/t0/extract_selects.py   # <Select> option sets in JSX
python FLUTTER-APP/scripts/t0/gen_dart.py          # -> listing_constants.dart
python FLUTTER-APP/scripts/t0/gen_keys.py          # -> listing_field_keys.dart
```

The two `extract_*` scripts write intermediate JSON to the scratchpad path in
their `SP` constant; point that at any writable directory.

## Verifying

```sh
flutter test test/listing_constants_parity_test.dart
flutter test test/listing_validators_parity_test.dart
```

The parity test's expected values are typed **independently** of these
generators, straight from the React source. That independence is the point: if a
parser here is wrong, the test fails. A test generated from the same extraction
would only prove the extractor agrees with itself.

## Known source quirks, preserved deliberately

- `residentialSocietyAmenityList` lists `Visitor Parking` twice (47 entries, 46
  distinct). Kept verbatim; dedupe belongs in the UI.
- `missingMetadataFields` lists 249 entries, 3 duplicated
  (`balconyPg`, `mealsIncluded`, `roomCleaningFrequency`). Deduped to 246,
  source order preserved.
- `linenChangeFrequency` and `roomCleaningFrequency` are *different* option sets
  (Fortnightly vs On Demand) despite looking alike.
