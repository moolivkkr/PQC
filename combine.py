import re, sys, os, html
D = sys.argv[1]
order = [("2b549c4f-a403","Tab 1.html",0),("5dd6e4e1-9c38","Runbook by language.html",0),
 ("f452a156-1a48","Go.html",1),("35b45b8c-c6f8","Python.html",1),("d69fae22-fa1f","Node.js.html",1),
 ("cd465386-557e","Java.html",1),("c09219a7-69d4",".NET.html",1),
 ("c0e73cdc-fca7","Infrastructure and services.html",0),("bb21387b-4f66","Load balancers.html",1),
 ("6d11c1c8-dcc8","Edge and API front doors.html",1),("5a29f676-6958","AWS service endpoints.html",1),
 ("c2c97bfd-040d","Network devices and egress.html",1),("27172d37-a5c2","IoT.html",1),
 ("569dd476-c063","Service mesh.html",1),("d9065243-9ab3","Databases and data services.html",1),
 ("99613846-4046","Hosts and OS.html",1),("38ead846-eb16","Certificates (ML-DSA).html",1)]
rollout = ('<p><em>Rollout loop (diagram in the online doc): 1 Classify, 2 Change request, '
           '3 Release, 4 Verify, repeated per release cycle.</em></p>')
anchors, parts = {}, []
for i,(fid,name,lvl) in enumerate(order):
    h = open(os.path.join(D,"tabs",name),encoding="utf-8").read()
    h1 = re.search(r'<h1 id="([^"]+)"', h).group(1)
    anchors[fid] = h1
    # unique ids: prefix every non-h1 id with tab index
    h = re.sub(r'<(h[2-6]) id="([^"]+)"', lambda m: f'<{m.group(1)} id="t{i}-{m.group(2)}"', h)
    h = re.sub(r'<figure data-embed="node/7c981588-62e7">.*?</figure>', rollout, h, flags=re.S)
    parts.append(h)
body = "\n".join(parts)
body = re.sub(r'<a data-atom="ref" data-ref="file/([0-9a-f-]+)">', lambda m: f'<a href="#{anchors.get(m.group(1),"")}">', body)
left = re.findall(r'data-(?:ref|embed)="[^"]*"', body)
print("unresolved refs/embeds:", left)
title = "PQC Detection and Remediation by Language and Compute"
# main tab h1 is the doc title; rename it to "Overview" so the title page carries the title
body = body.replace(f'<h1 id="pqc-detection-and-remediation-by-language-and-compute">{title}</h1>',
                    '<h1 id="pqc-detection-and-remediation-by-language-and-compute">Overview</h1>',1)
toc = "".join(f'<li class="l{lvl}"><a href="#{anchors[fid]}">{html.escape(re.search(r"<h1[^>]*>(.*?)</h1>", open(os.path.join(D,"tabs",n),encoding="utf-8").read()).group(1)) if fid!="2b549c4f-a403" else "Overview"}</a></li>' for fid,n,lvl in order)
css = """
body{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;font-size:10.5pt;line-height:1.45;color:#1a1a1a;max-width:none}
h1{font-size:20pt;border-bottom:2px solid #333;padding-bottom:4px;page-break-before:always;margin-top:0}
h2{font-size:14pt;margin-top:18px}h3{font-size:12pt}
table{border-collapse:collapse;width:100%;margin:8px 0;font-size:9pt;page-break-inside:auto}
th,td{border:1px solid #999;padding:4px 6px;vertical-align:top;text-align:left}
th{background:#e8e8e8} tr{page-break-inside:avoid}
code{font-family:Menlo,Consolas,monospace;font-size:8.5pt;background:#f2f2f2;padding:0 2px;word-break:break-word}
pre{background:#f2f2f2;padding:8px;font-size:8pt;white-space:pre-wrap;word-break:break-all;border:1px solid #ddd}
pre code{background:none;padding:0}
.cover{text-align:left;padding-top:180px}.cover h1{page-break-before:avoid;border:none;font-size:26pt}
.toc li.l1{margin-left:22px}.toc li{list-style:none;margin:3px 0}
a{color:#0b57d0;text-decoration:none}
@page{size:A4;margin:16mm 14mm}
"""
doc = f"""<!doctype html><html><head><meta charset="utf-8"><title>{title}</title><style>{css}</style></head><body>
<div class="cover"><h1 class="title">{title}</h1>
<p>Monitoring for non-PQ connections and the upgrades needed for PQ, by language, compute type and infrastructure component.</p>
<p>Exported 2026-11-13 from the Claude Docs document (all 17 tabs).<br>Source: https://claude.ai/artifact/9UmGyhf2tCn9V6s93RGx7S</p></div>
<div class="toc" style="page-break-before:always"><h2>Contents</h2><ul>{toc}</ul></div>
{body}</body></html>"""
open(os.path.join(D,"pqc-combined.html"),"w",encoding="utf-8").write(doc)
print("written", len(doc))
