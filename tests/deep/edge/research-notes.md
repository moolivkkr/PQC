# edge group research notes (2026-11-14)

## ELB (Documented, docs.aws.amazon.com/elasticloadbalancing/latest/{application,network}/describe-ssl-policies.html)
- PQ policies: TLS13-1-2-Res-PQ, -1-2-PQ, -1-2-Ext1-PQ, -1-2-Ext2-PQ, -1-3-PQ, -1-0-PQ (backend), FIPS: -1-2-Res-FIPS-PQ, -1-2-FIPS-PQ, -1-2-Ext0-FIPS-PQ, -1-2-Ext1-FIPS-PQ, -1-2-Ext2-FIPS-PQ, -1-3-FIPS-PQ, -1-0-FIPS-PQ; all suffixed -2025-09.
- Groups: SecP256r1MLKEM768, SecP384r1MLKEM1024, X25519MLKEM768.
- Default: console = TLS13-1-2-Res-PQ-2025-09; CLI/CFN/CDK = ELBSecurityPolicy-2016-08.
- Backend: not selectable; "If any of your listeners are using" PQ -> backend TLS13-1-0-PQ-2025-09; FIPS PQ -> TLS13-1-0-FIPS-PQ-2025-09; RFC9151 wins first.
- "PQ and non-PQ not compatible on same LB": NOT found on the policy pages (search snippet only). Mark not confirmed.
- ALB connection logs: 15 fields; tls_protocol(5), tls_cipher(6), conn_trace_id(12), tls_keyexchange(13), elb(14), ip_address(15). File prefix conn_log_.
- NLB access logs v2.0: 22 fields; tls_cipher(15) tls_protocol_version(16) tls_keyexchange(17) domain_name(18) ... tls_connection_creation_time(22). NLB policy page says positions 5/13 (copied from ALB; inconsistent).
- IAM key elasticloadbalancing:SecurityPolicy: CreateListener, ModifyListener (2015-12-01); CreateLoadBalancerPolicy, SetLoadBalancerPoliciesOfListener (classic). AWS example uses ForAnyValue:StringEquals. CreateLoadBalancer NOT listed (existing tab said so: fix). ListenerProtocol key: CreateListener, ModifyListener, CreateLoadBalancer, CreateLoadBalancerListeners.
- Config: ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK, param sslPolicies (CSV), resource AWS::ElasticLoadBalancingV2::Listener; not in me-central-1, ap-south-2, ap-southeast-4, ca-west-1, eu-south-2, eu-central-2.
- LBC (helm chart 3.6.3): alb.ingress.kubernetes.io/ssl-policy default ELBSecurityPolicy-2016-08; IngressClassParams spec.sslPolicy overrides annotation; NLB service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy default 2016-08; backend-protocol ssl|tcp; controller flag --default-ssl-policy, Helm value defaultSSLPolicy.
- CDK: elbv2.SslPolicy.TLS13_12_RES_PQ etc., PR aws/aws-cdk#36297 merged 2026-03-19.

## CloudFront (Documented)
- Viewer: X25519MLKEM768, SecP256r1MLKEM768, TLS 1.3 only. Policies incl TLSv1.2_2025, TLSv1.3_2025.
- Origin: curves prime256v1, secp384r1, X25519 only; origin ciphers page lists TLS1.2 ciphers.
- Headers: CloudFront-Viewer-TLS-Details JSON {tlsVersion,cipherSuite,handshakeType,keyExchange,signatureScheme,signaturePublicKeyType}; keyExchange e.g. X25519MLKEM768; origin request policy only. Also CloudFront-Viewer-JA3/JA4-Fingerprint, CloudFront-Viewer-TLS.
- Standard + real-time logs: ssl-protocol, ssl-cipher only; no key exchange field.

## API Gateway (Documented)
- Regional/private: SecurityPolicy_TLS13_1_3_2025_09, _TLS13_1_3_FIPS_2025_09, _TLS13_1_2_FIPS_PFS_PQ_2025_09, _TLS13_1_2_PFS_PQ_2025_09, _TLS13_1_2_PQ_2025_09, _TLS13_1_2_2021_06, TLS_1_2, TLS_1_0. No TLS1.3-only PQ policy.
- Edge: SecurityPolicy_TLS13_2025_EDGE, _TLS12_PFS_2025_EDGE, _TLS12_2018_EDGE, TLS_1_2 -- none PQ.
- Enhanced policy requires endpoint access mode BASIC|STRICT; migrate BASIC then STRICT; STRICT->BASIC ~15 min outage; back to legacy needs "".
- HTTP/WebSocket: TLS_1_2 only. Logs: $context.tlsVersion, $context.cipherSuite only.

## WAF (Documented)
- Resources: CloudFront, API GW REST, ALB, AppSync, Cognito user pool, App Runner, Bedrock AgentCore Gateway, Verified Access, Amplify.
- Log fields: no TLS version/cipher/group. ja3Fingerprint (32 hex), ja4Fingerprint (36) only for CloudFront and ALB.
- JA4 (FoxIO technical_details/JA4.md): supported_groups values NOT included, only the extension type codes; GREASE ignored; sorted. JA3 string includes curves list but WAF logs only MD5.

## Third-party
- F5 BIG-IP: X25519MLKEM768 TLS1.3 client+server SSL profiles from 17.5.1; SecP256r/384r from 21.1; tmsh `create ltm cipher rule R cipher DEFAULT dh-groups X25519MLKEM768:DEFAULT signature-algorithms DEFAULT` (techdocs 21.1 integrating-pqc-on-the-client-side).
- NetScaler: front end hybrid PQC, enhanced SSL profile, `bind ssl profile <p> -eccCurveName X25519_MLKEM768` (docs current-release hybrid-pqc; page body not fetched by tool, from search summary -> Claimed until fetched).
- FortiWeb 8.0.3: PQC TLS1.3 via OpenSSL 3.5, CLI client and server side (admin guide 426552; exact syntax not fetched).
