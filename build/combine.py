"""Combine the per-chapter HTML fragments in build/tabs/ into one white paper.

Usage: python3 -I build/combine.py <pqc repo dir> [document ...]
Documents (DOCS below): guide (the complete reference), paper (white paper), exec (executive summary),
go, python, nodejs, java, dotnet (language documents). Default: all.
Writes build/out/<document>.html (cover, numbered contents) and build/out/<document>-docx.html (body only),
and prints "<document> <output path>" lines that build/build.sh renders to PDF and DOCX.

What it does to the chapters:
- numbers chapters (1, 2, ... and 6.1, 6.2 for sub-chapters; appendices keep their letters) and builds a linked
  contents list with each top-level chapter's sections;
- gives every heading a document-wide id: ch-<chapter slug> for the h1, ch-<chapter slug>--<id> below it, so
  "#ch-12-detection" or "#ch-03-go--how-to-test" link across chapters;
- replaces each chapter's "Full configuration files" section with a table of links to the files in configs/
  (configs/MANIFEST.md, written by build/extract-configs.py); the code stays in the repository;
- shortens any other code block over MAX_LINES lines to an excerpt;
- turns REPO/<path> links into repository links and links file names in the configuration index.
"""
import html, os, re, sys

R = sys.argv[1]
T = os.path.join(R, "build", "tabs")
GH = "https://github.com/moolivkkr/PQC"
MAX_LINES = 20
# (file in build/tabs, level, doc tab id used by cross-tab refs in the exported infrastructure HTML)
GUIDE = [
    ("10-introduction.html", 0, "2b549c4f-a403"), ("11-use-cases.html", 0, None), ("12-detection.html", 0, None),
    ("13-inventory.html", 0, None), ("14-compute.html", 0, None), ("15-languages.html", 0, "5dd6e4e1-9c38"),
    ("03-go.html", 1, "f452a156-1a48"), ("04-python.html", 1, "35b45b8c-c6f8"),
    ("05-nodejs.html", 1, "d69fae22-fa1f"), ("06-java.html", 1, "cd465386-557e"),
    ("07-dotnet.html", 1, "c09219a7-69d4"),
    ("08-infrastructure.html", 0, "c0e73cdc-fca7"), ("Load balancers.html", 1, "bb21387b-4f66"),
    ("Edge and API front doors.html", 1, "6d11c1c8-dcc8"), ("AWS service endpoints.html", 1, "5a29f676-6958"),
    ("Network devices and egress.html", 1, "c2c97bfd-040d"), ("IoT.html", 1, "27172d37-a5c2"),
    ("Service mesh.html", 1, "569dd476-c063"), ("Databases and data services.html", 1, "d9065243-9ab3"),
    ("Hosts and OS.html", 1, "99613846-4046"), ("Certificates (ML-DSA).html", 1, "38ead846-eb16"),
    ("WAF.html", 1, "37cfac3b-4ca1"), ("Web servers and proxies.html", 1, "f7dff530-a0a0"),
    ("Mobile, desktop and CLI clients.html", 1, "89d3721c-f2a1"),
    ("21-enforcement.html", 0, "0803191b-9855"), ("23-rollout-gaps.html", 0, None),
    ("24-appendix-tests.html", 0, None), ("22-config-index.html", 0, "f5950343-31dd"), ("25-sources.html", 0, None),
]
LANGS = [("go", "Go", "03-go", "Go"), ("python", "Python", "04-python", "Python"),
         ("nodejs", "Node.js", "05-nodejs", "Nodejs"), ("java", "Java", "06-java", "Java"),
         ("dotnet", ".NET", "07-dotnet", "dotnet")]
DATE = "2026-11-16"
DOCS = {
    "guide": dict(out="PQC-Detection-and-Remediation", order=GUIDE, toc=2,
                  title="Post-Quantum TLS on AWS: Complete Guide",
                  sub="Detection, inventory and remediation by language, compute type and infrastructure service: "
                      "the full reference",
                  blurb="Every chapter in full: use cases, detection, inventory, solutions by compute type, the five "
                        "language chapters, twelve infrastructure areas, enforcement, rollout, test appendix, "
                        "configuration index and sources. For a short read, see the white paper and the executive "
                        "summary; language teams have their own documents."),
    "paper": dict(out="docs/PQC-White-Paper", toc=2,
                  order=[("paper-01-introduction.html", 0, None), ("paper-02-use-cases.html", 0, None),
                         ("paper-03-detection.html", 0, None), ("paper-04-inventory.html", 0, None),
                         ("paper-05-compute.html", 0, None), ("paper-06-languages.html", 0, None)]
                        + [(f"summary-{k}.html", 1, None) for k, *_ in LANGS]
                        + [("paper-07-infrastructure.html", 0, None), ("paper-08-enforcement.html", 0, None),
                           ("paper-09-rollout.html", 0, None), ("paper-10-documents.html", 0, None)],
                  title="Post-Quantum TLS on AWS",
                  sub="White paper: what we are solving, how we detect and track it, and how we fix it by compute "
                      "type and language",
                  blurb="The approach in brief: what \"PQC-enabled\" means, the use cases, detection with AWS logs "
                        "and Zeek, the inventory and dashboards, solutions by compute type, one page per language, "
                        "infrastructure, enforcement and the rollout. Each language team has its own detailed "
                        "document; the complete guide has every detail."),
    "exec": dict(out="docs/PQC-Executive-Summary", toc=0, numbered=False,
                 order=[("exec-summary.html", 0, None)],
                 title="Post-Quantum TLS on AWS: Executive Summary",
                 sub="The problem, what we found, the plan and the decisions we need", blurb=""),
}
for key, name, chap, fname in LANGS:
    DOCS[key] = dict(out=f"docs/languages/PQC-{fname}", toc=2,
                     order=[(f"summary-{key}.html", 0, None), ("lang-context.html", 0, None),
                            (f"{chap}.html", 0, None), (f"tests-{key}.html", 0, None)],
                     titles={f"summary-{key}.html": "Summary for " + name + " teams",
                             f"{chap}.html": name + ": detailed guide"},
                     title=f"Post-Quantum TLS on AWS: {name}",
                     sub=f"For {name} application teams: what to change on Lambda, ECS, EKS and EC2, every case, "
                         "how to test, and the evidence",
                     blurb=f"Start with the one-page summary. The detailed guide covers every {name} version, the "
                           "cases teams meet (own keystores, custom CA trust, mutual TLS, explicit TLS settings, FIPS, "
                           "libraries with their own TLS), how to test and roll back, and the configuration files. "
                           "The last chapter lists every end-to-end test case run for " + name + ".")
CONFIG_DIR = {"03-go": "go", "04-python": "python", "05-nodejs": "nodejs", "06-java": "java", "07-dotnet": "dotnet",
              "21-enforcement": "enforcement", "08-infrastructure": "infrastructure"}
TAB_DIR = {"Go": "go", "Python": "python", "Node.js": "nodejs", "Java": "java", ".NET": "dotnet",
           "Enforcement": "enforcement", "Enforcement and guardrails": "enforcement"}
ROLLOUT = ("<p><em>Rollout loop: 1 Classify, 2 Change request, 3 Release, 4 Verify, "
           "repeated per release cycle.</em></p>")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def text(h):
    return html.unescape(re.sub("<[^>]+>", "", h)).strip()


def repo_url(path):
    path = path.strip("/")
    kind = "tree" if os.path.isdir(os.path.join(R, path)) else "blob"
    return f"{GH}/{kind}/main/{path}"


# configs/MANIFEST.md: | `folder/path` | label |
MANIFEST = {}
for line in open(os.path.join(R, "configs", "MANIFEST.md"), encoding="utf-8"):
    m = re.match(r"\| `([^`]+)` \| (.*) \|\s*$", line)
    if m and "/" in m.group(1):
        MANIFEST.setdefault(m.group(1).split("/")[0], []).append((m.group(1), m.group(2)))


def md_inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)


def config_table(folder):
    rows = MANIFEST.get(folder, [])
    if not rows:
        return "<p>No configuration files for this chapter.</p>"
    body = "".join(
        f'<tr><td><a href="{repo_url("configs/" + p)}"><code>configs/{html.escape(p)}</code></a></td>'
        f"<td>{md_inline(label)}</td></tr>" for p, label in rows)
    return (f'<p>The complete files for this chapter are in the repository under '
            f'<a href="{repo_url("configs/" + folder)}"><code>configs/{folder}/</code></a>. '
            f"This paper shows only the main change from each; copy from the repository, not from the paper. "
            f"{len(rows)} files:</p><table><thead><tr><th>File</th><th>What it is</th></tr></thead>"
            f"<tbody>{body}</tbody></table>")


def strip_full_config(h, folder):
    m = re.search(r'<h2 id="([^"]*full-configuration[^"]*)"[^>]*>.*?</h2>', h, re.S)
    if not m:
        return h, 0
    end = re.search(r"<h[12][ >]", h[m.end():])
    stop = m.end() + end.start() if end else len(h)
    removed = h[m.start():stop].count("\n")
    new = f'<h2 id="{m.group(1)}">Configuration files</h2>\n{config_table(folder)}\n'
    return h[:m.start()] + new + h[stop:], removed


def shorten_pre(h, src_name):
    def cut(m):
        code = m.group(2)
        lines = code.split("\n")
        if len(lines) <= MAX_LINES:
            return m.group(0)
        keep = "\n".join(lines[:MAX_LINES - 4])
        return (f"{m.group(1)}{keep}\n…</code></pre><p class=\"excerpt\"><em>Excerpt: first {MAX_LINES - 4} of "
                f"{len(lines)} lines. Full text: <a href=\"{repo_url('src/' + src_name)}\"><code>src/{src_name}</code>"
                f"</a>.</em></p>")
    return re.sub(r"(<pre[^>]*><code[^>]*>)(.*?)</code></pre>", cut, h, flags=re.S)




def chapter_ids(order):
    return {"ch-" + slug(f[:-5]) for f, *_ in order}


# a link to a chapter missing from the current document goes to the document where that chapter lives
HOME = {}
for _key in ["exec", "paper", "guide"] + [k for k, *_ in LANGS]:
    for _c in chapter_ids(DOCS[_key]["order"]):
        if _key in [k for k, *_ in LANGS] or _c not in HOME:
            HOME[_c] = _key
for _key in [k for k, *_ in LANGS]:  # the language chapters belong to their language document
    for _c in chapter_ids(DOCS[_key]["order"]):
        HOME[_c] = _key


def doc_url(key):
    return f"{GH}/blob/main/{DOCS[key]['out']}.pdf"


def link_index_row(m):
    row = m.group(0)
    cells = re.findall(r"<td>(.*?)</td>", row, re.S)
    if not cells:
        return row
    c = re.search(r"<code>(.*?)</code>", cells[0], re.S)
    tab = text(cells[-1])
    folder = TAB_DIR.get(tab) or slug(tab)
    if not c or folder not in MANIFEST:
        return row
    name = html.unescape(c.group(1)).split()[0].lstrip("/").replace("~/", "home/")
    hits = [p for p, label in MANIFEST[folder] if re.match(r"`?" + re.escape(name), label.lstrip("`/"))] or \
           [p for p, _ in MANIFEST[folder] if p.endswith("/" + name.split("/")[-1])]
    if not hits:
        return row
    return row.replace(c.group(0), f'<a href="{repo_url("configs/" + hits[0])}">{c.group(0)}</a>', 1)


CSS = """
body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;font-size:10.5pt;line-height:1.45;color:#1a1a1a;background:#fff;max-width:none}
h1{font-size:20pt;border-bottom:2px solid #1f3a5f;color:#1f3a5f;padding-bottom:4px;page-break-before:always;margin-top:0}
h2{font-size:14pt;margin-top:18px;color:#1f3a5f}h3{font-size:12pt}h4{font-size:11pt}
table{border-collapse:collapse;width:100%;margin:8px 0;font-size:9pt;page-break-inside:auto}
th,td{border:1px solid #999;padding:4px 6px;vertical-align:top;text-align:left}
th{background:#e8edf3} tr{page-break-inside:avoid}
code{font-family:Menlo,Consolas,monospace;font-size:8.5pt;background:#f2f2f2;padding:0 2px;word-break:break-word}
code.nb{white-space:nowrap;word-break:normal}
pre{background:#f2f2f2;padding:8px;font-size:8pt;white-space:pre-wrap;word-break:break-all;border:1px solid #ddd}
pre code{background:none;padding:0}
p.excerpt{font-size:9pt;margin-top:-4px}
.cover{text-align:left;padding-top:160px}.cover h1{page-break-before:avoid;border:none;font-size:28pt}
.cover .sub{font-size:14pt;color:#444}.cover .meta{margin-top:60px;font-size:10.5pt}
.toc ul{padding-left:0}.toc li{list-style:none;margin:2px 0}.toc li.l0{margin-top:8px;font-weight:600}
.toc li.l1{margin-left:22px;font-weight:400;font-size:9.5pt}.toc li.l2{margin-left:22px;font-weight:400;font-size:9.5pt}
a{color:#0b57d0;text-decoration:none}
@media screen{body{max-width:1100px;margin:0 auto;padding:0 16px}}
@page{size:A4;margin:16mm 14mm}
"""


def build(key):
    spec = DOCS[key]
    order, numbered, titles = spec["order"], spec.get("numbered", True), spec.get("titles", {})
    missing = [f for f, *_ in order if not os.path.exists(os.path.join(T, f))]
    if missing:
        sys.exit(f"{key}: MISSING " + ", ".join(missing))
    anchors, toc, parts, stats = {}, [], [], []
    num0 = num1 = 0
    for name, lvl, fid in order:
        base = name[:-5]
        chid = "ch-" + slug(base)
        h = open(os.path.join(T, name), encoding="utf-8").read()
        m = re.search(r'<h1 id="([^"]+)"[^>]*>(.*?)</h1>', h, re.S)
        if not m:
            sys.exit(f"no h1 in {name}")
        title = titles.get(name) or text(m.group(2))
        if title.startswith("Appendix") or not numbered:
            label = ""
        elif lvl == 0:
            num0, num1 = num0 + 1, 0
            label = f"{num0}"
        else:
            num1 += 1
            label = f"{num0}.{num1}"
        shown = f"{label} {title}".strip()
        h = h.replace(m.group(0), f'<h1 id="{chid}">{html.escape(shown)}</h1>', 1)
        if fid:
            anchors[fid] = chid
        # code: full configuration section -> links; other long blocks -> excerpts
        folder = CONFIG_DIR.get(base) or slug(base)
        before = sum(b.count("\n") for b in re.findall(r"<pre.*?</pre>", h, re.S))
        h, _ = strip_full_config(h, folder)
        if base[:2].isdigit():
            src_name = base + ".md"
        elif name in os.listdir(os.path.join(R, "src", "html-infra")):
            src_name = "html-infra/" + name
        else:
            src_name = base + ".md"
        h = shorten_pre(h, src_name)
        after = sum(b.count("\n") for b in re.findall(r"<pre.*?</pre>", h, re.S))
        stats.append((shown, before, after))
        ids = set(re.findall(r'<h[2-6] id="([^"]+)"', h))
        h = re.sub(r'<(h[2-6]) id="([^"]+)"', lambda x: f'<{x.group(1)} id="{chid}--{x.group(2)}"', h)
        h = re.sub(r'href="#([^"]+)"', lambda x: f'href="#{chid}--{x.group(1)}"' if x.group(1) in ids else x.group(0), h)
        secs = []
        if lvl == 0:
            def num_h2(x):
                n = len(secs) + 1
                secs.append((x.group(1), text(x.group(2)), n))
                prefix = f"{label}.{n} " if label else ""
                return f'<h2 id="{x.group(1)}">{html.escape(prefix + text(x.group(2)))}</h2>'
            h = re.sub(r'<h2 id="([^"]+)"[^>]*>(.*?)</h2>', num_h2, h, flags=re.S)
            num1 = len(secs)  # sub-chapters number after the parent's own sections
        toc.append((shown, lvl, chid, [(a, (f"{label}.{n} " if label else "") + t) for a, t, n in secs]))
        h = re.sub(r'<figure data-embed="node/7c981588-62e7">.*?</figure>', ROLLOUT, h, flags=re.S)
        h = h.replace("&#91;embedded content: rollout loop · 4 steps, repeated per release cycle]",
                      "Rollout loop: 1 Classify, 2 Change request, 3 Release, 4 Verify, repeated per release cycle.")
        parts.append(h)

    body = "\n".join(parts)
    # exported infrastructure HTML refers to other tabs by doc id
    all_fids = {fid: "ch-" + slug(f[:-5]) for d in DOCS.values() for f, _, fid in d["order"] if fid}
    body = re.sub(r'<a data-atom="ref" data-ref="file/([0-9a-f-]+)">',
                  lambda m: f'<a href="#{anchors.get(m.group(1)) or all_fids.get(m.group(1), "")}">', body)
    body = re.sub(r'href="REPO/([^"]*)"', lambda m: f'href="{repo_url(m.group(1))}"', body)
    idx = re.search(r'<h1 id="ch-22-config-index">.*?(?=<h1 |\Z)', body, re.S)
    if idx:
        linked = re.sub(r"<tr>.*?</tr>", link_index_row, idx.group(0), flags=re.S)
        body = body[:idx.start()] + linked + body[idx.end():]
    # "tab" was the word for a section in the old multi-tab document
    body = re.sub(r"(<pre.*?</pre>)|\b(tab|tabs|Tab|Tabs)\b(?![-_./=])",
                  lambda m: m.group(1) or {"tab": "chapter", "tabs": "chapters", "Tab": "Chapter",
                                           "Tabs": "Chapters"}[m.group(2)], body, flags=re.S)
    # short inline code (up to 9 characters) never breaks mid-word; longer code still wraps
    body = re.sub(r"(<pre.*?</pre>)|<code>([^<\s]{1,9})</code>",
                  lambda m: m.group(1) or f'<code class="nb">{m.group(2)}</code>', body, flags=re.S)
    # links to chapters this document does not contain go to the document that has them
    ids = set(re.findall(r'id="([^"]+)"', body))

    def outside(m):
        target = m.group(1)
        if target in ids:
            return m.group(0)
        home = HOME.get(target.split("--")[0])
        return f'href="{doc_url(home)}"' if home and home != key else m.group(0)
    body = re.sub(r'href="#([^"]+)"', outside, body)
    left = re.findall(r'data-(?:ref|embed)="[^"]*"', body)
    dead = sorted({h for h in re.findall(r'href="#([^"]+)"', body) if h not in ids})
    print(f"[{key}] chapters {len(parts)}; code lines {sum(b for _, b, _ in stats)} -> {sum(a for _, _, a in stats)}; "
          f"unresolved {left}; dead links {dead}")

    def toc_html():
        out = []
        for t, lvl, a, secs in toc:
            out.append(f'<li class="l{lvl}"><a href="#{a}">{html.escape(t)}</a>')
            if secs and spec["toc"] >= 2:
                out.append('<ul>' + "".join(f'<li class="l2"><a href="#{s}">{html.escape(st)}</a></li>'
                                            for s, st in secs) + "</ul>")
            out.append("</li>")
        return "".join(out)

    toc_block = (f'<div class="toc" style="page-break-before:always"><h2>Contents</h2><ul>{toc_html()}</ul></div>'
                 if spec["toc"] else "")
    blurb = f"<p>{spec['blurb']}</p>" if spec["blurb"] else ""
    cover = f"""<div class="cover"><h1 class="title">{html.escape(spec['title'])}</h1>
<p class="sub">{html.escape(spec['sub'])}</p>{blurb}
<p class="meta">Kishore Mooli<br>Edition of {DATE}<br>Code, configuration files and tests: <a href="{GH}">{GH}</a></p></div>
{toc_block}"""
    head = (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" '
            f'content="width=device-width,initial-scale=1"><title>{html.escape(spec["title"])}</title>'
            f'<style>{CSS}</style></head><body>')
    out = os.path.join(R, "build", "out")
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, key + ".html"), "w", encoding="utf-8").write(f"{head}\n{cover}\n{body}</body></html>")
    open(os.path.join(out, key + "-docx.html"), "w", encoding="utf-8").write(f"{head}\n{body}</body></html>")
    print(f"OUT {key} {spec['out']} {spec['title']}")


for k in (sys.argv[2:] or list(DOCS)):
    build(k)
