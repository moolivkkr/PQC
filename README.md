# PQC

Post-quantum cryptography (PQC) migration notes for AWS workloads: how to detect non-post-quantum TLS connections and how to fix them, by language, compute type and infrastructure component.

Each finding carries an evidence label: **Tested** (run between 2026-11-12 and 2026-11-14 in AWS Lambda base images or official container images), **Documented** (stated in vendor docs), **Claimed** (vendor plan, not shipped), or **Unverified**.

## Final document (2026-11-14)

| File | Contents |
|------|----------|
| [PQC-Detection-and-Remediation.pdf](PQC-Detection-and-Remediation.pdf) | All 22 sections: Overview, Runbook, Go, Python, Node.js, Java, .NET, twelve infrastructure sections, Enforcement and guardrails, Configuration file index |
| [PQC-Detection-and-Remediation.docx](PQC-Detection-and-Remediation.docx) | Same content in Word; import into Google Docs with Drive > Upload, then Open with Google Docs |
| [PQC-Detection-and-Remediation.html](PQC-Detection-and-Remediation.html) | Same content as one HTML page |
| [PQC-Summary.pptx](PQC-Summary.pptx) | 16-slide summary: problem, status by language, existing keystores, infrastructure, resolved risks, rollout, open items |

## Layout

| Path | What it is |
|------|------------|
| `src/*.md` | **Source of truth.** One markdown file per section; edit these, then rebuild |
| `src/html-infra/` | The twelve infrastructure child sections, as exported HTML (2026-11-14) |
| `src/deck/summary-deck.md` | Source of the slide deck |
| `configs/<section>/` | Every file listed in the Configuration file index, extracted from the sections' "Full configuration files". `configs/MANIFEST.md` lists them |
| `kit/java-v2/` | Java pq-tls kit v2 sources: agent (`src/`), `pq-tls/pq-tls.security`, Lambda layer wrapper, `ci/java-pq-check.sh`. Build the jar from source; Bouncy Castle 1.87 jars are not committed |
| `tests/deep/<topic>/` | Test scripts, harnesses and outputs behind the Tested labels, per language and component |
| `tests/lambda/` | The 2026-11-12 Lambda runtime matrix (Runtime Interface Emulator) |
| `build/build.sh` | Rebuilds HTML, PDF and DOCX from `src/` (Docker pandoc pinned by digest, Chrome headless) |
| `build/extract-configs.py` | Regenerates `configs/` from `src/` |

Test certificates, keys, jars, Go module caches and Python packages are not committed; the scripts regenerate or download them.

Rebuild everything:

```bash
bash build/build.sh
python3 -I build/extract-configs.py .
```

PPTX: `docker run --rm -v "$PWD":/d -w /d pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e src/deck/summary-deck.md -t pptx --slide-level=2 -o PQC-Summary.pptx`

## Earlier files

`PQ.pdf`, `PQ.docx` (2026-11-12 drafts), and `pqc-combined.html`, `pqc-for-docx.html`, `extract.py`, `combine.py` (the 2026-11-13 export from the online doc) are kept for reference; the final document above supersedes them.
