"""Extract every file from the "Full configuration files" sections into configs/<tab>/<path>.

A file in the document is a label paragraph whose first code span is the path, followed by a
code block. Usage: python3 -I build/extract-configs.py <pqc repo dir>
Writes configs/ and configs/MANIFEST.md (path, tab, label).
"""
import html, os, re, sys

R = sys.argv[1]
SRC, OUT = os.path.join(R, "src"), os.path.join(R, "configs")
MD = {"03-go.md": "go", "04-python.md": "python", "05-nodejs.md": "nodejs", "06-java.md": "java",
      "07-dotnet.md": "dotnet", "21-enforcement.md": "enforcement", "08-infrastructure.md": "infrastructure"}


def safe(p):
    p = p.strip().strip("`*").split()[0] if p.strip() else "unnamed"
    p = re.sub(r"^~/", "home/", p).lstrip("/").replace("..", "_")
    p = re.sub(r"[^A-Za-z0-9._/@+-]", "_", p)
    return p or "unnamed"


def put(tab, path, body, label, manifest, seen):
    rel = os.path.join(tab, safe(path))
    base, n = rel, 2
    while rel in seen:  # same file name shown twice (variants): keep both
        stem, ext = os.path.splitext(base)
        rel, n = f"{stem}.variant{n}{ext}", n + 1
    seen.add(rel)
    dst = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, "w", encoding="utf-8").write(body if body.endswith("\n") else body + "\n")
    manifest.append((rel, label.strip()[:160]))


def from_md(name, tab, manifest, seen):
    lines = open(os.path.join(SRC, name), encoding="utf-8").read().split("\n")
    start = next((i for i, l in enumerate(lines) if l.startswith("## Full configuration files")), None)
    if start is None:
        return
    i, label = start + 1, None
    while i < len(lines):
        l = lines[i]
        if re.match(r"^\s*```", l):
            fence = l.strip()[:3]
            indent = len(l) - len(l.lstrip())
            j, body = i + 1, []
            while j < len(lines) and not lines[j].strip().startswith(fence):
                body.append(lines[j][indent:] if lines[j][:indent].strip() == "" else lines[j])
                j += 1
            m = re.search(r"`([^`]+)`", label or "")
            if m:
                put(tab, m.group(1), "\n".join(body), label, manifest, seen)
            i, label = j + 1, None
            continue
        if l.strip():
            label = l
        i += 1


def from_html(path, tab, manifest, seen):
    h = open(path, encoding="utf-8").read()
    m = re.search(r'<h2 id="[^"]*full-configuration[^"]*"', h)
    if not m:
        return
    h = h[m.start():]
    pos = 0
    for m in re.finditer(r"<pre[^>]*><code[^>]*>(.*?)</code></pre>", h, re.S):
        # label = last heading or paragraph between the previous block and this one
        labels = re.findall(r"<(h[3-6]|p)[^>]*>(.*?)</\1>", h[pos:m.start()], re.S)
        pos = m.end()
        if not labels:
            continue
        # prefer the nearest label naming a file in a code span; else the nearest label
        named = [l for l in labels if re.search(r"<code>[^<]*[./][^<]*</code>", l[1])]
        heads = [l for l in labels if l[0] != "p"]
        raw = (named or heads or labels)[-1][1]
        text = html.unescape(re.sub("<[^>]+>", "", raw)).strip()
        c = re.search(r"<code>(.*?)</code>", raw, re.S)
        if c:
            path = html.unescape(re.sub("<[^>]+>", "", c.group(1)))
        else:
            w = next((w for w in text.split() if re.search(r"[./]", w) or re.match(r"^[\w-]+$", w)), None)
            if not w:
                continue
            path = w
        put(tab, path, html.unescape(m.group(1)), text, manifest, seen)


manifest, seen = [], set()
for name, tab in MD.items():
    from_md(name, tab, manifest, seen)
for f in sorted(os.listdir(os.path.join(SRC, "html-infra"))):
    tab = re.sub(r"[^a-z0-9]+", "-", f[:-5].lower()).strip("-")
    from_html(os.path.join(SRC, "html-infra", f), tab, manifest, seen)

with open(os.path.join(OUT, "MANIFEST.md"), "w", encoding="utf-8") as m:
    m.write("# Configuration files\n\nExtracted from each tab's \"Full configuration files\" section by "
            "`build/extract-configs.py`. The document text is the source; re-run the script after editing it.\n\n"
            "| File | Label in the document |\n| --- | --- |\n")
    for rel, label in manifest:
        m.write(f"| `{rel}` | {label.replace('|', '/')} |\n")
print("files", len(manifest))
for t in sorted({r.split('/')[0] for r, _ in manifest}):
    print(f"  {t}: {sum(1 for r, _ in manifest if r.startswith(t + '/'))}")
