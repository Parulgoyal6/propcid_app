"""Generate listing_field_keys.dart from the extracted React metadata surface."""
import io, json

SP = r"C:/Users/USER/AppData/Local/Temp/claude/c--Users-USER-Desktop-Flutter/eaebe9cc-357a-46a1-8018-7398bb9efccc/scratchpad/t0"
OUT = 'FLUTTER-APP/lib/screens/post_property'
NL = chr(10)
Q = chr(39)

d = json.load(io.open(SP + '/metadata_keys.json', encoding='utf-8'))
s = lambda x: Q + x + Q

# missingMetadataFields verbatim, order preserved, duplicates noted
mm = d['missingMetadataFields']
seen, dupes, mm_unique = set(), [], []
for k in mm:
    if k in seen:
        dupes.append(k)
    else:
        seen.add(k)
        mm_unique.append(k)

L = []
L.append('''// GENERATED FROM REACT SOURCE — DO NOT HAND-EDIT.
//
// The authoritative metadata allow-list for the listing migration, parsed out
// of propcid/src/components/PropertyWizard/PropertyWizard.tsx by
// scripts/t0/gen_keys.py.
//
// final-architecture-review.md NEW-2: the real React metadata surface is ~340
// keys, not the 99 the migration specification implies. The parity target is
// the full set below, and any React key no Flutter input collects is simply
// absent from app-created rows.
//
// CLAUDE.md forbids inventing metadata keys — so add nothing here by hand.
// Regenerate instead; listing_constants_parity_test.dart guards the counts.''')

L.append('')
L.append('/// Every distinct key React can write to `properties.metadata`.')
L.append('/// Union of the explicit fillMetadata calls, the missingMetadataFields')
L.append('/// catch-all, and the direct `metadata.x =` assignments.')
L.append('const Set<String> kAllReactMetadataKeys = {')
for k in d['all_metadata_keys']:
    L.append('  %s,' % s(k))
L.append('};')

L.append('')
L.append('/// The `missingMetadataFields` catch-all (PropertyWizard.tsx:1664), verbatim')
L.append('/// and in source order. React feeds this straight to fillMetadata, so every')
L.append('/// key here is written with a typed-empty value when the form leaves it blank.')
L.append('///')
L.append('/// React lists %d entries; %d are duplicated in its own source' % (len(mm), len(dupes)))
L.append('/// (%s). Order is preserved; duplicates removed.' % ', '.join(sorted(set(dupes))))
L.append('const List<String> kMissingMetadataFields = [')
for k in mm_unique:
    L.append('  %s,' % s(k))
L.append('];')

L.append('')
L.append('/// Keys React assigns directly rather than through fillMetadata.')
L.append('/// `buildingInventory` and `pgHouseRules` are nested objects;')
L.append('/// `mediaCategories` is index-aligned with `media_urls`.')
L.append('const Set<String> kDirectAssignedMetadataKeys = {')
for k in d['direct_assign']:
    L.append('  %s,' % s(k))
L.append('};')

L.append('')
L.append('/// Builder-project tag keys. React DELETES these when no project is')
L.append('/// selected, rather than writing an empty value — so a merge-on-update')
L.append('/// that only ever adds keys would strand a stale tag. Relevant to T5.')
L.append('const Set<String> kProjectTagMetadataKeys = {')
for k in d['conditional_delete']:
    L.append('  %s,' % s(k))
L.append('};')

L.append('')
L.append('/// Sub-keys of the nested `metadata.pgHouseRules` object.')
L.append('const List<String> kPgHouseRuleKeys = [')
for k in d['pgHouseRules_subkeys']:
    L.append('  %s,' % s(k))
L.append('];')

L.append('')
L.append('/// Nested-object metadata keys. Phase 0 preserves these through the')
L.append('/// update-time merge without hydrating them into the provider bag;')
L.append('/// real editing support arrives with the category parity phases.')
L.append('const Set<String> kNestedObjectMetadataKeys = {')
for k in ['buildingInventory', 'pgHouseRules']:
    L.append('  %s,' % s(k))
L.append('};')

io.open(OUT + '/listing_field_keys.dart', 'w', encoding='utf-8').write(NL.join(L) + NL)
print('wrote listing_field_keys.dart')
print('  all keys            : %d' % len(d['all_metadata_keys']))
print('  missingMetadataFields: %d listed, %d unique, dupes=%s'
      % (len(mm), len(mm_unique), sorted(set(dupes))))
print('  direct assign       : %d' % len(d['direct_assign']))
print('  project tag (delete): %s' % d['conditional_delete'])
