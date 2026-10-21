"""Extract every <Select> option set bound to a PropertyFormData field.

The review (Q3) requires these be taken verbatim from the step JSX rather than
hand-typed, because a differing enum string silently breaks web filters/reads.

Parses actual <Select> ... </Select> spans: the formData binding is read from
the OPENING TAG ONLY, so an <Input value={formData.x}> sitting before an
unrelated Select can no longer be mis-attributed to it.
"""
import io, re, json, os

SP = r"C:/Users/USER/AppData/Local/Temp/claude/c--Users-USER-Desktop-Flutter/eaebe9cc-357a-46a1-8018-7398bb9efccc/scratchpad/t0"
STEPS = 'propcid/src/components/PropertyWizard/steps'

BIND = re.compile(r"value=\{\s*formData\.((?:buildingInventory\.)?[A-Za-z0-9_]+)")
ITEM = re.compile(r"<SelectItem\s+value=\"([^\"]*)\"")
NL = chr(10)

result = {}
unbound = []

for fname in sorted(os.listdir(STEPS)):
    if not fname.endswith('.tsx'):
        continue
    path = os.path.join(STEPS, fname).replace(chr(92), '/')
    src = io.open(path, encoding='utf-8').read()

    for m in re.finditer(r"<Select\b", src):
        # Opening tag spans from '<Select' to its first unescaped '>'
        tag_end = src.find('>', m.start())
        close = src.find('</Select>', tag_end)
        if tag_end == -1 or close == -1:
            continue
        open_tag = src[m.start():tag_end]
        body = src[tag_end:close]

        vals = ITEM.findall(body)
        if not vals:
            continue

        b = BIND.search(open_tag)
        line = src[:m.start()].count(NL) + 1
        if not b:
            unbound.append({'file': fname, 'line': line, 'options': vals})
            continue

        field = b.group(1)
        entry = result.setdefault(field, {'sources': [], 'options': []})
        entry['sources'].append('%s:%d' % (fname, line))
        for v in vals:
            if v not in entry['options']:
                entry['options'].append(v)

io.open(SP + '/select_options.json', 'w', encoding='utf-8').write(
    json.dumps({'bound': result, 'unbound': unbound}, indent=1, ensure_ascii=False))

print('bound fields: %d   unbound Selects: %d' % (len(result), len(unbound)))
print('-' * 78)
for k in sorted(result):
    o = result[k]['options']
    print('%-26s %2d  %s' % (k, len(o), ' | '.join(o)[:110]))
