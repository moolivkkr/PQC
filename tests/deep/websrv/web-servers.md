# Web servers, reverse proxies and app servers (self-managed)

Every OpenSSL 3.5, Go 1.24+ and JDK 25 server tested here negotiates X25519MLKEM768 on both legs with one or two lines of config; Envoy and anything on the Amazon Linux 2023 crypto policy stay classical until you set the group list. 110 checks on 13 products, run 2026-11-14 (scripts and logs under `scratchpad/deep/websrv/`).

## What decides PQ here

The TLS library linked into the server binary decides, separately for each leg. **Inbound** (client to server) uses the listener's group list. **Upstream** (server to backend: `proxy_pass`, `ProxyPass`, `server` lines, Envoy clusters) uses the proxy's client-side group list. OpenSSL 3.5 puts X25519MLKEM768 first in its built-in default, so nginx, Apache httpd, HAProxy and Tomcat-native are PQ on both legs with no directive at all, unless a system policy overrides it (Amazon Linux 2023, RHEL-family crypto-policies). Envoy (BoringSSL) defaults to X25519 and P-256 and must be told. Caddy and Traefik use Go's crypto/tls, PQ by default since Go 1.24. Tomcat's JSSE connector follows the JDK (see the Java tab); IIS follows Windows SChannel (see the .NET and Hosts tabs).

## Status matrix

Evidence: **Tested** = run here on 2026-11-14 with the image and version shown (arm64 images). Pass counts are in Verify.

| Product and version | Image or package (compute) | TLS library | Inbound PQ by default | Upstream PQ by default | Setting that controls it | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| nginx 1.31.8 mainline | `nginx:latest` Debian 13 (ECS, Fargate, EKS) | OpenSSL 3.5.7 | Yes | Yes | `ssl_ecdh_curve`, `proxy_ssl_conf_command Groups` | Tested |
| nginx 1.31.8 | `nginx:alpine` Alpine 3.24 | OpenSSL 3.5.9 | Yes | Yes | same | Tested |
| nginx 1.30.6 stable | `nginx:stable` Debian 13 | OpenSSL 3.5.7 | Yes (same OpenSSL) | Yes | same | Tested (version only) |
| nginx 1.30.6 | Amazon Linux 2023 `dnf install nginx` (EC2, AL2023 images) | OpenSSL 3.5.8 + crypto policy | **No** | **No** | explicit directives, or `DEFAULT:PQ` policy (Hosts tab) | Tested |
| Apache httpd 2.4.71 | `httpd:2.4` Debian 13, `httpd:2.4-alpine` | OpenSSL 3.5.7 / 3.5.9 | Yes | Yes | `SSLOpenSSLConfCmd Groups`; no proxy-side directive | Tested |
| Apache httpd (AL2023 package) | Amazon Linux 2023 `dnf install httpd mod_ssl` | OpenSSL 3.5.8 + crypto policy | Yes with `SSLOpenSSLConfCmd` | **No**; Yes after `update-crypto-policies --set DEFAULT:PQ` | crypto policy or `OPENSSL_CONF` | Tested |
| HAProxy 3.4.7 | `haproxy:latest`/`lts` Debian 13, `haproxy:lts-alpine` | OpenSSL 3.5.7 / 3.5.9 | Yes | Yes | `curves` on bind/server lines, `ssl-default-bind-curves`, `ssl-default-server-curves` | Tested |
| Envoy 1.36.13 | `envoyproxy/envoy:v1.36-latest` | BoringSSL | **No** (X25519, P-256) | **No** | `tls_params.ecdh_curves` on both contexts | Tested |
| Envoy 1.36.3 in Istio proxyv2 1.28.0 | `istio/proxyv2:1.28.0` | BoringSSL | No unless set | No unless set | same (Istio sets it for you: Service mesh tab) | Tested |
| Caddy 2.11.9 (Go 1.27.3) | `caddy:2` | Go crypto/tls | Yes | Yes | `tls { curves }`, `transport http { tls_curves }` | Tested |
| Traefik 3.7.19 (Go 1.27.4) | `traefik:v3` | Go crypto/tls | Yes | Yes (Go default; no curve option on serversTransport) | TLS option `curvePreferences` | Tested |
| Tomcat 11.0.29, JSSE connector | `tomcat:11-jdk25-temurin` (JDK 25.0.5) | JDK JSSE | Yes | n/a (app clients: Java tab) | `SSLHostConfig groups` | Tested |
| Tomcat 11.0.29, OpenSSL connector | same image, Ubuntu 26.04 | OpenSSL 3.5.5 via tomcat-native | Yes | n/a | `<OpenSSLConfCmd name="Groups">` | Tested |
| ingress-nginx controller v1.14.0 (nginx 1.27.1) | `registry.k8s.io/ingress-nginx/controller:v1.14.0` Alpine 3.22 | OpenSSL 3.5.4 | Yes | Yes | ConfigMap `ssl-ecdh-curve` | Tested (its nginx binary with the same directives; ConfigMap path not run) |
| nginx/httpd/HAProxy on Ubuntu 24.04 or Debian 12 | distro packages (EC2) | OpenSSL 3.0.x | No, cannot | No, cannot | upgrade OS or use a container image | Tested earlier (Hosts tab) |
| IIS on Windows Server 2025 | SChannel | SChannel | not confirmed | not confirmed | Microsoft lists hybrid ML-KEM groups from the July 14, 2026 update KB5099536 ([Microsoft FAQ](https://techcommunity.microsoft.com/t5/post-quantum-crypto-tech-blog/windows-tls-1-3-and-post-quantum-crypto-faq/ba-p/4556389)); default ordering not confirmed. See .NET and Hosts tabs | Documented (availability only) |

Device types: these are all software on Linux-class compute (EC2, ECS/Fargate, EKS). For managed front doors (ALB, NLB, CloudFront, API Gateway) see the Load balancers and Edge tabs. For appliances (F5, Citrix, firewalls) see Network devices.

## Client side (upstream leg)

The upstream leg is the one most often missed: a PQ listener in front of a classical `proxy_pass` leaves the backend hop exposed. Test it against a PQ-only backend (Verify).

- **nginx** (1.19.4+ for `proxy_ssl_conf_command`). Without it, nginx uses OpenSSL's default list, which is PQ on OpenSSL 3.5 but not under the AL2023 policy (Tested: HTTP 502 to a PQ-only backend).
  ```nginx
  location /api/ {
      proxy_pass https://backend:8443/;
      proxy_ssl_protocols TLSv1.3;
      proxy_ssl_conf_command Groups X25519MLKEM768:X25519;
      proxy_ssl_verify on;
      proxy_ssl_trusted_certificate /etc/ssl/certs/ca.pem;
  }
  ```
- **Apache httpd**: there is no `SSLProxy*` directive for groups; `SSLOpenSSLConfCmd` applies to the server side. The proxy leg takes OpenSSL's default. On Debian/Alpine images that is PQ (Tested). On AL2023 it failed with `AH02003: SSL Proxy connect failed ... handshake failure` until the host policy was set to `DEFAULT:PQ` (Tested). Alternative: point `OPENSSL_CONF` at a PQ config in the unit file (Hosts tab).
  ```apache
  SSLProxyEngine on
  SSLProxyProtocol -all +TLSv1.3
  SSLProxyVerify require
  SSLProxyCACertificateFile /etc/ssl/certs/ca.pem
  ProxyPass /api/ https://backend:8443/
  ```
- **HAProxy**: `curves` on each `server` line, or once in `global` with `ssl-default-server-curves` (accepted by HAProxy 3.4.7, Tested).
  ```haproxy
  backend be_api
      server api1 backend:8443 ssl verify required ca-file /etc/ssl/certs/ca.pem sni str(backend) curves X25519MLKEM768:X25519 ssl-min-ver TLSv1.3
  ```
- **Envoy**: set `ecdh_curves` in the cluster's `UpstreamTlsContext`, and set **both** minimum and maximum version: the upstream maximum defaults to TLS 1.2, so `tls_minimum_protocol_version: TLSv1_3` alone fails with `NO_SUPPORTED_VERSIONS_ENABLED` (Tested). Without `ecdh_curves`, a PQ-only backend returns 503 (Tested).
  ```yaml
  transport_socket:
    name: envoy.transport_sockets.tls
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
      sni: backend
      common_tls_context:
        tls_params:
          tls_minimum_protocol_version: TLSv1_3
          tls_maximum_protocol_version: TLSv1_3
          ecdh_curves: ["X25519MLKEM768", "X25519"]
  ```
- **Caddy**: `tls_curves` in the `reverse_proxy` HTTP transport (Tested; also PQ without it, from Go's default).
  ```caddy
  reverse_proxy https://backend:8443 {
      transport http {
          tls_server_name backend
          tls_curves x25519mlkem768 x25519
      }
  }
  ```
- **Traefik**: `serversTransport` has no curve option ([Traefik 3.7 TLS options](https://doc.traefik.io/traefik/reference/routing-configuration/http/tls/tls-options/)); the backend leg uses Go's default, which includes X25519MLKEM768 in Traefik builds on Go 1.24+ (Tested with 3.7.19).
- **Tomcat as a client** (HttpClient, RestTemplate, WebClient inside the webapp) follows the JDK: see the Java tab.

## Server side (inbound)

Keep a classical fallback (`X25519`, then P-256) after the hybrid group unless you are deliberately enforcing PQ-only. All rows below were Tested with a PQ-only client (got X25519MLKEM768), a default OpenSSL 3.5 client (got X25519MLKEM768), a classical client (got X25519) and a TLS 1.2 client (refused, because each config is TLS 1.3-only).

| Server | Directive (excerpt) | Docs |
| --- | --- | --- |
| nginx | `ssl_protocols TLSv1.3;` `ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1;` | [ssl_ecdh_curve](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_ecdh_curve) |
| Apache httpd | `SSLProtocol -all +TLSv1.3` `SSLOpenSSLConfCmd Groups X25519MLKEM768:X25519:secp256r1` | [SSLOpenSSLConfCmd](https://httpd.apache.org/docs/2.4/mod/mod_ssl.html#sslopensslconfcmd) |
| HAProxy | `bind :443 ssl crt /etc/haproxy/site.pem curves X25519MLKEM768:X25519:P-256 ssl-min-ver TLSv1.3` | [curves](https://docs.haproxy.org/3.2/configuration.html#5.1-curves) |
| Envoy | `DownstreamTlsContext.common_tls_context.tls_params.ecdh_curves: ["X25519MLKEM768","X25519","P-256"]` | [TlsParameters](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/transport_sockets/tls/v3/common.proto) |
| Caddy | `tls cert key { protocols tls1.3  curves x25519mlkem768 x25519 secp256r1 }` | [tls directive](https://caddyserver.com/docs/caddyfile/directives/tls) |
| Traefik | TLS option `minVersion: VersionTLS13`, `curvePreferences: [X25519MLKEM768, X25519, CurveP256]` | [TLS options](https://doc.traefik.io/traefik/reference/routing-configuration/http/tls/tls-options/) |
| Tomcat JSSE | `<SSLHostConfig protocols="TLSv1.3" groups="X25519MLKEM768,x25519,secp256r1">` | [SSLHostConfig groups](https://tomcat.apache.org/tomcat-11.0-doc/config/http.html) |
| Tomcat OpenSSL | `<OpenSSLConf><OpenSSLConfCmd name="Groups" value="X25519MLKEM768:X25519:secp256r1"/></OpenSSLConf>` | same page |

**PQ-only enforcement** (only for internal endpoints whose every client you control): list only `X25519MLKEM768`. Classical clients then fail with `no suitable key share` (Tested on the AL2023 default case, the mirror image of this). Traefik: setting `curvePreferences` without X25519MLKEM768 turns PQ **off**, the same as Go's explicit `CurvePreferences` (Go tab).

**Kubernetes ingress and gateways**

- **ingress-nginx** ConfigMap `ssl-ecdh-curve: "X25519MLKEM768:X25519:prime256v1"` and `ssl-protocols: "TLSv1.3"` (or `"TLSv1.2 TLSv1.3"`). The v1.14.0 image links OpenSSL 3.5.4, so the upstream leg is PQ by default. The project was retired on 2026-03-24 with no further fixes ([Kubernetes blog](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)); plan the move to Gateway API.
- **AWS Load Balancer Controller**: the ALB/NLB terminates TLS, so set the PQ security policy with `alb.ingress.kubernetes.io/ssl-policy` or `service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy`. Policy names and the target-group leg are in the Load balancers tab.
- **Envoy Gateway**: `ClientTrafficPolicy.spec.tls.ecdhCurves` for listeners and `EnvoyProxy.spec.backendTLS` (type BackendTLSConfig, has `ecdhCurves`) for backends. Both default to X25519 and P-256 ([API reference v1.10](https://gateway.envoyproxy.io/docs/api/extension_types/)). Documented; not run here.
- **Istio ingress/egress gateways**: `meshConfig.tlsDefaults.ecdhCurves` or `COMPLIANCE_POLICY=pqc`; see the Service mesh tab.

## Packaging per compute type

Lambda does not apply (no long-running web server). The rule for containers: pick an image on Debian 13 or Alpine 3.22+ and pin it by digest; the config file does the rest.

- **ECS / Fargate**: bake `nginx.conf` into the image (Dockerfile in Full configuration files) and run it from a task definition. Terraform `aws_ecs_task_definition` and CloudFormation `AWS::ECS::TaskDefinition` are below. No environment variable is needed.
- **EKS**: mount the config from a ConfigMap into the pod. For ingress-nginx, set `controller.config.ssl-ecdh-curve` in Helm values. For Envoy Gateway, apply the ClientTrafficPolicy and EnvoyProxy manifests.
- **EC2 on Amazon Linux 2023**: the crypto policy removes ML-KEM from the defaults. Either put the explicit directives in the server config (nginx, HAProxy, httpd inbound), or set the host policy to `DEFAULT:PQ` (needed for the httpd proxy leg). An SSM document that writes the nginx config and reloads it is below in Terraform and CloudFormation; the host-wide policy is in the Hosts tab.
- **EC2 on Ubuntu 24.04 or Debian 12**: OpenSSL 3.0 cannot do ML-KEM. Run the official container image on the host, or move to Ubuntu 26.04 (OpenSSL 3.5.5 seen in the Tomcat image) or AL2023.

## Verify

1. **Posture.** `nginx -V 2>&1 | grep OpenSSL`, `haproxy -vv | grep 'SSL library'`, `envoy --version` (BoringSSL), `caddy version`, `traefik version` (Go 1.24+), `httpd -v` plus `openssl version`. OpenSSL must be 3.5 or later. On AL2023 also run `update-crypto-policies --show`.
2. **Inbound, live.** PQ client must get the hybrid group; classical client must still connect:
   ```sh
   openssl s_client -connect host:443 -tls1_3 -groups X25519MLKEM768 </dev/null 2>&1 | grep 'Negotiated TLS1.3 group'
   # Negotiated TLS1.3 group: X25519MLKEM768
   openssl s_client -connect host:443 -tls1_3 -groups X25519 </dev/null 2>&1 | grep 'Peer Temp Key'
   # Peer Temp Key: X25519, 253 bits
   openssl s_client -connect host:443 -tls1_2 </dev/null   # must fail when the listener is 1.3-only
   ```
3. **Upstream, live.** Point a test route at a PQ-only backend (`openssl s_server -accept 8443 -www -tls1_3 -groups X25519MLKEM768 ...`) and at a classical-only one (`-groups X25519`); both must return HTTP 200 through the proxy.
4. **Logs and metrics.** nginx: `$ssl_curve` in `log_format` (Tested: `proto=TLSv1.3 ... group=X25519MLKEM768`). Envoy: admin `/stats` counters `listener.<addr>.ssl.curves.X25519MLKEM768` and `cluster.<name>.ssl.curves.X25519MLKEM768` (Tested). Apache httpd and HAProxy have no group variable in their log formats (not found in this test); use the s_client checks or packet capture (Network devices tab).

**Results, 2026-11-14:** 110 checks passed across nginx (Debian, Alpine, AL2023), httpd (Debian, Alpine, AL2023), HAProxy (Debian, Alpine), Envoy (upstream and Istio builds), Caddy, Traefik, Tomcat (JSSE and OpenSSL) and the ingress-nginx nginx binary. Four further checks were the expected negatives: AL2023 nginx with no group directive negotiated X25519 and refused a PQ-only client, its upstream returned 502, and the AL2023 httpd proxy returned 500 until `DEFAULT:PQ` was set. Kyverno policies (Service mesh tab) passed 3 compliant and flagged 3 non-compliant test resources.

## Pitfalls and rollback

- **Envoy upstream TLS maximum defaults to 1.2.** Setting only the minimum to 1.3 gives `NO_SUPPORTED_VERSIONS_ENABLED` and 503s. Set both (Tested).
- **Envoy has no ML-KEM by default.** Without `ecdh_curves`, a PQ-only client is refused and a PQ-only backend gives 503 (Tested).
- **Amazon Linux 2023 crypto policy** drops ML-KEM from OpenSSL defaults, even with OpenSSL 3.5.8. Explicit server directives work; the Apache proxy leg needs the host policy (Tested).
- **Old OpenSSL rejects the name.** On OpenSSL 3.0 hosts, a config naming X25519MLKEM768 is expected to fail at load (`nginx -t`, `haproxy -c`): not tested here, so run the config check in CI before rollout.
- **Explicit lists replace the default.** Traefik `curvePreferences` or an nginx `ssl_ecdh_curve` without X25519MLKEM768 turns PQ off.
- **PQ-only listeners lock out classical clients.** Keep `X25519` after the hybrid group on anything internet-facing. A community report describes intermittent failures after forcing PQ-only on nginx ([forum thread](https://community.nginx.org/t/error-when-trying-to-enforce-pqc-hndl-resistant-nginx-configuration-no-suitable-key-share/9558), Claimed).
- **Larger ClientHello** (about 1.2 KB more) can upset old middleboxes on the upstream path; see Network devices.
- **ingress-nginx is retired**: fixes stop, so plan the Gateway API move rather than relying on it long term.
- **Rollback:** remove the group directive, or put `X25519` first, then reload (`nginx -s reload`, `systemctl reload haproxy`, Envoy hot restart or xDS push). No restart of clients is needed. On AL2023, `update-crypto-policies --set DEFAULT` and restart the service.

## Full configuration files

All files below were used in the tests, apart from the AWS IaC (not deployed: no AWS credentials here). Lab shortcuts (`verify none`, `insecure_skip_verify`) are marked; use CA verification in production.

`/etc/nginx/nginx.conf`
```nginx
@@nginx.conf@@
```

`/usr/local/apache2/conf/httpd.conf` (official image; on AL2023 use `ServerRoot "/etc/httpd"`, `User apache`, DocumentRoot `/var/www/html`)
```apache
@@httpd.conf@@
```

`/usr/local/etc/haproxy/haproxy.cfg`
```haproxy
@@haproxy.cfg@@
```

`/etc/envoy/envoy.yaml`
```yaml
@@envoy.yaml@@
```

`/etc/caddy/Caddyfile`
```caddy
@@Caddyfile@@
```

`/etc/traefik/traefik.yml`
```yaml
@@traefik.yml@@
```

`/etc/traefik/dynamic.yml`
```yaml
@@dynamic.yml@@
```

`/usr/local/tomcat/conf/server.xml` (JSSE)
```xml
@@server.xml@@
```

`/usr/local/tomcat/conf/server.xml` (OpenSSL implementation)
```xml
@@server-openssl.xml@@
```

`ingress-nginx-values.yaml` (Helm)
```yaml
@@ingress-nginx-values.yaml@@
```

`envoy-gateway-pq.yaml`
```yaml
@@envoy-gateway-pq.yaml@@
```

`Dockerfile` (nginx for ECS/Fargate/EKS)
```dockerfile
@@Dockerfile.nginx@@
```

`ecs-nginx.tf` (Terraform)
```hcl
@@ecs-nginx.tf@@
```

`ecs-nginx.yaml` (CloudFormation)
```yaml
@@ecs-nginx.cfn.yaml@@
```

`ssm-nginx-pq.tf` and `ssm-nginx-pq.cfn.yaml` (EC2 on AL2023)
```hcl
@@ssm-nginx-pq.tf@@
```
```yaml
@@ssm-nginx-pq.cfn.yaml@@
```
