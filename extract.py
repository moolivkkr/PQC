import json, base64, sys, re, os
src, out = sys.argv[1], sys.argv[2]
found = {}
pat = re.compile(r'\{"verdict":"allow".*?"frame":\{[^}]*\}\}', re.S)
with open(src) as f:
    for line in f:
        if 'bytes_b64' not in line: continue
        try: rec = json.loads(line)
        except Exception: continue
        def walk(o):
            if isinstance(o, str):
                if '"bytes_b64"' in o:
                    for m in pat.finditer(o):
                        try:
                            d = json.loads(m.group(0))['data']
                            found[d['name']] = base64.b64decode(d['bytes_b64'])
                        except Exception as e: pass
            elif isinstance(o, dict): [walk(v) for v in o.values()]
            elif isinstance(o, list): [walk(v) for v in o]
        walk(rec)
for n, b in found.items():
    open(os.path.join(out, n), 'wb').write(b); print(len(b), n)
