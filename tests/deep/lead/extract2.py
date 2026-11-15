import json, re, sys, glob, os, html

OUT = os.path.dirname(os.path.abspath(__file__))
TR = sys.argv[1]  # transcript jsonl
FILES = sys.argv[2:]  # saved tool-result files

TABS = {'c02d62b2-67e7':('go',False),'610684f0-aa35':('python',False),'d02c414f-ccd4':('node',False),'4c9d8c6b-f4f3':('java',False),'88a41389-c93f':('dotnet',False),'143c638f-590a':('lb',False),'8868eb3f-63a6':('endpoints',False),'5bfb4cc4-ab9a':('network',False),'e86fe07a-cac9':('iot',False),
    'd8fe2c64-7cf3': ('edge', False), 'bda3ce4d-bf11': ('mesh', False),
    '4939fb11-df6b': ('databases', False), 'c3d96e94-4f34': ('hosts', False),
    'c645e972-553d': ('certificates', False), 'ea8fb0bb-ef44': ('waf', False),
    '10112461-0b3c': ('webservers', False), '28091f56-7418': ('clients', False),
    'ab9fe1da-cf13': ('enforcement', False), 'b5cf0064-6a9b': ('runbook', True),
    'afc77a21-4a57': ('infrastructure', True), 'c238c638-bd7c': ('config-index', True),
}

def parse_payload(s):
    out = []
    i = 0
    while True:
        j = s.find('{"verdict', i)
        if j < 0: break
        try:
            obj, end = json.JSONDecoder().raw_decode(s[j:])
            out.append(obj); i = j + end
        except Exception:
            i = j + 1
    return out

docs = {}
def add(obj):
    try:
        xml = obj['data']['xml']
    except Exception:
        return
    m = re.match(r"<doc node='([^']+)' rev='(\d+)'", xml)
    if m: docs[m.group(1)] = (xml, obj.get('rev'))

def texts_from(content):
    if isinstance(content, str): yield content
    elif isinstance(content, list):
        for c in content:
            if isinstance(c, dict):
                if 'text' in c: yield c['text']
                if 'content' in c: yield from texts_from(c['content'])

for f in FILES:
    for item in json.load(open(f)):
        for o in parse_payload(item.get('text', '')): add(o)
for line in open(TR):
    try: rec = json.loads(line)
    except Exception: continue
    msg = rec.get('message', {})
    if not isinstance(msg, dict): continue
    for c in msg.get('content', []) if isinstance(msg.get('content'), list) else []:
        if isinstance(c, dict) and c.get('type') == 'tool_result':
            for t in texts_from(c.get('content')):
                for o in parse_payload(t): add(o)

# --- block parsing
BLOCK_RE = re.compile(r"<(paragraph|table|codeBlock|list)\b([^>]*)>", re.S)

def attrs(a):
    return dict(re.findall(r"(\w+)='([^']*)'", a))

def strip(x):
    x = re.sub(r"<!\[CDATA\[(.*?)\]\]>", lambda m: m.group(1).replace('<', '\x00'), x, flags=re.S)
    x = re.sub(r"<mention [^>]*label='([^']*)'[^>]*/>", r"[\1]", x)
    x = re.sub(r"<[^>]+>", "", x)
    return html.unescape(x.replace('\x00', '<'))

def top_blocks(body):
    """Yield (kind, attrs, inner) for top-level blocks."""
    pos = 0; n = len(body)
    while True:
        m = BLOCK_RE.search(body, pos)
        if not m: return
        kind = m.group(1); a = attrs(m.group(2))
        if m.group(2).rstrip().endswith('/'):
            yield kind, a, ''; pos = m.end(); continue
        depth = 1; k = m.end()
        tag_re = re.compile(r"<(/?)%s\b[^>]*?(/?)>|<!\[CDATA\[.*?\]\]>" % kind, re.S)
        while depth:
            t = tag_re.search(body, k)
            if t.group(0).startswith('<![CDATA['):
                k = t.end(); continue
            if t.group(1): depth -= 1
            elif not t.group(2): depth += 1
            k = t.end()
        yield kind, a, body[m.end():k - len('</%s>' % kind)]
        pos = k

def table_rows(inner):
    rows = []
    for r in re.findall(r"<row\b[^>]*>(.*?)</row>", inner, re.S):
        cells = re.findall(r"<cell\b[^>]*>(.*?)</cell>", r, re.S)
        rows.append('| ' + ' | '.join(strip(c).strip().replace('\n', ' ') for c in cells) + ' |')
    return rows

def code_first2(inner, n=2):
    t = strip(inner)
    return '\n'.join(t.split('\n')[:n])

def render(kind, a, inner, full_code=False):
    if kind == 'paragraph':
        return strip(inner)
    if kind == 'table':
        return '\n'.join(table_rows(inner))
    if kind == 'codeBlock':
        c = strip(inner) if full_code else code_first2(inner)
        return "```%s\n%s\n```" % (a.get('language', ''), c)
    if kind == 'list':
        items = re.findall(r"<listItem\b[^>]*>(.*?)</listItem>", inner, re.S)
        outs = []
        for it in items:
            parts = []
            for k2, a2, in2 in top_blocks(it):
                parts.append(render(k2, a2, in2, full_code))
            outs.append('- ' + '\n  '.join(p.replace('\n', '\n  ') for p in parts))
        return '\n'.join(outs)
    return strip(inner)

report = []
for node, (short, parent) in TABS.items():
    if node not in docs:
        report.append(f"MISSING {short}"); continue
    xml, rev = docs[node]
    body = re.sub(r"^<doc[^>]*>|</doc>$", "", xml)
    blocks = list(top_blocks(body))
    L = []
    h1 = next((strip(i) for k, a, i in blocks if k == 'paragraph' and a.get('heading') == '1'), '')
    L.append(f"# TAB: {short}  node={node}  rev={rev}")
    L.append("\n## 1. H1 and lead paragraphs")
    L.append("H1: " + h1)
    paras = [strip(i) for k, a, i in blocks if k == 'paragraph' and 'heading' not in a and strip(i).strip()]
    for p in paras[:2]: L.append("\n" + p)
    L.append("\n## 2. Headings")
    for k, a, i in blocks:
        if k == 'paragraph' and a.get('heading') in ('2', '3'):
            L.append(("  " if a['heading'] == '3' else "") + f"H{a['heading']}: " + strip(i))
    L.append("\n## 3. Status matrix (first table)")
    first_tbl = next(((a, i) for k, a, i in blocks if k == 'table'), None)
    # prefer the table after a 'Status matrix' heading if one exists
    seen_sm = False
    for k, a, i in blocks:
        if k == 'paragraph' and a.get('heading') and 'status matrix' in strip(i).lower(): seen_sm = True
        elif seen_sm and k == 'table': first_tbl = (a, i); break
    if first_tbl: L.extend(table_rows(first_tbl[1]))
    else: L.append("(no table)")
    L.append("\n## 4. Full configuration files section")
    idx = None
    for n_, (k, a, i) in enumerate(blocks):
        if k == 'paragraph' and a.get('heading') == '2' and re.search(r'configuration files|config', strip(i), re.I):
            idx = n_
    if idx is None:
        L.append("(no 'Full configuration files' section)")
    else:
        for k, a, i in blocks[idx:]:
            if k == 'paragraph' and a.get('heading'):
                L.append(f"H{a['heading']}: " + strip(i))
            else:
                L.append(render(k, a, i))
    open(os.path.join(OUT, f"extract-{short}.txt"), 'w').write('\n'.join(L) + '\n')
    if parent:
        F = [f"# TAB: {short}  node={node}  doc rev={rev}", "# full text with block ids and hashes (id prefix 'mttvddjsrgd')", ""]
        for k, a, i in blocks:
            bid = a.get('id', ''); bid = bid if bid.startswith('mttvddjsrgd') else 'mttvddjsrgd' + bid
            hd = f" heading={a['heading']}" if 'heading' in a else ''
            F.append(f"[{kind_id}]" if False else f"[{k} id={bid} h={a.get('h','')} rev={a.get('rev','-')}{hd}]")
            F.append(render(k, a, i, full_code=True)); F.append("")
        open(os.path.join(OUT, f"extract-{short}.txt"), 'a').write('\n## 5. Full text with block ids\n' + '\n'.join(F) + '\n')
        open(os.path.join(OUT, f"extract-{short}.xml"), 'w').write(xml + '\n')
    report.append(f"ok {short} rev={rev} blocks={len(blocks)}")
print('\n'.join(report))
