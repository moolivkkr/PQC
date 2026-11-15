## What decides PQ here
Each managed front door terminates TLS with its own stack and policy, so the service and the policy you pick decide the client-facing leg. CloudFront and Cognito custom domains offer PQ on TLS 1.3 by default; API Gateway REST needs an opt-in `SecurityPolicy_*_PQ_*` policy plus an endpoint access mode; HTTP and WebSocket APIs and edge-optimized APIs have no PQ policy. The upstream legs are classical today: CloudFront to origin, and API Gateway to its integrations. Global Accelerator does not terminate TLS, so the client and your endpoint decide.

## Status matrix
| Front door | Device type | Client-facing leg | Upstream leg | Default | Evidence |
|---|---|---|---|---|---|
| CloudFront | Managed CDN | PQ on every viewer policy: X25519MLKEM768, SecP256r1MLKEM768, TLS 1.3 only | Classical: curves prime256v1, secp384r1, X25519; `OriginSSLProtocols` max `TLSv1.2` | PQ, nothing to do | Documented |
| API Gateway REST, Regional and private APIs and custom domains | Managed | Opt-in: `SecurityPolicy_TLS13_1_2_PQ_2025_09`, `..._PFS_PQ_2025_09`, `..._FIPS_PFS_PQ_2025_09` (TLS 1.2+1.3) | Integration egress TLS 1.2, never PQ | `TLS_1_0` on APIs, `TLS_1_2` on domains: not PQ | Documented |
| API Gateway REST, edge-optimized | Managed (CloudFront-fronted) | No PQ policy: `SecurityPolicy_TLS13_2025_EDGE`, `_TLS12_PFS_2025_EDGE`, `_TLS12_2018_EDGE`, `TLS_1_2` | TLS 1.2 | Not PQ | Documented (policy list) |
| API Gateway HTTP and WebSocket APIs | Managed | Only `TLS_1_2`; no PQ policy | TLS 1.2 | Not PQ | Documented |
| AppSync custom domains | Managed | TLS 1.2 and 1.3; PQ not stated | n/a | Not confirmed | Documented (TLS versions), PQ Unverified |
| Cognito user pool custom domain | Managed (CloudFront distribution owned by AWS) | `TLS_V1_2_2021` and `TLS_V1_3_2025` are "post-quantum-ready"; `TLS_V1` discouraged | n/a | Set by `CustomDomainConfig.SecurityPolicy` | Documented |
| Transfer Family SFTP | Managed | SSH KEX `mlkem768x25519-sha256`, `mlkem768nistp256-sha256`, `mlkem1024nistp384-sha384` in `TransferSecurityPolicy-2025-03`, `-FIPS-2025-03`, `-AS2Restricted-2025-07` | n/a | Older policies: not PQ | Documented |
| Transfer Family FTPS | Managed | TLS cipher list is ECDHE TLS 1.2 suites; no PQ | n/a | Not PQ | Documented (absence) |
| Transfer Family AS2 | Managed | No PQ statement found | n/a | Not confirmed | Unverified |
| Global Accelerator | Managed, layer 4 (TCP/UDP) | Pass-through: PQ if client and endpoint (ALB, NLB, EC2) negotiate it | Same connection | Follows the endpoint | Documented (layer-4 service) |
| Amplify Hosting, App Runner, Lightsail distributions, Verified Access | Managed | No TLS policy setting or PQ statement found | n/a | Not confirmed | Unverified |
| Lightsail load balancer | Managed | No: `TLS-2016-08`, `TLS-FS-1-2-Res-2019-08` only | n/a | Not PQ | Documented |

Sources: [CloudFront viewer ciphers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/secure-connections-supported-viewer-protocols-ciphers.html), [CloudFront origin ciphers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/secure-connections-supported-ciphers-cloudfront-to-origin.html), [API Gateway policies](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-security-policies-list.html), [Cognito custom domain](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-add-custom-domain.html), [Transfer Family policies](https://docs.aws.amazon.com/transfer/latest/userguide/security-policies.html), [AppSync custom domains](https://docs.aws.amazon.com/appsync/latest/devguide/custom-domain-name.html). All read 2026-11-14.

(sections 3-7 as written to the doc; files under iac/edge/)
