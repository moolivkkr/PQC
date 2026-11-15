#!/usr/bin/env python3
# Summarise out-<label>.txt from run-cases.sh into one matrix (rows = check, columns = runtime).
import json, re, sys, pathlib
d = pathlib.Path(__file__).parent
labels = ['node22', 'node24', 'lambda22-pq', 'lambda24-pq', 'lambda22-aws', 'lambda24-aws']
rows, order = {}, []
def put(k, lab, v):
    if k not in rows: rows[k] = {}; order.append(k)
    rows[k][lab] = v
def short(s):
    s = s.strip()
    m = re.search(r'group=(\S+)', s); g = m.group(1) if m else None
    c = re.search(r'cert=(\S+)', s); a = re.search(r'alert ([a-z ]+)', s); r = re.search(r'cn=\S+', s)
    if a: return 'FAIL ' + a.group(1).strip()
    out = (g or '') + (' cert=' + c.group(1) if c else '') + (' ' + r.group(0) if r else '')
    return out.strip() or s[:40]
for lab in labels:
    f = d / f'out-{lab}.txt'
    if not f.exists(): continue
    port, grp, sub = None, None, ''
    for line in f.read_text().splitlines():
        if line.startswith('failed '): put('srv ' + line.split(' :: ')[0][7:], lab, 'FAIL ' + line.split(' :: ')[1][:50])
        m = re.match(r'-- (\d+)\s+(.*)', line)
        if m: port = m.group(1) + ' ' + m.group(2); continue
        m = re.match(r'\s+(PQ client|classical client|TLS1.2 client|RSA-only sigalgs|ECDSA-only|SNI \S+ PQ|PQ \+ client cert|PQ, no cert|classical \+ cert):\s*(.*)', line)
        if m and port:
            val = m.group(2)
            if ' | classical: ' in val:
                p, c = val.split(' | classical: '); put(f'srv {port} :: {m.group(1)}', lab, short(p)); put(f'srv {port} :: {m.group(1)[:-3]} classical', lab, short(c))
            else: put(f'srv {port} :: {m.group(1)}', lab, short(val))
            continue
        if line.startswith('## '): sub = line[3:] + ' '
        if line.startswith('{"group"'):
            j = json.loads(line); sub = ''
            grp = j['group'] + ' ' + ' '.join(x for x in [('XCA=' + j['NODE_EXTRA_CA_CERTS'].split('/')[-1]) if j['NODE_EXTRA_CA_CERTS'] else '',
                ('SSL_CERT_FILE') if j['SSL_CERT_FILE'] else '', ' '.join(j['execArgv']), j['NODE_OPTIONS'] or ''] if x)
        elif line.startswith('{"case"'):
            j = json.loads(line)
            v = ('ok ' + (j.get('group') or str(j.get('status', '')))) if j.get('ok') else 'FAIL ' + str(j.get('error') or j.get('threw'))
            k = f"cli [{grp}] {sub}{j['case']}"
            if k in rows and lab in rows[k]: k += ' (2nd line)'
            put(k, lab, v)
print('| check | ' + ' | '.join(labels) + ' |')
print('|---' * (len(labels) + 1) + '|')
for k in order:
    vals = [rows[k].get(l, '-') for l in labels]
    flag = '' if len(set(vals[:4])) == 1 else ' **DIFF**'
    print(f'| {k}{flag} | ' + ' | '.join(vals) + ' |')
