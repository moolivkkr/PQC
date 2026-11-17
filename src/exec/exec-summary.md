# Executive summary

## The problem

Our TLS connections agree their session keys with classical cryptography. Traffic recorded today can be decrypted once a large quantum computer exists ("harvest now, decrypt later"), so anything that must stay confidential for years is exposed now. The fix, hybrid ML-KEM key exchange (X25519MLKEM768), is standardised (FIPS 203) and supported by AWS, browsers and current language runtimes, but it is **off by default on most of what we run**: Lambda and Amazon Linux 2023 negotiate classical keys for Python, Node.js and .NET, and Java before 25 and Node.js 18 and 20 cannot negotiate PQ at all. Nothing fails when a connection is classical, so only measurement shows where we stand.

**"PQC-enabled" in this programme** means every connection we own negotiates hybrid ML-KEM where both ends can, keeps classical fallback so nothing breaks, and is **proven** by logs or sensors, not assumed from a deployment. It does not mean new certificates: ML-KEM works with today's certificates. PQ certificates (ML-DSA) are a separate, slower track for long-lived trust such as device firmware roots and code signing.

## What we found

| Finding | Evidence |
| --- | --- |
| Every language (Go, Python, Node.js, Java, .NET) can be made PQ on every compute type we use (Lambda, ECS on Fargate and EC2, EKS, EC2) with **one change per workload**: a config file, an agent, a base image or a version | 471 of 471 end-to-end cases passed on real Lambda, ECS and EC2 deployments in LocalStack Pro (2026-11-16) |
| Existing certificates, keystores, private CAs and mutual TLS **keep working** with the fix in all five languages | Tested per language |
| Classical connections **can be detected**: CloudTrail and load balancer logs for AWS-facing traffic, Zeek network sensors for internal and egress traffic, application logs for Lambda and Fargate | Zeek and log checks Tested; AWS-side logs Documented |
| A posture **inventory** classifies every Lambda function, ECS task, load balancer and API by what it needs | Script Tested on LocalStack (25 of 25) |
| **AWS blocks some legs today**: CloudFront to origin, API Gateway egress and HTTP APIs, IoT Core, RDS Proxy, ElastiCache, MSK, OpenSearch, AWS VPN | Documented; recorded as exceptions |
| **Fixed deadline**: AWS blocks updates to deprecated Lambda runtimes from **2027-08-31**; after that they cannot be fixed | AWS runtime page (forecast) |

## The plan

| Step | What | When (proposed) |
| --- | --- | --- |
| Prove | Confirm the lab results on real AWS (one workload per language and compute; logs) | 2026-11-23 to 2026-12-18 |
| See | Inventory every account; dashboards for the classical share; Zeek on internal traffic | to 2027-01-15 |
| Fix | Runtime upgrades for runtimes AWS will block (first); the shared fix through the build template for everything else; front doors to PQ policies | 2026-12 to 2027-06-30 |
| Hold | Guardrails warn, then fail, so new work stays PQ | 2027-01 to 2027-09-30 |
| Certificates | ML-DSA roots for long-lived devices and signing; internal dual-certificate pilots | to 2027-12-17 |

Each change rides the normal release pipeline and is rolled back by removing one setting. A workload is done only when the dashboards show its traffic as PQ; anything AWS or a third party blocks is a recorded exception with an owner and a review date.

## Risks

- **Lab, not production:** nothing has run on real AWS yet; Phase 0 closes this.
- **Runtime upgrades** for Node.js 18 and 20, Python 3.9 to 3.11 and Java on Amazon Linux 2 must finish before AWS's 2027-08-31 block.
- **Blind spots:** Lambda and Fargate calls to non-AWS services are visible only through posture and application logs.
- **Java 8 to 21** relies on Bouncy Castle as the TLS provider until teams move to JDK 25.

## Decisions and asks

1. An AWS sandbox account for Phase 0 (four weeks).
2. A named owner per language and per infrastructure area.
3. Agreement to the warn-then-fail guardrail schedule and the exception process.
4. Prioritise the runtime upgrades AWS will block.

The white paper has the approach; each language team has its own document; every configuration file and test is in the repository.
