"""pqc-e2e runner: runs cases/*.json against the isolated LocalStack and grades them.

    python -m runner run [--lang python,node] [--compute lambda,ec2] [--id GLOB] [--jobs 6]
    python -m runner list [...same filters]
    python -m runner cleanup        # removes only resources this suite created (pqc-* names, project=pqc-e2e tag)

Runs inside the pqc-e2e/runner container on the pqc-e2e network (see run.sh).
"""
import argparse
import fnmatch
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from . import compute, report

E2E = os.environ.get("E2E_ROOT", "/e2e")


def load_cases(args):
    cases = []
    for fn in sorted(os.listdir(os.path.join(E2E, "cases"))):
        if not fn.endswith(".json"):
            continue
        doc = json.load(open(os.path.join(E2E, "cases", fn)))
        for c in doc.get("cases", []):
            c.setdefault("lang", doc.get("lang"))
            c.setdefault("targets", doc.get("default_targets", list(compute.TARGETS)))
            c["_file"] = fn
            cases.append(c)
    ids = [c["id"] for c in cases]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        sys.exit("duplicate case ids: %s" % sorted(dup))
    if args.lang:
        cases = [c for c in cases if c["lang"] in args.lang.split(",")]
    if args.compute:
        cases = [c for c in cases if c["compute"] in args.compute.split(",")]
    if args.id:
        cases = [c for c in cases if any(fnmatch.fnmatch(c["id"], g) for g in args.id.split(","))]
    return cases


def main():
    ap = argparse.ArgumentParser(prog="runner")
    ap.add_argument("cmd", choices=["run", "list", "cleanup"])
    ap.add_argument("--lang")
    ap.add_argument("--compute")
    ap.add_argument("--id")
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("PQC_JOBS", "6")))
    ap.add_argument("--out", default=os.path.join(E2E, "results", "runs"))
    args = ap.parse_args()

    if args.cmd == "cleanup":
        compute.cleanup()
        return
    cases = load_cases(args)
    if args.cmd == "list":
        for c in cases:
            print("%-48s %-12s %-10s %s" % (c["id"], c["compute"], c.get("mode", ""), c.get("title", "")))
        print("%d cases" % len(cases))
        return

    run_id = time.strftime("r%m%d%H%M%S")
    out_dir = os.path.join(args.out, run_id)
    os.makedirs(out_dir, exist_ok=True)
    print("run %s: %d cases, %d jobs -> %s" % (run_id, len(cases), args.jobs, out_dir), flush=True)
    env = compute.Env(E2E, run_id)
    env.prepare(cases)

    def one(c):
        r = compute.run_case(env, c)
        print("%-5s %-48s %s" % (r["verdict"], c["id"], r.get("summary", "")), flush=True)
        return r

    # EC2 instances are heavier: run them with fewer workers, after the container computes.
    light = [c for c in cases if c["compute"] != "ec2"]
    heavy = [c for c in cases if c["compute"] == "ec2"]
    results = []
    with ThreadPoolExecutor(args.jobs) as ex:
        results += list(ex.map(one, light))
    with ThreadPoolExecutor(max(1, min(args.jobs, 4))) as ex:
        results += list(ex.map(one, heavy))
    results += compute.run_detection(env, results)

    report.write(out_dir, run_id, results, env.meta)
    failed = [r for r in results if r["verdict"] != "PASS"]
    print("\n%d passed, %d failed/error of %d -> %s" % (len(results) - len(failed), len(failed), len(results), out_dir))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
