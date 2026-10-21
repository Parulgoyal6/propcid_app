import io, re, json, os

SP = r"C:/Users/USER/AppData/Local/Temp/claude/c--Users-USER-Desktop-Flutter/eaebe9cc-357a-46a1-8018-7398bb9efccc/scratchpad/t0"
BASE = 'propcid/src'

WANT = ['propertyTypes', 'residentialSubTypeGroups', 'residentialappartment', 'landtypes',
        'landTypeOptions', 'plotTypeOptions', 'landUseMasterPlanOptions', 'landSoilTypes',
        'pgtype', 'buildingTypeOptions',
        'residentialSocietyAmenityList', 'residentialFlatAmenityList',
        'residentialParkingAmenityList', 'residentialTenantPreferenceList',
        'commercialSuitableForList', 'commercialOfficeBuildingAmenityList',
        'commercialRetailWarehouseAmenityList', 'commercialWashroomList',
        'commercialParkingList', 'commercialOtherParkingList',
        'PgRoomAmenityList', 'PgCommonAreaAmenityList', 'PgSafetyAndSecurityList',
        'PgTenantRulesList', 'OtherGeneralAmenitiesList',
        'defaultImageCategories', 'landImageCategories', 'roomFeatures']

BACKSLASH = chr(92)
OPENERS = '[{('
CLOSERS = ']})'
QUOTES = '"' + chr(39) + '`'


def balanced(text, i):
    """Return index just past the bracket that opens at position i."""
    depth = 0
    j = i
    instr = False
    q = ''
    while j < len(text):
        c = text[j]
        if instr:
            if c == BACKSLASH:
                j += 2
                continue
            if c == q:
                instr = False
        elif c in QUOTES:
            instr = True
            q = c
        elif c in OPENERS:
            depth += 1
        elif c in CLOSERS:
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return -1


found = {}
for root, _dirs, files in os.walk(BASE):
    for f in files:
        if not f.endswith(('.ts', '.tsx')):
            continue
        p = os.path.join(root, f).replace(chr(92), '/')
        try:
            src = io.open(p, encoding='utf-8').read()
        except Exception:
            continue
        for name in WANT:
            if name in found:
                continue
            m = re.search(r"const\s+" + name + r"\s*(?::[^=]*?)?=\s*\[", src)
            if not m:
                continue
            s = m.end() - 1
            e = balanced(src, s)
            if e == -1:
                continue
            found[name] = {'file': p, 'line': src[:m.start()].count(chr(10)) + 1,
                           'raw': src[s:e]}

io.open(SP + '/arrays_raw.json', 'w', encoding='utf-8').write(
    json.dumps(found, indent=1))

for n in WANT:
    if n in found:
        r = found[n]
        print('%-38s %-32s:%-5d len=%d' % (n, r['file'].split('/')[-1], r['line'], len(r['raw'])))
    else:
        print('%-38s *** NOT FOUND ***' % n)
