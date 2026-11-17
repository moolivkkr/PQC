# Context for application teams

## What "PQC-enabled" means

A **PQ connection** is a TLS 1.3 handshake that negotiated a hybrid ML-KEM key exchange group, X25519MLKEM768 (ML-KEM is FIPS 203). It protects traffic recorded today from being decrypted by a future quantum computer. Your service is **PQ-enabled** when it offers or accepts that group first **and** still connects to classical peers, so nothing breaks. It is **done** when the programme's dashboards show its connections as PQ, not when the change is deployed.

What does **not** change: your certificates, keystores, private CA trust and mutual TLS. ML-KEM works with today's RSA and ECDSA certificates. ML-DSA (PQ certificates, FIPS 204) is a separate, later track; your summary page says what your runtime can do with it.

## How the fix ships

Every fix is one of: a configuration file plus a variable, a Java agent, a base image or a version. The shared `pq-tls` kit versions these files once, and the shared build template adds them, so your service picks the fix up on its next release and rolls back by removing one setting. Guardrails in the pipeline warn first and fail later on settings that block PQ.

| Where a variable goes | How |
| --- | --- |
| Lambda (zip or image) | `Environment.Variables` (CloudFormation, SAM), `environment` (CDK, Terraform) |
| Container images | `ENV NAME=value` in the Dockerfile |
| ECS task, EKS pod (override) | `containerDefinitions[].environment`; `spec.containers[].env` |
| EC2 service | `Environment=NAME=value` in the systemd unit |

## Evidence labels

| Label | Meaning |
| --- | --- |
| Tested | Run between 2026-11-12 and 2026-11-16 in Lambda base images, official images or the LocalStack end-to-end suite. Not run on real AWS |
| Documented | Stated in vendor documentation, not tested here |
| Claimed | A vendor plan, not shipped |
| Unverified | Believed true; confirm before relying on it |

## Related documents

The programme's white paper (`docs/PQC-White-Paper.pdf`) explains detection, the inventory and the rollout. The complete guide (`PQC-Detection-and-Remediation.pdf`) holds the infrastructure detail (load balancers, databases, service mesh, hosts). Every configuration file named in this document is in the repository under `configs/`, and every test under `e2e/` and `tests/`.
