"""Writes results.json, junit.xml and summary.md for a run, and refreshes results/latest/."""
import json
import os
import shutil
from xml.sax.saxutils import escape


def _cell(r, t):
    v = (r.get("targets") or {}).get(t) or {}
    c = v.get("client") or {}
    if not c:
        return "-"
    if not c.get("ok"):
        return "fail"
    return ("**PQ**" if c.get("pq") else "classical") + (" 1.2" if c.get("tls_version") == "TLSv1.2" else "")


def write(out_dir, run_id, results, meta):
    json.dump({"run_id": run_id, "meta": meta, "results": results}, open(os.path.join(out_dir, "results.json"), "w"),
              indent=1, default=str)

    # JUnit: one testsuite per lang/compute
    suites = {}
    for r in results:
        suites.setdefault("%s.%s" % (r["lang"], r["compute"]), []).append(r)
    x = ['<?xml version="1.0" encoding="UTF-8"?>', '<testsuites name="pqc-e2e" id="%s">' % run_id]
    for name, rs in sorted(suites.items()):
        f = sum(r["verdict"] == "FAIL" for r in rs)
        e = sum(r["verdict"] == "ERROR" for r in rs)
        x.append('<testsuite name="%s" tests="%d" failures="%d" errors="%d">' % (escape(name), len(rs), f, e))
        for r in rs:
            x.append('<testcase classname="%s" name="%s" time="%s">' % (escape(name), escape(r["id"]), r.get("seconds", 0)))
            if r["verdict"] == "FAIL":
                x.append('<failure message="%s"/>' % escape(r.get("summary", ""), {'"': "&quot;"}))
            elif r["verdict"] == "ERROR":
                x.append('<error message="%s"/>' % escape(r.get("summary", ""), {'"': "&quot;"}))
            x.append("<system-out>%s</system-out></testcase>" % escape(r.get("summary", "")))
        x.append("</testsuite>")
    x.append("</testsuites>")
    open(os.path.join(out_dir, "junit.xml"), "w").write("\n".join(x))

    # Markdown summary
    p = sum(r["verdict"] == "PASS" for r in results)
    md = ["# PQC end-to-end results - run %s" % run_id, "",
          "LocalStack: %s. %d of %d cases passed." % (meta.get("localstack"), p, len(results)), "",
          "PASS = the observed behaviour matched the expectation in the case file (which is the documented behaviour); "
          "it does not mean PQ was negotiated. Cells: what the client negotiated against each observer listener "
          "(hybrid :8443, pqonly :8444, mtls :8445, eccert :8446, tls12 :8447).", ""]
    for lang in sorted({r["lang"] for r in results}):
        rs = [r for r in results if r["lang"] == lang]
        md += ["## %s" % lang, "",
               "| Case | Compute | Runtime | Mode | hybrid | pqonly | mtls | eccert | tls12 | Verdict |",
               "|---|---|---|---|---|---|---|---|---|---|"]
        for r in sorted(rs, key=lambda r: (r["compute"], r["id"])):
            if r["mode"] == "detection":
                md.append("| %s | %s | | detection | %s | | | | | %s |" % (r["id"], r["compute"], r.get("summary", ""), r["verdict"]))
                continue
            md.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                r["id"], r["compute"], r.get("runtime") or r.get("runtime_label") or "", r["mode"],
                *(_cell(r, t) for t in ("hybrid", "pqonly", "mtls", "eccert", "tls12")),
                r["verdict"] if r["verdict"] == "PASS" else "**%s**" % r["verdict"]))
        md.append("")
    bad = [r for r in results if r["verdict"] != "PASS"]
    if bad:
        md += ["## Failures and errors", ""]
        for r in bad:
            md.append("- `%s` (%s): %s" % (r["id"], r["verdict"], r.get("summary", "")))
        md.append("")
    open(os.path.join(out_dir, "summary.md"), "w").write("\n".join(md))

    latest = os.path.join(os.path.dirname(os.path.dirname(out_dir)), "latest")
    os.makedirs(latest, exist_ok=True)
    for f in ("summary.md", "junit.xml", "results.json"):
        shutil.copy(os.path.join(out_dir, f), os.path.join(latest, f))
