# PQC

Post-quantum cryptography (PQC) migration notes for AWS workloads: how to detect non-post-quantum TLS connections and how to fix them, by language, compute type and infrastructure component.

Each finding carries an evidence label: **Tested** (run between 2026-11-12 and 2026-11-16 in AWS Lambda base images or official container images, and in the end-to-end suite below), **Documented** (stated in vendor docs), **Claimed** (vendor plan, not shipped), or **Unverified**.

## White paper (2026-11-16)

*Post-Quantum TLS on AWS: Detection, Inventory and Remediation*, by Kishore Mooli.

| File | Contents |
|------|----------|
| [PQC-Detection-and-Remediation.pdf](PQC-Detection-and-Remediation.pdf) | 1 Introduction (what we solve, what "PQC-enabled" means, scope, approach, results); 2 Use cases (ML-KEM vs ML-DSA); 3 Detection (CloudTrail, ELB logs, Zeek, application logs); 4 Inventory and dashboards; 5 Solutions by compute type (Lambda, ECS Fargate, ECS on EC2 and EKS, EC2); 6 Solutions by language (Go, Python, Node.js, Java, .NET); 7 Infrastructure and services (twelve areas); 8 Enforcement and guardrails; 9 Rollout, gaps and open items; Appendix A tests per language with paths to the test code; Appendix B configuration file index; Appendix C sources. Numbered, linked contents. Code is limited to the main change; complete files are linked to `configs/` |
| [PQC-Detection-and-Remediation.docx](PQC-Detection-and-Remediation.docx) | Same content in Word; import into Google Docs with Drive > Upload, then Open with Google Docs |
| [PQC-Detection-and-Remediation.html](PQC-Detection-and-Remediation.html) | Same content as one HTML page |
| [PQC-Summary.pptx](PQC-Summary.pptx), [PQC-Summary.pdf](PQC-Summary.pdf) | 39-slide deck (PowerPoint and PDF) in the Secure Telemetry Tokenization format: why now, baseline and target, tested outcome, ML-KEM vs ML-DSA by use case (public HTTPS, internal HTTPS, workload identity and mTLS, user, device and IoT, code signing, SSH); test rounds and corrections; the solution per language (Go, Python, Node.js, Java, .NET) by compute type (Lambda, ECS Fargate, ECS on EC2 and EKS, EC2), ML-DSA by client stack, the AWS runtime deadline, design choices; infrastructure services in three slides with a risk column, the ML-DSA certificate track, what AWS blocks, guardrails, detection and traps; scorecard, rollout, the ask; appendix of test cases per language and for infrastructure, with links to the test code (private repo). Speaker notes on every slide |

## End-to-end verification (2026-11-15)

`e2e/` deploys real workloads into an isolated LocalStack Pro (Lambda zip, layer, extension and container image; ECS Fargate; ECS on EC2; EC2 from AMIs built on AL2023 `2023.12.20261109` and Amazon Linux 2) for Python, Node.js, Java, .NET and Go. Each one connects to a TLS observer that records what was offered and negotiated, and the run is graded against the document's claims.

- **Result:** run r1117041043 (2026-11-16): 471 of 471 cases pass: 437 client cases, 32 load balancer target-leg cases and the CloudWatch and server-side detection checks ([results](e2e/results/latest/summary.md)). Every client case also has three ML-DSA certificate targets.
- **Detection and inventory checks** (2026-11-16): Zeek 7.2.2 with `pq-tls.zeek` classifies every handshake (`e2e/zeek/check.sh`); the posture inventory script classifies 25 of 25 LocalStack components (`e2e/inventory/test_inventory.py`).
- **Document errors found and fixed** (each kept as a regression case): Python legacy bridge missing `idna`; Node 20 on AL2023 is fixable; JDK 8 needs `-Dorg.bouncycastle.jsse.client.assumeOriginalHostName=true`; the layer wrapper had no .NET branch, so the enforcement guard accepted classical .NET functions; .NET `X509Store` on Lambda needs `HOME=/tmp`; Go FIPS group lists. Details: [e2e/README.md](e2e/README.md).
- **Run it:** [e2e/RUNNING.md](e2e/RUNNING.md). **Not covered:** real AWS, x86_64, and the ALB/NLB listener leg (LocalStack's ALB ignores security policies; the load balancer to container leg is modelled and tested).

## Layout

| Path | What it is |
|------|------------|
| `src/*.md` | **Source of truth.** One markdown file per chapter (10 introduction, 11 use cases, 12 detection, 13 inventory, 14 compute, 15 languages, 03-07 language chapters, 08 infrastructure, 21 enforcement, 23 rollout, 24 test appendix, 22 config index, 25 sources); edit these, then rebuild |
| `configs/inventory/` | `pq_inventory.py` (read-only posture inventory: Lambda, ECS, ELB, API Gateway, classified) and `athena-views.sql` (posture and observed signals in one place, for the dashboards) |
| `build/gen-appendix-tests.py` | Regenerates `src/24-appendix-tests.md` from the latest e2e results |
| `src/html-infra/` | The twelve infrastructure child sections, as exported HTML (2026-11-14) |
| `src/deck/` | Source of the slide deck: `deck.json`, `deck.css` and one HTML file per slide (claude.ai Slides format) |
| `configs/<section>/` | Every file listed in the Configuration file index, extracted from the sections' "Full configuration files". `configs/MANIFEST.md` lists them |
| `kit/java-v2/` | Java pq-tls kit v2 sources: agent (`src/`), `pq-tls/pq-tls.security`, Lambda layer wrapper (covers Python, Node.js, Java and .NET runtimes), `ci/java-pq-check.sh`. Build the jar from source; Bouncy Castle 1.87 jars are not committed |
| `tests/deep/<topic>/` | Test scripts, harnesses and outputs behind the Tested labels, per language and component |
| `tests/lambda/` | The 2026-11-12 Lambda runtime matrix (Runtime Interface Emulator) |
| `e2e/` | End-to-end suite on LocalStack: probes per language, observer, runner, cases, `pq-egress` extension, results ([README](e2e/README.md), [RUNNING](e2e/RUNNING.md), [CONTRACT](e2e/CONTRACT.md)) |
| `build/build.sh` | Rebuilds HTML, PDF and DOCX from `src/` (Docker pandoc pinned by digest, Chrome headless). `build/combine.py` numbers chapters, builds the contents, replaces each "Full configuration files" section with links to `configs/` and shortens any other code block over 20 lines |
| `build/deck-renumber.py` | Renumbers slide footers and scorecard cross-references in `deck.json` order |
| `build/deck.sh` | Rebuilds the deck from `src/deck/`: checks every slide for overflow, prints the PDF with headless Chrome, and builds the PPTX (one image per slide plus speaker notes). Fonts are vendored in `build/fonts/` (OFL) |
| `build/extract-configs.py` | Regenerates `configs/` from `src/` |
| `artifacts/` | Review artifacts kept with the project, each as HTML and DOCX: the rollout plan (`PQC-TLS-rollout-plan.*`, source `.md` exported from the [Claude Doc](https://claude.ai/artifact/7uLzuHcyCSJ4WN13MkxBt8)) and the end-to-end findings page (`PQC-e2e-findings.*`). Rebuild with `bash artifacts/build.sh` |

Test certificates, keys, jars, Go module caches and Python packages are not committed; the scripts regenerate or download them.

Rebuild everything:

```bash
python3 -I build/extract-configs.py .      # configs/ from the chapters' full configuration sections
python3 -I build/gen-appendix-tests.py .   # after an e2e run
bash build/build.sh
```

Deck (PPTX and PDF): `bash build/deck.sh`

## Earlier files

`PQ.pdf`, `PQ.docx` (2026-11-12 drafts), and `pqc-combined.html`, `pqc-for-docx.html`, `extract.py`, `combine.py` (the 2026-11-13 export from the online doc) are kept for reference only. They predate the end-to-end fixes and contain the errors listed above; use the final document.
