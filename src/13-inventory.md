# Inventory and dashboards

Detection produces signals; the inventory turns them into a list of everything we own that makes or ends a TLS connection, each with a status, an owner and a next action. Dashboards track that list to done. A component is **done** when its posture is PQ and the observed signals show no classical connections for seven days, or when it is a recorded exception.

## What the inventory holds

| Component | Source | What is read | How it is classified | In `pq_inventory.py` |
| --- | --- | --- | --- | --- |
| Lambda functions | `lambda:ListFunctions` | Runtime, package type, `OPENSSL_CONF`, `JAVA_TOOL_OPTIONS`, `GODEBUG`, `PYTHONPATH`, `AWS_LAMBDA_EXEC_WRAPPER`, layers, role | Language chapters, Lambda rows; AWS block-update date | Yes (Tested) |
| ECS task definitions (Fargate and EC2) | `ecs:ListTaskDefinitions`, `DescribeTaskDefinition` | Image, environment, task role | Base image (PQ by default or not), PQ variables | Yes (Tested; image classification is by tag, confirm with a scan) |
| Container images (ECS, EKS, Lambda images) | Amazon Inspector SBOM export or a scanner in CI | OS OpenSSL, JDK, Node, Python's linked OpenSSL, Go build info (`go version -m`) | Language chapters, container rows | No: status `scan` points here |
| EKS workloads | Kubernetes API (`Deployment`, `Pod` specs) | Image, environment | As for ECS | No (add: same rules as ECS) |
| EC2 hosts | SSM Inventory | OS, OpenSSL version, crypto policy (`update-crypto-policies --show`) | [Hosts and OS](#ch-hosts-and-os) | No (add) |
| ALB and NLB listeners | `elbv2:DescribeListeners` | `SslPolicy` | PQ policy names (`-PQ-`) | Yes (Tested) |
| Classic Load Balancers | `elb:DescribeLoadBalancers` | Existence | Always `blocked`: migrate | Yes (Tested) |
| API Gateway | `apigateway:GetDomainNames`, `apigatewayv2:GetApis` | REST domain security policy; HTTP and WebSocket APIs | REST: PQ policy or not; HTTP and WebSocket: `blocked` | Yes (Tested) |
| CloudFront distributions | `cloudfront:ListDistributions` | Origins | Viewer leg PQ; origin leg a recorded exception | No (add) |
| Databases and data services | `rds:DescribeDBInstances`, ElastiCache, MSK, OpenSearch | Engine and version | [Databases and data services](#ch-databases-and-data-services) | No (add) |
| Certificates | ACM, AWS Private CA, the CLM product | Key algorithm (RSA, ECDSA, ML-DSA), expiry, issuer | [Use cases](#ch-11-use-cases) | No (add) |
| IoT devices | IoT fleet indexing | TLS library and version as a thing attribute | [IoT](#ch-iot) | No (add) |
| External destinations | Zeek `ssl.log`, egress proxy logs | Server name, negotiated group | Classical destinations become third-party exceptions or upgrade requests | From observed signals |

The script ([pq_inventory.py](REPO/configs/inventory/pq_inventory.py)) is read-only. It writes one JSON line per component, for one account and Region. Run it per account from a scheduled job, with a read-only role assumed from the organisation's security account.

## Status values

| Status | Meaning | Next action |
| --- | --- | --- |
| `pq` | PQ today with no change (Java 25, a Debian 13 image, a PQ listener policy) | Confirm with observed signals |
| `pq-fixed` | Our fix is applied (config file, agent, layer, `GODEBUG`) | Confirm with observed signals; a `pq-fixed` component with classical traffic is a failed fix |
| `bridge` | A partial fix: Python 3.9 to 3.11 shim (requests and boto3 only) or the `pq-egress` extension | Plan the runtime upgrade |
| `fixable` | One change makes it PQ | Release the fix through the build template |
| `upgrade` | Only a runtime or version upgrade helps (Node 18 and 20, Python 3.9 to 3.11 without the shim) | Schedule before the block-update date |
| `blocked` | AWS offers no PQ option (Classic LB, API Gateway HTTP and WebSocket) | Migrate or front it, or record an exception |
| `scan` | Metadata is not enough (container images, custom runtimes) | Scan the image or binary |

The main classification rule, for Python on Lambda:

```
if rt.startswith("python3."):
    if minor >= 12:
        # fixed = OPENSSL_CONF points at openssl-pq.cnf, or the pq-tls layer wraps the runtime
        return "pq-fixed" if pq_conf or wrapped else "fixable"
    if wrapped or "pyshim" in env.get("PYTHONPATH", ""):
        return "bridge"          # the shim covers requests and boto3 only
    return "upgrade"
```

**Tested.** `e2e/inventory/test_inventory.py` creates 25 components in LocalStack Pro: 17 Lambda functions (every runtime family, with and without each fix), 3 ECS task definitions, an ALB with a PQ and a classical listener, a Classic LB, an API Gateway REST domain and an HTTP API. It runs the script and checks every status: 25 of 25 passed on 2026-11-16. Not run against a real AWS account.

## From signals to dashboards

```
 Posture                         Observed
 pq_inventory.py (daily)         CloudTrail       ALB / NLB logs     Zeek ssl.log      App tls_handshake logs
        |                             |                  |                 |                  |
        v                             v                  v                 v                  v
 s3://.../pq-inventory/          S3 (trail)       S3 (ELB logs)     S3 (Firehose)     CloudWatch -> S3 export
        \___________________________ Athena: pq_inventory, pq_observed, pq_workload ___________/
                                                    |
                         Dashboards (QuickSight or Managed Grafana) + CloudWatch alarms
```

The Athena views ([athena-views.sql](REPO/configs/inventory/athena-views.sql)) put every observed source into one shape (`source, ts, who, dest, tls_version, grp, pq`) and join it to the latest inventory by IAM role, which CloudTrail records for every call. The views follow AWS's and Zeek's documented formats; the Zeek table matches the JSON our Zeek check produced. They have not been run on Athena (Unverified).

## Dashboards

| Dashboard | Question it answers | Source | Done when |
| --- | --- | --- | --- |
| **Programme** | How many components are PQ, and is the classical share of handshakes falling? | `pq_inventory_latest` by status over time; `pq_observed` classical share per day and source | Every component `pq`, `pq-fixed` or an exception; classical share flat at the exception level |
| **By compute type** | Where is each Lambda, ECS, EKS and EC2 workload? | `pq_inventory_latest` by compute and status | No `fixable` or `upgrade` left |
| **By language and runtime** | Which runtimes need an upgrade, and before which date? | `pq_inventory_latest` by language, runtime and `block_update` | No component on a runtime past or near its block-update date |
| **Front doors and infrastructure** | Are all listeners and APIs on PQ policies? Which legs are blocked by AWS? | Inventory listener and API rows; ALB and NLB `tls_keyexchange` | Every listener PQ; blocked legs in the exception register |
| **Network (Zeek)** | Which hosts still make classical TLS connections, and to where? | `zeek_ssl` classical flows by client and server name; `notice.log` | Only exception destinations remain |
| **Fix verification** | Did each fix work? | `pq_workload`: posture `pq-fixed` against observed classical AWS calls | No `pq-fixed` workload with classical calls |
| **Certificates** | Which certificates are RSA, ECDSA or ML-DSA, and when do long-lived roots expire? | Certificate inventory | ML-DSA roots in place for the use cases that need them |
| **Exceptions** | What is classical on purpose, who owns it, and when is it reviewed? | Exception register | Every exception has an owner and a review date in the future |

Alarms come from the same data: a CloudTrail metric filter for classical AWS API calls, the hourly classical share from ELB logs, and Zeek notices for destinations on the PQ-required list ([Enforcement and guardrails](#ch-21-enforcement)).

## Rollout of the inventory

1. **Week 1:** run `pq_inventory.py` in every account and Region; load the output to S3; create the Athena tables.
2. **Week 2:** turn on ALB connection logs and NLB access logs; add `keyexchange` to the CloudTrail table; deploy the CloudTrail alarm.
3. **Weeks 2 to 4:** deploy Zeek sensors on the mirrored ENIs of NAT instances, egress proxies and the busiest EC2 hosts; ship JSON logs to S3.
4. **Week 4:** build the Programme, By compute type and Fix verification dashboards first; the rest follow.
5. **Then:** extend the script with the "No (add)" rows above, starting with container image scans (they replace the `scan` status).
