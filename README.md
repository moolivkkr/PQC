# PQC

Post-quantum cryptography (PQC) migration notes for AWS workloads: how to detect non-post-quantum TLS connections and how to fix them, organized by language and compute type.

| File | Contents |
|------|----------|
| [PQ.pdf](PQ.pdf) | *PQC Detection and Remediation by Language and Compute*: detection signals per compute type, a remediation matrix per language, front-door TLS policies, the rollout process, gaps, and sources |
| [PQ.docx](PQ.docx) | *Hosts and operating systems*: PQ status per OS (Amazon Linux, Debian, Alpine, Windows), how to fix it, how to detect it, and risks |

Each finding carries an evidence label: **Tested** (run on 2026-11-12 in AWS Lambda base images), **Documented** (stated in vendor docs), or **Unverified**.

## Combined document

| File | Contents |
|------|----------|
| [PQC-Detection-and-Remediation.pdf](PQC-Detection-and-Remediation.pdf) / [.docx](PQC-Detection-and-Remediation.docx) | The full document, all 17 tabs: overview, runbooks per language (Go, Python, Node.js, Java, .NET), and infrastructure and services (load balancers, edge, AWS endpoints, network devices, IoT, service mesh, databases, hosts, certificates) |
| [pqc-combined.html](pqc-combined.html) | The combined HTML the PDF is printed from; `pqc-for-docx.html` is the variant used for the Word export |
| `extract.py`, `combine.py` | Helper scripts that pulled the tab exports out and merged them into one HTML file |
