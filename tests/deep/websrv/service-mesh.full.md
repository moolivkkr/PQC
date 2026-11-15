# Service mesh and east-west traffic

Linkerd 2.19+ is PQ for meshed traffic by default. Istio 1.27+ and Consul 2.1+ need one setting, and Istio's setting enforces PQ-only. Cilium's node encryption, ECS Service Connect and Kuma have no PQ key-exchange setting that we could find. App Mesh was shut down on 2026-09-30. Envoy configs and Kyverno guardrails were tested locally on 2026-11-14; no cluster was stood up.

## What decides PQ here

The mesh proxy's TLS library and the group list the control plane pushes to it. The app talks plaintext to its local proxy, and proxy-to-proxy mTLS carries the hop: Envoy (BoringSSL) in Istio sidecars, Istio gateways, Consul and ECS Service Connect; the Rust proxies (Linkerd proxy, Istio ztunnel) use aws-lc. If the app does its own TLS, the mesh only forwards the encrypted bytes and the app's runtime decides (language tabs). Gateways and TLS origination to external hosts are "non-mesh TLS" and often have a separate setting. Certificate signatures stay classical in every mesh listed (Certificates (ML-DSA) tab).

## Status matrix

| Mesh and version | Data path | PQ by default | How to turn on | Compute | Evidence |
| --- | --- | --- | --- | --- | --- |
| Linkerd 2.19+ (from edge-25.8.4) | Meshed pod-to-pod mTLS | **Yes**, prefers X25519MLKEM768 | Upgrade control plane, restart workloads | EKS | Documented ([2.19 announcement](https://linkerd.io/2025/10/31/announcing-linkerd-2.19/), [edge-25.8.4](https://linkerd.io/2025/09/05/linkerd-edge-release-roundup/)) |
| Istio 1.27+ sidecar | Envoy-to-Envoy mTLS, gateway downstream and upstream, xDS | No | `COMPLIANCE_POLICY=pqc` on istiod: TLS 1.3 and X25519MLKEM768 **only** | EKS | Documented ([1.27 change notes](https://istio.io/latest/news/releases/1.27.x/announcing-1.27/change-notes/)); Helm render Tested |
| Istio 1.27+ ambient | ztunnel HBONE mTLS, waypoints | No | `COMPLIANCE_POLICY=pqc` on istiod **and** ztunnel | EKS | Documented; Helm render Tested |
| Istio gateways and TLS origination | Ingress/egress listeners, DestinationRule `SIMPLE` | No | `meshConfig.tlsDefaults.ecdhCurves: [X25519MLKEM768, X25519]` (mesh-wide; not mesh mTLS) | EKS | Documented ([Red Hat OSSM 3.3](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.3/html/installing/ossm-pqc-install)); Helm render Tested |
| Istio proxyv2 1.28.0 (Envoy 1.36.3) | Proxy binary | No unless pushed | Accepts `X25519MLKEM768` in `ecdh_curves`, both directions | any | Tested |
| Envoy 1.36.13 standalone or self-managed sidecar | Listener and cluster TLS | No (X25519, P-256) | `ecdh_curves` both sides, TLS 1.3 min **and** max upstream | ECS, EKS, EC2 | Tested |
| Consul 2.1+ | Mesh incoming and outgoing, agent RPC/HTTPS/gRPC | Yes when TLS 1.3 is the minimum and the list is empty | Mesh config entry `TLS.Incoming/Outgoing`, agent `tls_ecdh_curves` | EKS, ECS, EC2 | Documented ([Consul PQ TLS](https://developer.hashicorp.com/consul/docs/secure/encryption/post-quantum)) |
| Consul ingress and API gateway external listeners | North-south TLS | No (Envoy default) | No setting exposed | EKS, ECS, EC2 | Documented |
| Cilium WireGuard | Node-to-node | No (WireGuard Curve25519) | No PQ option found in Cilium docs | EKS | Unverified |
| Cilium IPsec | Node-to-node | Not applicable: pre-shared keys from the `cilium-ipsec-keys` Secret, no public-key exchange | Use per-tunnel keys (`3+`), rotate | EKS | Documented ([Cilium IPsec](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)) |
| Cilium ztunnel encryption (1.19+, beta) | Pod-to-pod mTLS | Not documented | none found | EKS | Unverified |
| ECS Service Connect TLS | Task-to-task via AWS-managed Envoy, TLS 1.3 | Not documented; no key-exchange setting | none; use a self-managed Envoy sidecar or app TLS | ECS | Documented (TLS 1.3 only: [ECS docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect-tls.html)); PQ Unverified |
| AWS App Mesh | n/a | n/a | Discontinued 2026-09-30; console and resources gone | ECS, EKS, EC2 | Documented ([App Mesh guide](https://docs.aws.amazon.com/app-mesh/latest/userguide/what-is-app-mesh.html)) |
| Kuma / Kong Mesh | Envoy mTLS | No PQ setting found | none found | EKS, EC2 | Unverified |

Lambda functions are not meshed; their outbound TLS is the language tabs.

## Client side (app level)

Inside a mesh, the best client setting is none: send plaintext HTTP to the local proxy and let the mesh do mTLS. Then PQ follows the mesh row above, whatever language the app uses.

- **Calls to services inside the mesh**: use `http://svc.ns.svc.cluster.local`. If the app uses `https://` itself, the mesh only passes the bytes through, and the app's runtime picks the groups (Go, Python, Node.js, Java, .NET tabs).
- **Calls to external hosts (egress)**: either the app does TLS (language tab), or the app sends plain HTTP and Istio originates TLS with a `ServiceEntry` plus a `DestinationRule` in `tls.mode: SIMPLE`. Origination is non-mesh TLS, so it follows `meshConfig.tlsDefaults.ecdhCurves` or `COMPLIANCE_POLICY=pqc`.
  ```yaml
  trafficPolicy:
    portLevelSettings:
    - port: { number: 443 }
      tls: { mode: SIMPLE, sni: api.partner.example, credentialName: partner-ca }
  ```
- **Linkerd**: traffic to unmeshed or external destinations is not mesh mTLS; PQ there is the app's own TLS.
- **ECS without a PQ mesh**: run a self-managed Envoy sidecar; the app calls `http://127.0.0.1:8080/<service>/` and Envoy originates TLS with `ecdh_curves` (task definition and Dockerfile in Full configuration files; Envoy config in the Web servers tab).

## Server side (mesh control plane and proxies)

- **Istio (enforcing, all proxy TLS)**: istiod Helm values `pilot.env.COMPLIANCE_POLICY: pqc`; ambient adds the ztunnel chart value `env.COMPLIANCE_POLICY: pqc`. Restart workloads so proxies reconnect.
  ```yaml
  pilot:
    env:
      COMPLIANCE_POLICY: pqc
  ```
- **Istio (gateways only, with fallback)**: `meshConfig.tlsDefaults.ecdhCurves: [X25519MLKEM768, X25519]`. Use this for internet-facing gateways, because `COMPLIANCE_POLICY=pqc` also covers gateway downstream TLS and would refuse classical clients.
- **Linkerd 2.19+**: nothing to set. `helm upgrade linkerd-crds` then `linkerd-control-plane`, then `kubectl rollout restart` each meshed workload.
- **Consul 2.1+**: mesh config entry and agent TLS:
  ```hcl
  Kind = "mesh"
  TLS {
    Outgoing {
      TLSMinVersion = "TLSv1_3"
      TLSMaxVersion = "TLSv1_3"
      ECDHCurves    = ["X25519MLKEM768", "X25519"]
    }
  }
  ```
  `Incoming` takes the same three keys. Agent `tls.defaults`: `tls_min_version = "TLSv1_3"` and `tls_ecdh_curves = "X25519MLKEM768,X25519"` (a comma-separated string, not a list). Allowed names: X25519MLKEM768, X25519, P-256, P-384, P-521.
- **Envoy self-managed**: `ecdh_curves: ["X25519MLKEM768", "X25519"]` in both `DownstreamTlsContext` and `UpstreamTlsContext` (Tested; full file in the Web servers tab).
- **Cilium**: keep IPsec per-tunnel keys (`3+` prefix; global keys deprecated in 1.16) or WireGuard; neither gives PQ key exchange, so put PQ in a mesh layer above it when the threat model needs it.

**Guardrails (Kyverno).** Three policies, run in Audit first: istiod and ztunnel must carry `COMPLIANCE_POLICY=pqc`; Envoy Gateway `ClientTrafficPolicy.spec.tls.ecdhCurves` must start with X25519MLKEM768; the ingress-nginx ConfigMap `ssl-ecdh-curve` must start with X25519MLKEM768. Tested with the Kyverno CLI v1.16.0: 3 compliant resources passed, 3 non-compliant failed. Gatekeeper equivalents were not written. Org-wide controls are in the Enforcement and guardrails tab.

## Packaging per compute type

- **EKS (Istio)**: `helm upgrade istiod istio/istiod -n istio-system -f values-istiod-pqc.yaml`; ambient also `helm upgrade ztunnel istio/ztunnel -n istio-system -f values-ztunnel-pqc.yaml`. Rendering the 1.28.0 charts put `COMPLIANCE_POLICY=pqc` on the istiod container and `tlsDefaults.ecdhCurves` in the `istio` ConfigMap (Tested, `helm template` only). IstioOperator form is in Full configuration files.
- **EKS (Linkerd)**: chart version 2.19+ (or Buoyant Enterprise 2.19+); no values.
- **ECS / Fargate**: Service Connect has no group setting, so for PQ between ECS services today use either app-level TLS (language tabs) or a self-managed Envoy sidecar: Dockerfile plus task definition in Terraform and CloudFormation below (CloudFormation passed cfn-lint; not deployed).
- **EC2 (Consul)**: agent `tls.hcl` in `/etc/consul.d/`, mesh entry with `consul config write mesh.hcl`, then restart the agent and Envoy sidecars.

## Verify

1. **Posture.** Istio: `istioctl version` 1.27+; `kubectl -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].env}' | grep COMPLIANCE_POLICY`. Linkerd: `linkerd version` 2.19+ and `linkerd check --proxy` (all proxies on the new version). Consul: `consul version` 2.1+ and `consul config read -kind mesh -name mesh`.
2. **Envoy counters (Istio, Consul, self-managed).** On fresh connections, `ssl.curves.X25519MLKEM768` must rise and `ssl.curves.X25519` must not. Tested on standalone Envoy 1.36: `listener.0.0.0.0_8443.ssl.curves.X25519MLKEM768: 5` and `cluster.be_pq.ssl.curves.X25519MLKEM768: 1`.
   ```sh
   kubectl exec deploy/orders -c istio-proxy -- pilot-agent request GET 'stats?filter=ssl.curves'
   kubectl exec deploy/orders -c istio-proxy -- pilot-agent request GET config_dump | grep -A3 ecdh_curves
   ```
3. **Linkerd.** 2.19 exports the negotiated TLS key exchange as proxy metrics ([announcement](https://linkerd.io/2025/10/31/announcing-linkerd-2.19/)); check `linkerd diagnostics proxy-metrics -n <ns> deploy/<name>` for the key-exchange label. The exact metric name was not confirmed here.
4. **Gateways, live.** From outside: `openssl s_client -connect gw:443 -tls1_3 -groups X25519MLKEM768` must show `Negotiated TLS1.3 group: X25519MLKEM768`; `-groups X25519` must still connect unless you chose `COMPLIANCE_POLICY=pqc`, which refuses it.
5. **Envoy test results (2026-11-14).** Envoy 1.36.13 and Istio's Envoy 1.36.3 with the Web servers tab config: 12 of 12 checks passed (PQ client, classical fallback, TLS 1.2 refused, PQ-only and classical backends reached). With `ecdh_curves` removed, the PQ-only client was refused and the PQ-only backend gave 503 (expected).

## Pitfalls and rollback

- **`COMPLIANCE_POLICY=pqc` is PQ-only.** It refuses peers without X25519MLKEM768: older Istio in multicluster, classical clients on ingress gateways, and external hosts reached by TLS origination. Turn it on per cluster after every peer is 1.27+; use `tlsDefaults.ecdhCurves` with fallback for internet-facing gateways.
- **`tlsDefaults.ecdhCurves` does not touch mesh mTLS** and applies mesh-wide; there is no per-workload setting (Red Hat OSSM docs).
- **FIPS builds.** Red Hat says PQC is unavailable on OpenShift clusters in FIPS mode. Envoy BoringSSL-FIPS defaults to P-256 only; Consul lists FIPS Envoy builds 1.38.4 and 1.39.1 that accept the hybrid group. Check your FIPS image before turning it on.
- **Envoy upstream maximum TLS defaults to 1.2**: a TLS 1.3 minimum without a maximum fails with `NO_SUPPORTED_VERSIONS_ENABLED` (Tested). Consul notes the same.
- **Existing connections keep their groups** until they close. Restart workloads or wait for connection churn before measuring.
- **Mixed versions** (Linkerd proxies older than 2.19, Envoys without ML-KEM) negotiate classical silently with Linkerd and Consul fallback lists.
- **Apps doing their own TLS** bypass all of this.
- **Rollback.** Istio: remove `COMPLIANCE_POLICY` (and `tlsDefaults.ecdhCurves`), `helm upgrade`, restart istiod, ztunnel and workloads. Consul: set `ECDHCurves = ["X25519"]` and write the mesh entry. Linkerd: no switch to turn PQ off was found; downgrading below 2.19 is the only route (not recommended).

## Full configuration files

`values-istiod-pqc.yaml`, `values-ztunnel-pqc.yaml`, `istio-operator-pqc.yaml`, `egress-tls-origination.yaml` (Istio)
```yaml
# ---- values-istiod-pqc.yaml (helm upgrade istiod istio/istiod -n istio-system -f values-istiod-pqc.yaml) ----
# Rendered with helm template oci://gcr.io/istio-release/charts/istiod --version 1.28.0: env lands on the
# discovery container, tlsDefaults lands in the istio ConfigMap (checked 2026-11-14).
pilot:
  env:
    COMPLIANCE_POLICY: pqc          # Istio 1.27+: TLS 1.3 + X25519MLKEM768 only, for mesh mTLS, gateways and xDS
meshConfig:
  tlsDefaults:
    # Non-mesh TLS (gateway listeners, TLS origination). Used on its own when you want PQ-preferred
    # with classical fallback on gateways instead of the enforcing COMPLIANCE_POLICY.
    ecdhCurves: [X25519MLKEM768, X25519]
---
# ---- values-ztunnel-pqc.yaml (ambient only; helm upgrade ztunnel istio/ztunnel -n istio-system -f ...) ----
env:
  COMPLIANCE_POLICY: pqc
---
# ---- istio-operator-pqc.yaml (istioctl install -f istio-operator-pqc.yaml) ----
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: pqc
  namespace: istio-system
spec:
  profile: default                  # "ambient" for ambient mode
  meshConfig:
    tlsDefaults:
      ecdhCurves: [X25519MLKEM768, X25519]
  values:
    pilot:
      env:
        COMPLIANCE_POLICY: pqc
    ztunnel:                        # ambient profile only
      env:
        COMPLIANCE_POLICY: pqc
---
# ---- egress-tls-origination.yaml: app sends plain HTTP, the egress gateway / sidecar does PQ TLS to the external host ----
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner-api
  namespace: payments
spec:
  hosts: [api.partner.example]
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  resolution: DNS
  location: MESH_EXTERNAL
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: partner-api-tls
  namespace: payments
spec:
  host: api.partner.example
  trafficPolicy:
    portLevelSettings:
    - port: { number: 443 }
      tls:
        mode: SIMPLE                # TLS origination; key-exchange groups from tlsDefaults / COMPLIANCE_POLICY
        sni: api.partner.example
        credentialName: partner-ca  # Secret with ca.crt; or caCertificates: /etc/ssl/certs/ca-certificates.crt
```

`mesh.hcl`, `mesh.yaml`, `/etc/consul.d/tls.hcl`, systemd drop-in (Consul)
```hcl
### mesh.hcl  (consul config write mesh.hcl) - Consul 2.1+
Kind = "mesh"
TLS {
  Incoming {
    TLSMinVersion = "TLSv1_3"
    TLSMaxVersion = "TLSv1_3"
    ECDHCurves    = ["X25519MLKEM768", "X25519"]
  }
  Outgoing {
    TLSMinVersion = "TLSv1_3"
    TLSMaxVersion = "TLSv1_3"   # set it: Envoy's upstream maximum otherwise defaults to TLS 1.2
    ECDHCurves    = ["X25519MLKEM768", "X25519"]
  }
}

### mesh.yaml  (Kubernetes, consul-k8s CRD; confirm with: kubectl explain mesh.spec.tls.incoming)
apiVersion: consul.hashicorp.com/v1alpha1
kind: Mesh
metadata:
  name: mesh
spec:
  tls:
    incoming:
      tlsMinVersion: TLSv1_3
      tlsMaxVersion: TLSv1_3
      ecdhCurves: ["X25519MLKEM768", "X25519"]
    outgoing:
      tlsMinVersion: TLSv1_3
      tlsMaxVersion: TLSv1_3
      ecdhCurves: ["X25519MLKEM768", "X25519"]

### /etc/consul.d/tls.hcl  (agent TLS: internal RPC, HTTPS, gRPC; Helm: server.extraConfig)
tls {
  defaults {
    ca_file         = "/etc/consul.d/certs/consul-agent-ca.pem"
    cert_file       = "/etc/consul.d/certs/server.pem"
    key_file        = "/etc/consul.d/certs/server-key.pem"
    verify_incoming = true
    verify_outgoing = true
    tls_min_version = "TLSv1_3"
    tls_ecdh_curves = "X25519MLKEM768,X25519"
  }
  internal_rpc {
    verify_server_hostname = true
  }
}

### /etc/systemd/system/consul.service.d/override.conf  (EC2)
[Service]
ExecStartPre=/usr/bin/consul validate /etc/consul.d/
```

`Dockerfile` (self-managed Envoy sidecar for ECS; `envoy.yaml` is in the Web servers tab)
```dockerfile
# Dockerfile - pq-envoy sidecar. Envoy 1.36.13 (BoringSSL) accepts X25519MLKEM768 (Tested 2026-11-14).
# The base image (Ubuntu 22.04) has no curl, which the ECS health check needs.
FROM envoyproxy/envoy@sha256:93e25ef06d87a908a1114e8dff9a2b3a3046fbbfda7e644d448d752332633de6
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
# envoy.yaml = the Web servers tab file: listener 8443 terminates PQ TLS from peers,
# listener 8080 takes the app's plain HTTP and originates PQ TLS (ecdh_curves + TLS 1.3 min AND max) to peers.
COPY envoy.yaml /etc/envoy/envoy.yaml
# Certificates: write them to /certs at task start (e.g. an init container reading Secrets Manager);
# never bake private keys into the image.
```

`ecs-envoy-sidecar.tf` (Terraform)
```hcl
# ecs-envoy-sidecar.tf - ECS/Fargate: self-managed Envoy sidecar doing PQ TLS for east-west calls,
# for teams that need PQ between ECS services today (Service Connect has no key-exchange setting).
# The app calls http://127.0.0.1:8080/<svc>/...; Envoy originates TLS with ecdh_curves to the peer task,
# and the peer's Envoy terminates on 8443. Image = envoyproxy/envoy with envoy.yaml baked in (Web servers tab).
variable "app_image" { type = string }
variable "envoy_image" { type = string } # e.g. <acct>.dkr.ecr.<region>.amazonaws.com/pq-envoy@sha256:...
variable "execution_role_arn" { type = string }

resource "aws_ecs_task_definition" "orders" {
  family                   = "orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.execution_role_arn
  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.app_image
      essential    = true
      environment  = [{ name = "PAYMENTS_URL", value = "http://127.0.0.1:8080/payments" }]
      dependsOn    = [{ containerName = "envoy", condition = "HEALTHY" }]
      portMappings = []
    },
    {
      name         = "envoy"
      image        = var.envoy_image
      essential    = true
      command      = ["envoy", "-c", "/etc/envoy/envoy.yaml"]
      portMappings = [{ containerPort = 8443, protocol = "tcp" }]
      healthCheck = {
        command  = ["CMD-SHELL", "curl -sf http://127.0.0.1:9901/ready || exit 1"]
        interval = 10
        retries  = 3
      }
    }
  ])
}
```

`ecs-envoy-sidecar.yaml` (CloudFormation)
```yaml
# ecs-envoy-sidecar.yaml - CloudFormation equivalent of ecs-envoy-sidecar.tf
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  AppImage: { Type: String }
  EnvoyImage: { Type: String }
  ExecutionRoleArn: { Type: String }
Resources:
  OrdersTask:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: "512"
      Memory: "1024"
      ExecutionRoleArn: !Ref ExecutionRoleArn
      ContainerDefinitions:
        - Name: app
          Image: !Ref AppImage
          Essential: true
          Environment:
            - Name: PAYMENTS_URL
              Value: http://127.0.0.1:8080/payments
          DependsOn:
            - ContainerName: envoy
              Condition: HEALTHY
        - Name: envoy
          Image: !Ref EnvoyImage
          Essential: true
          Command: [envoy, -c, /etc/envoy/envoy.yaml]
          PortMappings:
            - ContainerPort: 8443
              Protocol: tcp
          HealthCheck:
            Command: ["CMD-SHELL", "curl -sf http://127.0.0.1:9901/ready || exit 1"]
            Interval: 10
            Retries: 3
```

`kyverno-pq-policies.yaml` (and the test resources in `kyverno-test-resources.yaml` under the work dir)
```yaml
# kyverno-pq-policies.yaml - Audit first (validationFailureAction: Audit), switch to Enforce per cluster.
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-ingress-nginx-ecdh-curve
  annotations:
    policies.kyverno.io/title: ingress-nginx must offer X25519MLKEM768
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: configmap-ssl-ecdh-curve
    match:
      any:
      - resources:
          kinds: [ConfigMap]
          names: ["ingress-nginx-controller"]
    validate:
      message: "ingress-nginx ConfigMap must set ssl-ecdh-curve with X25519MLKEM768 first."
      pattern:
        data:
          ssl-ecdh-curve: "X25519MLKEM768:*"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-envoy-gateway-client-tls
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: clienttrafficpolicy-ecdh
    match:
      any:
      - resources:
          kinds: [gateway.envoyproxy.io/v1alpha1/ClientTrafficPolicy]
    validate:
      message: "ClientTrafficPolicy.spec.tls.ecdhCurves must list X25519MLKEM768 first (Envoy's default is X25519,P-256)."
      deny:
        conditions:
          any:
          - key: "{{ request.object.spec.tls.ecdhCurves[0] || '' }}"
            operator: NotEquals
            value: X25519MLKEM768
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-istiod-compliance-policy
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: istiod-env
    match:
      any:
      - resources:
          kinds: [Deployment]
          namespaces: [istio-system]
          selector:
            matchLabels:
              app: istiod
    validate:
      message: "istiod must run with COMPLIANCE_POLICY=pqc (Istio 1.27+)."
      deny:
        conditions:
          any:
          - key: "{{ request.object.spec.template.spec.containers[?name=='discovery'].env[] | [?name=='COMPLIANCE_POLICY'].value | [0] || '' }}"
            operator: NotEquals
            value: pqc
  - name: ztunnel-env
    match:
      any:
      - resources:
          kinds: [DaemonSet]
          namespaces: [istio-system]
          names: [ztunnel]
    validate:
      message: "ztunnel must run with COMPLIANCE_POLICY=pqc in ambient mode."
      deny:
        conditions:
          any:
          - key: "{{ request.object.spec.template.spec.containers[?name=='istio-proxy'].env[] | [?name=='COMPLIANCE_POLICY'].value | [0] || '' }}"
            operator: NotEquals
            value: pqc
```
