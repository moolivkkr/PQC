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
# /etc/nginx/nginx.conf - PQ hybrid TLS on the listener and on the proxy_pass (upstream) leg
# Needs nginx linked against OpenSSL 3.5+ (nginx:1.29+/stable on Debian 13 or Alpine 3.22+).
worker_processes auto;
events { worker_connections 1024; }

http {
    access_log /dev/stdout;
    error_log  /dev/stderr info;

    # Log the negotiated group per request ($ssl_curve, nginx 1.21.5+).
    log_format tls '$remote_addr "$request" $status proto=$ssl_protocol '
                   'cipher=$ssl_cipher group=$ssl_curve';

    # ---- Server side (inbound) ----
    server {
        listen 8443 ssl;
        server_name srv;
        access_log /dev/stdout tls;

        ssl_certificate     /certs/server.crt;
        ssl_certificate_key /certs/server.key;

        # TLS 1.3 only. Use "TLSv1.2 TLSv1.3" if you still have 1.2-only clients.
        ssl_protocols TLSv1.3;
        # Hybrid first, classical fallback for clients that do not offer ML-KEM.
        ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1;

        location / { return 200 "ok group=$ssl_curve\n"; }
    }

    # ---- Client side (upstream / proxy_pass) ----
    server {
        listen 8080;

        location /pq/ {
            proxy_pass https://be:8443/;          # PQ-only backend
            proxy_ssl_server_name on;
            proxy_ssl_name be;
            proxy_ssl_protocols TLSv1.3;
            # nginx 1.19.4+: pass Groups straight to OpenSSL for the upstream leg.
            proxy_ssl_conf_command Groups X25519MLKEM768:X25519;
            # Production: proxy_ssl_verify on; proxy_ssl_trusted_certificate /etc/ssl/certs/ca.pem;
        }

        location /classic/ {
            proxy_pass https://be:9443/;          # classical-only backend (fallback check)
            proxy_ssl_server_name on;
            proxy_ssl_name be;
            proxy_ssl_protocols TLSv1.3;
            proxy_ssl_conf_command Groups X25519MLKEM768:X25519;
        }
    }
}
```

`/usr/local/apache2/conf/httpd.conf` (official image; on AL2023 use `ServerRoot "/etc/httpd"`, `User apache`, DocumentRoot `/var/www/html`)
```apache
# /usr/local/apache2/conf/httpd.conf - minimal, complete. PQ hybrid inbound (mod_ssl) and on the reverse-proxy leg.
# Needs Apache httpd 2.4.x with mod_ssl linked against OpenSSL 3.5+ (httpd:2.4 on Debian 13 / Alpine 3.22+).
ServerRoot "/usr/local/apache2"
ServerName srv
Listen 8443
Listen 8080

LoadModule mpm_event_module      modules/mod_mpm_event.so
LoadModule authz_core_module     modules/mod_authz_core.so
LoadModule unixd_module          modules/mod_unixd.so
LoadModule log_config_module     modules/mod_log_config.so
LoadModule mime_module           modules/mod_mime.so
LoadModule dir_module            modules/mod_dir.so
LoadModule ssl_module            modules/mod_ssl.so
LoadModule socache_shmcb_module  modules/mod_socache_shmcb.so
LoadModule proxy_module          modules/mod_proxy.so
LoadModule proxy_http_module     modules/mod_proxy_http.so

User daemon
Group daemon
ErrorLog /proc/self/fd/2
LogLevel warn ssl:info
# %{SSL_PROTOCOL}x / %{SSL_CIPHER}x are standard. mod_ssl has no "negotiated group" variable,
# so the group itself is not loggable here (check with s_client or a packet capture).
LogFormat "%h \"%r\" %>s %{SSL_PROTOCOL}x %{SSL_CIPHER}x" tls
CustomLog /proc/self/fd/1 tls

SSLSessionCache shmcb:/tmp/ssl_scache(512000)

# ---- Server side (inbound) ----
<VirtualHost *:8443>
    SSLEngine on
    SSLCertificateFile    /certs/server.crt
    SSLCertificateKeyFile /certs/server.key
    SSLProtocol -all +TLSv1.3
    # Passed to OpenSSL SSL_CONF: hybrid first, classical fallback.
    SSLOpenSSLConfCmd Groups X25519MLKEM768:X25519:secp256r1
    DocumentRoot /usr/local/apache2/htdocs
    <Directory /usr/local/apache2/htdocs>
        Require all granted
    </Directory>
</VirtualHost>

# ---- Client side (reverse proxy to TLS backends) ----
<VirtualHost *:8080>
    SSLProxyEngine on
    SSLProxyProtocol -all +TLSv1.3
    # Lab only. Production: SSLProxyVerify require + SSLProxyCACertificateFile.
    SSLProxyVerify none
    SSLProxyCheckPeerName off
    SSLProxyCheckPeerCN off
    # There is no SSLProxy* directive for groups: the proxy leg uses OpenSSL's default group list
    # (X25519MLKEM768 first on OpenSSL 3.5), or whatever the system openssl.cnf sets.
    ProxyPass        /pq/      https://be:8443/
    ProxyPass        /classic/ https://be:9443/
</VirtualHost>
```

`/usr/local/etc/haproxy/haproxy.cfg`
```haproxy
# /usr/local/etc/haproxy/haproxy.cfg - PQ hybrid on bind (inbound) and server (upstream) lines.
# Needs HAProxy built against OpenSSL 3.5+ (haproxy:3.x on Debian 13 / Alpine 3.22+).
global
    log stdout format raw local0 info
    # Defaults for every bind line / every server line
    ssl-default-bind-curves   X25519MLKEM768:X25519:P-256
    ssl-default-bind-options  ssl-min-ver TLSv1.3
    ssl-default-server-curves X25519MLKEM768:X25519:P-256
    ssl-default-server-options ssl-min-ver TLSv1.3

defaults
    mode http
    log global
    # %sslv / %sslc are protocol and cipher; HAProxy 3.x has no fetch for the negotiated group name.
    log-format "%ci \"%r\" %ST %sslv %sslc"
    timeout connect 5s
    timeout client  10s
    timeout server  10s

# ---- Server side (inbound) ----
frontend fe_tls
    bind :8443 ssl crt /certs/server.pem curves X25519MLKEM768:X25519:P-256 ssl-min-ver TLSv1.3
    http-request return status 200 content-type text/plain string "ok"

# ---- Client side (upstream) ----
frontend fe_http
    bind :8080
    use_backend be_pq if { path_beg /pq/ }
    default_backend be_classic

backend be_pq
    # Lab only: verify none. Production: verify required ca-file /etc/ssl/certs/ca.pem sni str(be)
    server pq be:8443 ssl verify none curves X25519MLKEM768:X25519 ssl-min-ver TLSv1.3

backend be_classic
    server cl be:9443 ssl verify none curves X25519MLKEM768:X25519 ssl-min-ver TLSv1.3
```

`/etc/envoy/envoy.yaml`
```yaml
# /etc/envoy/envoy.yaml - standalone Envoy: PQ hybrid downstream (listener) and upstream (cluster) TLS.
# Envoy default ecdh_curves is X25519, P-256 (no ML-KEM): you must set the list on BOTH sides.
admin:
  address: { socket_address: { address: 0.0.0.0, port_value: 9901 } }

static_resources:
  listeners:
  # ---- Server side (downstream TLS) ----
  - name: tls_in
    address: { socket_address: { address: 0.0.0.0, port_value: 8443 } }
    filter_chains:
    - transport_socket:
        name: envoy.transport_sockets.tls
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
          common_tls_context:
            tls_params:
              tls_minimum_protocol_version: TLSv1_3
              tls_maximum_protocol_version: TLSv1_3
              ecdh_curves: ["X25519MLKEM768", "X25519", "P-256"]
            tls_certificates:
            - certificate_chain: { filename: /certs/server.crt }
              private_key: { filename: /certs/server.key }
      filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: tls_in
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
              log_format:
                text_format_source:
                  inline_string: "%REQ(:PATH)% %RESPONSE_CODE% %DOWNSTREAM_TLS_VERSION% %DOWNSTREAM_TLS_CIPHER%\n"
          route_config:
            virtual_hosts:
            - name: local
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                direct_response: { status: 200, body: { inline_string: "ok\n" } }
          http_filters:
          - name: envoy.filters.http.router
            typed_config: { "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router }

  # ---- Client side (plain HTTP in, TLS to backends) ----
  - name: http_in
    address: { socket_address: { address: 0.0.0.0, port_value: 8080 } }
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: http_in
          route_config:
            virtual_hosts:
            - name: backends
              domains: ["*"]
              routes:
              - match: { prefix: "/pq/" }
                route: { cluster: be_pq, prefix_rewrite: "/" }
              - match: { prefix: "/classic/" }
                route: { cluster: be_classic, prefix_rewrite: "/" }
          http_filters:
          - name: envoy.filters.http.router
            typed_config: { "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router }

  clusters:
  - name: be_pq
    type: STRICT_DNS
    load_assignment:
      cluster_name: be_pq
      endpoints: [{ lb_endpoints: [{ endpoint: { address: { socket_address: { address: be, port_value: 8443 } } } }] }]
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: be
        common_tls_context:
          tls_params:
            tls_minimum_protocol_version: TLSv1_3
            tls_maximum_protocol_version: TLSv1_3   # upstream max defaults to TLSv1_2!
            ecdh_curves: ["X25519MLKEM768", "X25519"]
          # Production: validation_context: { trusted_ca: { filename: /etc/ssl/certs/ca.pem } }
  - name: be_classic
    type: STRICT_DNS
    load_assignment:
      cluster_name: be_classic
      endpoints: [{ lb_endpoints: [{ endpoint: { address: { socket_address: { address: be, port_value: 9443 } } } }] }]
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: be
        common_tls_context:
          tls_params:
            tls_minimum_protocol_version: TLSv1_3
            tls_maximum_protocol_version: TLSv1_3   # upstream max defaults to TLSv1_2!
            ecdh_curves: ["X25519MLKEM768", "X25519"]
```

`/etc/caddy/Caddyfile`
```caddy
# /etc/caddy/Caddyfile - Caddy 2.10+ (Go 1.24+): X25519MLKEM768 is in Go's default list, so the
# explicit "curves" lines below only pin the order and make the intent auditable.
{
	auto_https off
	log {
		output stdout
	}
}

# ---- Server side (inbound) ----
https://:8443 {
	tls /certs/server.crt /certs/server.key {
		protocols tls1.3
		curves x25519mlkem768 x25519 secp256r1
	}
	respond "ok"
}

# ---- Client side (reverse_proxy to TLS backends) ----
:8080 {
	handle_path /pq/* {
		reverse_proxy https://be:8443 {
			transport http {
				tls_server_name be
				tls_insecure_skip_verify   # lab only; production: tls_trust_pool file /etc/ssl/certs/ca.pem
				tls_curves x25519mlkem768 x25519
			}
		}
	}
	handle_path /classic/* {
		reverse_proxy https://be:9443 {
			transport http {
				tls_server_name be
				tls_insecure_skip_verify
				tls_curves x25519mlkem768 x25519
			}
		}
	}
}
```

`/etc/traefik/traefik.yml`
```yaml
# /etc/traefik/traefik.yml - static configuration
entryPoints:
  websecure:
    address: ":8443"
  web:
    address: ":8080"
providers:
  file:
    filename: /etc/traefik/dynamic.yml
log:
  level: INFO
accessLog: {}
```

`/etc/traefik/dynamic.yml`
```yaml
# /etc/traefik/dynamic.yml - dynamic configuration (file provider)
tls:
  certificates:
    - certFile: /certs/server.crt
      keyFile: /certs/server.key
  options:
    default:                       # applies to every TLS router unless a router names another option
      minVersion: VersionTLS13
      curvePreferences:
        - X25519MLKEM768
        - X25519
        - CurveP256

http:
  routers:
    tls-in:
      entryPoints: [websecure]
      rule: "PathPrefix(`/`)"
      tls: {}
      service: be-classic          # inbound test only checks the handshake
    pq:
      entryPoints: [web]
      rule: "PathPrefix(`/pq/`)"
      middlewares: [strip]
      service: be-pq
    classic:
      entryPoints: [web]
      rule: "PathPrefix(`/classic/`)"
      middlewares: [strip]
      service: be-classic
  middlewares:
    strip:
      stripPrefix:
        prefixes: ["/pq", "/classic"]
  serversTransports:
    backend-tls:
      serverName: be
      insecureSkipVerify: true     # lab only; production: rootCAs: [/etc/ssl/certs/ca.pem]
      # No curve setting on serversTransport: the upstream leg uses Go's default list,
      # which includes X25519MLKEM768 in Go 1.24+ (Traefik 3.4+ builds).
  services:
    be-pq:
      loadBalancer:
        serversTransport: backend-tls
        servers: [{ url: "https://be:8443" }]
    be-classic:
      loadBalancer:
        serversTransport: backend-tls
        servers: [{ url: "https://be:9443" }]
```

`/usr/local/tomcat/conf/server.xml` (JSSE)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- /usr/local/tomcat/conf/server.xml - Tomcat 11, JSSE connector (Java's own TLS stack).
     PQ comes from the JDK: JDK 25.0.5+ (Temurin/Corretto) offers X25519MLKEM768 by default.
     On Java 8-21 use the Bouncy Castle JSSE agent from the Java tab instead. -->
<Server port="-1" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Service name="Catalina">
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               SSLEnabled="true" maxThreads="50"
               sslImplementationName="org.apache.tomcat.util.net.jsse.JSSEImplementation">
      <!-- groups = named groups in preference order (JSSE names). Omit it to use jdk.tls.namedGroups / JDK default. -->
      <SSLHostConfig protocols="TLSv1.3" groups="X25519MLKEM768,x25519,secp256r1">
        <Certificate certificateKeystoreFile="/certs/server.p12"
                     certificateKeystoreType="PKCS12"
                     certificateKeystorePassword="changeit" />
      </SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="false" autoDeploy="false" />
    </Engine>
  </Service>
</Server>
```

`/usr/local/tomcat/conf/server.xml` (OpenSSL implementation)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- /usr/local/tomcat/conf/server.xml - Tomcat 11, NIO connector with the OpenSSL implementation
     (tomcat-native / libtcnative linked to the system OpenSSL). PQ then depends on the image's OpenSSL:
     3.5+ needed (tomcat:11-jdk25 on Ubuntu 26.04 ships 3.5.x; Ubuntu 24.04-based images ship 3.0 = no PQ). -->
<Server port="-1" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" />
  <Service name="Catalina">
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               SSLEnabled="true" maxThreads="50"
               sslImplementationName="org.apache.tomcat.util.net.openssl.OpenSSLImplementation">
      <SSLHostConfig protocols="TLSv1.3">
        <!-- Passed to OpenSSL SSL_CONF_cmd, same as nginx ssl_conf_command / Apache SSLOpenSSLConfCmd -->
        <OpenSSLConf>
          <OpenSSLConfCmd name="Groups" value="X25519MLKEM768:X25519:secp256r1" />
        </OpenSSLConf>
        <Certificate certificateFile="/certs/server.crt"
                     certificateKeyFile="/certs/server.key"
                     type="EC" />
      </SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="false" autoDeploy="false" />
    </Engine>
  </Service>
</Server>
```

`ingress-nginx-values.yaml` (Helm)
```yaml
# ingress-nginx-values.yaml - helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx -f ingress-nginx-values.yaml
# Controller v1.14.0 links OpenSSL 3.5.4 (checked 2026-11-14). The project was retired 2026-03-24: plan a Gateway API move.
controller:
  image:
    # pin by digest
    digest: sha256:e4127065d0317bd11dc64c4dd38dcf7fb1c3d72e468110b4086e636dbaac943d
  config:
    # rendered into nginx.conf as ssl_ecdh_curve / ssl_protocols for every TLS server block
    ssl-ecdh-curve: "X25519MLKEM768:X25519:prime256v1"
    ssl-protocols: "TLSv1.3"            # "TLSv1.2 TLSv1.3" if 1.2-only clients remain
    # Upstream (backend-protocol: HTTPS) uses OpenSSL's default list, X25519MLKEM768 first on 3.5.
    # For an explicit upstream list, add to the http block via a snippet (needs allow-snippet-annotations / snippets enabled):
    # http-snippet: |
    #   proxy_ssl_conf_command Groups X25519MLKEM768:X25519;
```

`envoy-gateway-pq.yaml`
```yaml
# envoy-gateway-pq.yaml - Envoy Gateway (Gateway API). Field names from the v1.10 API reference; not run here.
# Listener side: ClientTrafficPolicy.spec.tls (ClientTLSSettings). Backend side: EnvoyProxy.spec.backendTLS (BackendTLSConfig).
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: pq-listener
  namespace: default
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: eg
  tls:
    minVersion: "1.3"
    maxVersion: "1.3"
    ecdhCurves: ["X25519MLKEM768", "X25519", "P-256"]
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: pq-proxy
  namespace: envoy-gateway-system
spec:
  backendTLS:
    minVersion: "1.3"
    maxVersion: "1.3"      # Envoy's upstream maximum otherwise defaults to 1.2
    ecdhCurves: ["X25519MLKEM768", "X25519"]
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: pq-proxy
    namespace: envoy-gateway-system
```

`Dockerfile` (nginx for ECS/Fargate/EKS)
```dockerfile
# Dockerfile - nginx with PQ hybrid TLS. nginx:1.31.8 on Debian 13, OpenSSL 3.5.7 (checked 2026-11-14).
# Pin by digest; refresh the digest when you patch.
FROM nginx@sha256:165ddde8751e75a1c907d24ef10d9f6deb08b57e0fe56caf67512486aff76d82
COPY nginx.conf /etc/nginx/nginx.conf
# Certificates: mount from Secrets Manager/ACM-exported files or a Kubernetes Secret at /certs at runtime.
RUN nginx -V 2>&1 | grep -q 'OpenSSL 3\.[5-9]' || (echo "nginx not linked to OpenSSL 3.5+" && exit 1)
EXPOSE 8443 8080
```

`ecs-nginx.tf` (Terraform)
```hcl
# ecs-nginx.tf - Fargate task running the PQ nginx image built from the Dockerfile above.
variable "image" {
  description = "ECR image by digest, e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com/pq-nginx@sha256:..."
  type        = string
}
variable "execution_role_arn" { type = string }

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/pq-nginx"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "nginx" {
  family                   = "pq-nginx"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  container_definitions = jsonencode([{
    name         = "nginx"
    image        = var.image
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    # nginx access log carries group=$ssl_curve -> CloudWatch Logs Insights can count non-PQ handshakes
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.nginx.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "nginx"
      }
    }
    healthCheck = {
      command  = ["CMD-SHELL", "nginx -t || exit 1"]
      interval = 30
      retries  = 3
    }
  }])
}

data "aws_region" "current" {}
```

`ecs-nginx.yaml` (CloudFormation)
```yaml
# ecs-nginx.yaml - CloudFormation equivalent of ecs-nginx.tf
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  Image:
    Type: String
    Description: ECR image by digest (repo@sha256:...)
  ExecutionRoleArn:
    Type: String
Resources:
  LogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: /ecs/pq-nginx
      RetentionInDays: 30
  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: pq-nginx
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: "256"
      Memory: "512"
      ExecutionRoleArn: !Ref ExecutionRoleArn
      RuntimePlatform:
        OperatingSystemFamily: LINUX
        CpuArchitecture: ARM64
      ContainerDefinitions:
        - Name: nginx
          Image: !Ref Image
          Essential: true
          PortMappings:
            - ContainerPort: 8443
              Protocol: tcp
          LogConfiguration:
            LogDriver: awslogs
            Options:
              awslogs-group: !Ref LogGroup
              awslogs-region: !Ref AWS::Region
              awslogs-stream-prefix: nginx
          HealthCheck:
            Command: ["CMD-SHELL", "nginx -t || exit 1"]
            Interval: 30
            Retries: 3
```

`ssm-nginx-pq.tf` and `ssm-nginx-pq.cfn.yaml` (EC2 on AL2023)
```hcl
# ssm-nginx-pq.tf - EC2 (Amazon Linux 2023): add PQ group lines to nginx and reload.
# Assumes the site config lives in /etc/nginx/conf.d/*.conf. Run with State Manager or Run Command.
resource "aws_ssm_document" "nginx_pq" {
  name            = "PQ-Nginx-Groups"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-DOC
    schemaVersion: "2.2"
    description: "Enable X25519MLKEM768 on nginx inbound and proxy_pass legs (AL2023)"
    mainSteps:
      - action: aws:runShellScript
        name: nginxPq
        inputs:
          runCommand:
            - set -euo pipefail
            - nginx -V 2>&1 | grep -q 'OpenSSL 3\.[5-9]' || { echo "nginx OpenSSL < 3.5"; exit 1; }
            - |
              cat > /etc/nginx/conf.d/00-pq-tls.conf <<'EOF'
              # http-level defaults; server blocks inherit unless they override
              ssl_protocols TLSv1.2 TLSv1.3;
              ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1;
              proxy_ssl_protocols TLSv1.2 TLSv1.3;
              proxy_ssl_conf_command Groups X25519MLKEM768:X25519:prime256v1;
              EOF
            - nginx -t
            - systemctl reload nginx
            - echo | openssl s_client -connect 127.0.0.1:443 -tls1_3 -groups X25519MLKEM768 2>&1 | grep 'Negotiated TLS1.3 group'
  DOC
}
```
```yaml
# ssm-nginx-pq.yaml - CloudFormation equivalent of ssm-nginx-pq.tf
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  NginxPqDocument:
    Type: AWS::SSM::Document
    Properties:
      Name: PQ-Nginx-Groups
      DocumentType: Command
      DocumentFormat: YAML
      Content:
        schemaVersion: "2.2"
        description: Enable X25519MLKEM768 on nginx inbound and proxy_pass legs (AL2023)
        mainSteps:
          - action: aws:runShellScript
            name: nginxPq
            inputs:
              runCommand:
                - set -euo pipefail
                - nginx -V 2>&1 | grep -q 'OpenSSL 3\.[5-9]' || { echo "nginx OpenSSL < 3.5"; exit 1; }
                - |
                  cat > /etc/nginx/conf.d/00-pq-tls.conf <<'EOF'
                  ssl_protocols TLSv1.2 TLSv1.3;
                  ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1;
                  proxy_ssl_protocols TLSv1.2 TLSv1.3;
                  proxy_ssl_conf_command Groups X25519MLKEM768:X25519:prime256v1;
                  EOF
                - nginx -t
                - systemctl reload nginx
                - echo | openssl s_client -connect 127.0.0.1:443 -tls1_3 -groups X25519MLKEM768 2>&1 | grep 'Negotiated TLS1.3 group'
```
