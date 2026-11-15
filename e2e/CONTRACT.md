# Probe contract and layout (for adding a language)

Every language follows the same layout as Python, so one runner grades every language the same way.

## Files a language owns

| Path | What |
|---|---|
| `clients/<lang>/` | Probe source: Lambda handler + CLI entry point, no PQ-specific settings in code |
| `build/<lang>.sh` | Builds Lambda zips into `.work/artifacts/lambda/<lang>/`, pushes ECS / Lambda images to LocalStack ECR with `ecr_build`, writes EC2 files to `.work/artifacts/ec2/<lang>/` (lands at `/opt/pqc/<lang>/` in the AMI), adds layer parts under `.work/artifacts/layer-src/<layer>/` |
| `cases/<lang>.py` → `cases/<lang>.json` | The case matrix; expectations = the language tab's documented claims |
| `ec2/al2023/packages.d/<lang>.txt`, `ec2/al2023/setup.d/<lang>.sh` (and `ec2/al2/…`) | dnf/yum packages and setup steps for the golden AMIs |

Shared (do not change per language): `runner/`, `observer/`, `compose.yaml`, `env.sh`, `build/{lib,common,layers,ami}.sh`, `cases/lib.py`, `certs/`.

## What a probe does

Input (environment; the Lambda event may also carry `case_id` and `targets`):

| Var | Meaning |
|---|---|
| `PQC_CASE_ID` | Case id; send as `?id=` on every request |
| `PQC_TARGETS` | Comma list from `hybrid,pqonly,mtls,eccert,tls12`, visited **in that order** (the runner brackets failed handshakes between successful ones) |
| `PQC_OBSERVER` | Host, `pq-observer` |
| `PQC_COMPUTE`, `PQC_MODE` | Echo into output |
| `PQC_CERTS` | Optional cert dir; else `<probe dir>/certs`, `/opt/pqc-certs`, `/etc/pqc/certs` |
| `PQC_EGRESS_PORT` | If set: extension mode. `GET http://127.0.0.1:$PQC_EGRESS_PORT/<target>/probe?id=<case>` (plain HTTP); the pq-egress extension makes the TLS connection |

Ports: hybrid 8443, pqonly 8444, mtls 8445 (send client cert), eccert 8446, tls12 8447.
`GET https://pq-observer:<port>/probe?id=<case>` returns the observer's JSON view: `tls_version`, `group`, `pq`, `offered_pq`.

Trust only the test CA (`ca.crt`, or `truststore.p12` for Java, password `changeit`). Client certificate for mtls:
`client.crt` + `client.key`, or `client.p12` (password `changeit`). Use the language's standard HTTPS client (the
path most applications use). Don't set TLS groups or versions in the probe; whatever the runtime, platform and fix
produce is what gets measured.

Output:

- One line per target: `{"event":"tls_handshake","case_id":..,"lang":..,"runtime":..,"compute":..,"mode":..,"target":..,"ok":bool,"tls_version":..,"group":..,"pq":bool,"offered_pq":bool,"pq_status":"pq|classical|failed","error":..}`
- Lambda: the handler **returns** `{"case_id","lang","runtime","tls_lib","compute","mode","results":{target:{ok,tls_version,group,pq,offered_pq,error,stack}}}`
- CLI (ECS, EC2): the same object printed as one line: `PQC_RESULT <json>`

## Case JSON (see cases/python.py)

`compute` is one of `lambda`, `ecs-fargate`, `ecs-ec2`, `ec2`, with a matching key:

- `lambda`: `{runtime, handler, zip: "<lang>/<file>.zip", layers: ["pq-tls"|"pq-egress"|"pq-tls-combined"], env}` or `{image: "<repo>:<tag>"}` for PackageType Image
- `ecs`: `{image: "<repo>:<tag>", command: [...], entrypoint: [...], env}`
- `ec2`: `{ami: "pqc-al2023"|"pqc-al2", setup: [shell...], run: "<command>", env}`

`finding` (optional string): set it when the observed behaviour differs from the language tab, the enforcement tab
or a kit file. The expectation then records what actually happens (so the suite stays green and catches regressions),
and the finding explains the gap and names the doc line. The summary lists every finding. Never "fix" an expectation
silently.

`expect` per target: any of `ok`, `pq`, `group`, `tls_version`, `offered_pq`, `error_match` (regex). Presets in
`cases/lib.py`: `CLASSICAL`, `PQ`, `TLS12_ONLY`, plus `override(...)`.

## Run

```bash
source e2e/env.sh
bash e2e/build/<lang>.sh && bash e2e/build/layers.sh && bash e2e/build/ami.sh
(cd e2e/cases && python3 <lang>.py)
PQC_JOBS=3 e2e/run.sh --skip-build --lang <lang>          # or --id 'node-lambda-*'
```

Results: `e2e/results/runs/<run>/{summary.md,results.json,junit.xml}` (also copied to `results/latest/`).
