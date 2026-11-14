"""Combine the per-tab HTML fragments in build/tabs/ into one document.

Usage: python3 -I build/combine.py <pqc repo dir>
Writes build/pqc-combined.html (with cover and contents) and build/pqc-for-docx.html (body only).
"""
import html, os, re, sys

R = sys.argv[1]
T = os.path.join(R, "build", "tabs")
TITLE = "PQC Detection and Remediation by Language and Compute"
# (file in build/tabs, contents level, doc tab id used by cross-tab refs in exported HTML)
ORDER = [
    ("01-overview.html", 0, "2b549c4f-a403"), ("02-runbook.html", 0, "5dd6e4e1-9c38"),
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
    ("21-enforcement.html", 0, "0803191b-9855"), ("22-config-index.html", 0, "f5950343-31dd"),
]
ROLLOUT = ("<p><em>Rollout loop: 1 Classify, 2 Change request, 3 Release, 4 Verify, "
           "repeated per release cycle.</em></p>")

missing = [f for f, _, _ in ORDER if not os.path.exists(os.path.join(T, f))]
if missing:
    sys.exit("MISSING " + ", ".join(missing))

anchors, titles, parts = {}, [], []
for i, (name, lvl, fid) in enumerate(ORDER):
    h = open(os.path.join(T, name), encoding="utf-8").read()
    m = re.search(r'<h1 id="([^"]+)"[^>]*>(.*?)</h1>', h, re.S)
    if not m:
        sys.exit(f"no h1 in {name}")
    h1id = f"tab{i}-{m.group(1)}"
    h = h.replace(m.group(0), f'<h1 id="{h1id}">{"Overview" if i == 0 else m.group(2)}</h1>', 1)
    anchors[fid] = h1id
    titles.append(("Overview" if i == 0 else re.sub("<[^>]+>", "", m.group(2)), lvl, h1id))
    # unique ids per tab: prefix every other heading id and same-tab #links
    ids = set(re.findall(r'<h[2-6] id="([^"]+)"', h))
    h = re.sub(r'<(h[2-6]) id="([^"]+)"', lambda x: f'<{x.group(1)} id="t{i}-{x.group(2)}"', h)
    h = re.sub(r'href="#([^"]+)"', lambda x: f'href="#t{i}-{x.group(1)}"' if x.group(1) in ids else x.group(0), h)
    h = re.sub(r'<figure data-embed="node/7c981588-62e7">.*?</figure>', ROLLOUT, h, flags=re.S)
    h = h.replace("&#91;embedded content: rollout loop · 4 steps, repeated per release cycle]", "Rollout loop: 1 Classify, 2 Change request, 3 Release, 4 Verify, repeated per release cycle.")
    parts.append(h)

body = "\n".join(parts)
body = re.sub(r'<a data-atom="ref" data-ref="file/([0-9a-f-]+)">',
              lambda m: f'<a href="#{anchors.get(m.group(1), "")}">', body)
left = re.findall(r'data-(?:ref|embed)="[^"]*"', body)
print("unresolved refs/embeds:", left)

toc = "".join(f'<li class="l{l}"><a href="#{a}">{html.escape(t)}</a></li>' for t, l, a in titles)
css = """
body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;font-size:10.5pt;line-height:1.45;color:#1a1a1a;background:#fff;max-width:none}
h1{font-size:20pt;border-bottom:2px solid #333;padding-bottom:4px;page-break-before:always;margin-top:0}
h2{font-size:14pt;margin-top:18px}h3{font-size:12pt}h4{font-size:11pt}
table{border-collapse:collapse;width:100%;margin:8px 0;font-size:9pt;page-break-inside:auto}
th,td{border:1px solid #999;padding:4px 6px;vertical-align:top;text-align:left}
th{background:#e8e8e8} tr{page-break-inside:avoid}
code{font-family:Menlo,Consolas,monospace;font-size:8.5pt;background:#f2f2f2;padding:0 2px;word-break:break-word}
pre{background:#f2f2f2;padding:8px;font-size:8pt;white-space:pre-wrap;word-break:break-all;border:1px solid #ddd}
pre code{background:none;padding:0}
.cover{text-align:left;padding-top:180px}.cover h1{page-break-before:avoid;border:none;font-size:26pt}
.toc li.l1{margin-left:22px}.toc li{list-style:none;margin:3px 0}
a{color:#0b57d0;text-decoration:none}
@media screen{body{max-width:1100px;margin:0 auto;padding:0 16px}}
@page{size:A4;margin:16mm 14mm}
"""
cover = f"""<div class="cover"><h1 class="title">{TITLE}</h1>
<p>Monitoring for non-PQ connections and the changes needed for post-quantum TLS, by language, compute type and infrastructure component. Covers simple cases, existing certificates in custom keystores, custom CA trust, mutual TLS and the other cases application teams meet.</p>
<p>Final edition, 2026-11-14. 22 sections: Overview, Runbook, five language tabs, twelve infrastructure tabs, Enforcement and guardrails, and the Configuration file index.</p></div>
<div class="toc" style="page-break-before:always"><h2>Contents</h2><ul>{toc}</ul></div>"""
head = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{TITLE}</title><style>{css}</style></head><body>'
out = os.path.join(R, "build")
open(os.path.join(out, "pqc-combined.html"), "w", encoding="utf-8").write(f"{head}\n{cover}\n{body}</body></html>")
open(os.path.join(out, "pqc-for-docx.html"), "w", encoding="utf-8").write(f"{head}\n{body}</body></html>")
print("tabs", len(parts), "bytes", len(body))
