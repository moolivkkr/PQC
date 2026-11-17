# Inventory and dashboards

The inventory is one list of everything that makes or ends a TLS connection, each with a status, an owner and a next action. A component is **done** when its posture is PQ and observed signals show no classical connections for seven days, or when it is a recorded exception.

| Status | Meaning | Next action |
| --- | --- | --- |
| `pq` | PQ today with no change | Confirm with observed signals |
| `pq-fixed` | Our fix is applied | Confirm; classical traffic here means a failed fix |
| `bridge` | Partial fix (Python 3.9 to 3.11 shim, `pq-egress` extension) | Plan the runtime upgrade |
| `fixable` | One change makes it PQ | Release the fix |
| `upgrade` | Only a runtime upgrade helps | Schedule before the block-update date |
| `blocked` | AWS offers no PQ option | Migrate, front it, or record an exception |
| `scan` | Needs an image or binary scan | Scan |

**Sources.** Lambda functions, ECS task definitions, ELB listeners, Classic load balancers and API Gateway are read by `configs/inventory/pq_inventory.py` (read-only; Tested on LocalStack, 25 of 25 components classified correctly). Next to add: container image scans (Inspector SBOM), EC2 hosts (SSM Inventory), EKS workloads, RDS and data services, certificates (ACM, Private CA), CloudFront and IoT devices.

**Pipeline.** Inventory output, CloudTrail, ELB logs, Zeek `ssl.log` and application handshake logs land in S3; Athena views (`configs/inventory/athena-views.sql`) put them in one shape and join observed calls to workloads by IAM role; dashboards in QuickSight or Managed Grafana read the views. The views follow documented log formats but have not been run on Athena (Unverified).

| Dashboard | Question | Done when |
| --- | --- | --- |
| Programme | How many components are PQ; is the classical share falling? | All `pq`, `pq-fixed` or exceptions |
| By compute type, by language and runtime | Where is each workload; which runtimes hit a deadline? | No `fixable` or `upgrade` left |
| Front doors and infrastructure | Are all listeners and APIs on PQ policies? | All PQ or recorded |
| Network (Zeek) | Which hosts still make classical connections, to where? | Only exception destinations |
| Fix verification | Did each fix work? | No `pq-fixed` workload with classical calls |
| Certificates; Exceptions | Algorithms and expiry; owners and review dates | Plans in place; no overdue review |

**First four weeks:** run the inventory in every account; turn on ELB connection logs and the CloudTrail alarm; deploy Zeek on mirrored ENIs of NAT instances, proxies and the busiest hosts; build the Programme, By compute type and Fix verification dashboards.
