# Appendix. Documents, code and tests

| Document | For |
| --- | --- |
| Executive summary (`docs/PQC-Executive-Summary.pdf`) | Leadership: the problem, the plan, the asks |
| This white paper (`docs/PQC-White-Paper.pdf`) | Architects, platform and security teams |
| Language documents (`docs/languages/PQC-Go.pdf`, `PQC-Python.pdf`, `PQC-Nodejs.pdf`, `PQC-Java.pdf`, `PQC-dotnet.pdf`) | Each language's application teams: every version, case, test and file |
| Complete guide (`PQC-Detection-and-Remediation.pdf`) | Everything in one reference, including the twelve infrastructure areas and enforcement in full |
| Rollout plan (`artifacts/PQC-TLS-rollout-plan.md`) | Programme management |

| Code | Path |
| --- | --- |
| Configuration files, by chapter | `configs/` (index: `configs/MANIFEST.md`) |
| Inventory script and Athena views | `configs/inventory/` |
| Java kit v2 (agent, layer wrapper, CI check) | `kit/java-v2/` |
| End-to-end suite (cases, probes, observer, results) | `e2e/` (results: `e2e/results/latest/summary.md`) |
| Zeek and inventory checks | `e2e/zeek/check.sh`, `e2e/inventory/test_inventory.py` |
| Earlier container and Lambda tests | `tests/deep/`, `tests/lambda/` |
