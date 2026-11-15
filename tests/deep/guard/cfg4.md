### Kubernetes

`rules/k8s/kyverno-pq-tls-cel.yaml`

```yaml
# Kyverno 1.20+ (CEL ValidatingPolicy). Kyverno 1.20 no longer executes kyverno.io/v1 ClusterPolicy.
# Start with validationActions [Audit]; switch to [Deny] after the warn window.
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-alb-ingress
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ networking.k8s.io ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ ingresses ]
  variables:
    - name: ann
      expression: "has(object.metadata.annotations) ? object.metadata.annotations : {}"
    - name: pq
      expression: >-
        ['ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09','ELBSecurityPolicy-TLS13-1-3-PQ-2025-09',
        'ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09']
  matchConditions:
    - name: alb-class
      expression: >-
        (has(object.spec.ingressClassName) && object.spec.ingressClassName == 'alb') ||
        (has(object.metadata.annotations) && object.metadata.annotations[?'kubernetes.io/ingress.class'].orValue('') == 'alb')
    - name: tls-and-no-exception
      expression: >-
        has(object.metadata.annotations) &&
        'alb.ingress.kubernetes.io/certificate-arn' in object.metadata.annotations &&
        !('pq-tls.example.com/exception' in object.metadata.annotations)
  validations:
    - expression: "variables.ann[?'alb.ingress.kubernetes.io/ssl-policy'].orValue('') in variables.pq"
      message: "PQ-K1: set alb.ingress.kubernetes.io/ssl-policy to a -PQ-2025-09 policy (default ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09)"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-nlb-service
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ services ]
  matchConditions:
    - name: tls-lb
      expression: >-
        object.spec.type == 'LoadBalancer' && has(object.metadata.annotations) &&
        'service.beta.kubernetes.io/aws-load-balancer-ssl-cert' in object.metadata.annotations &&
        !('pq-tls.example.com/exception' in object.metadata.annotations)
  validations:
    - expression: >-
        object.metadata.annotations[?'service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy'].orValue('')
        .matches('^ELBSecurityPolicy-TLS13-1-[23]-.*PQ-2025-09$')
      message: "PQ-K2: set service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy to a -PQ-2025-09 policy"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-ingress-nginx-curves
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ configmaps ]
  matchConditions:
    - name: controller-cm
      expression: "object.metadata.name == 'ingress-nginx-controller'"
  validations:
    - expression: "has(object.data) && object.data[?'ssl-ecdh-curve'].orValue('').startsWith('X25519MLKEM768')"
      message: "PQ-K3: set data.ssl-ecdh-curve to X25519MLKEM768:X25519:prime256v1"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-istiod
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ apps ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ deployments ]
  matchConditions:
    - name: istiod
      expression: "object.metadata.namespace == 'istio-system' && object.metadata.name.startsWith('istiod')"
  validations:
    - expression: >-
        object.spec.template.spec.containers.exists(c, c.name == 'discovery' && has(c.env) &&
        c.env.exists(e, e.name == 'COMPLIANCE_POLICY' && has(e.value) && e.value == 'pqc'))
      message: "PQ-K4: istiod container needs env COMPLIANCE_POLICY=pqc"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: pq-tls-workload-env
spec:
  validationActions: [ Audit ]
  matchConstraints:
    resourceRules:
      - apiGroups: [ "" ]
        apiVersions: [ v1 ]
        operations: [ CREATE, UPDATE ]
        resources: [ pods ]
  variables:
    - name: envs
      expression: >-
        object.spec.containers.filter(c, has(c.env)).map(c, c.env).flatten()
  validations:
    - expression: "!variables.envs.exists(e, e.name == 'GODEBUG' && has(e.value) && e.value.contains('tlsmlkem=0'))"
      message: "PQ-K6: GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
    - expression: "!variables.envs.exists(e, e.name == 'OPENSSL_CONF' && has(e.value) && e.value == '/dev/null')"
      message: "PQ-K7: OPENSSL_CONF=/dev/null drops the PQ group configuration"
```

`rules/k8s/kyverno-pq-tls.yaml`

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-aws-load-balancers
  annotations:
    policies.kyverno.io/title: PQ TLS policy on AWS Load Balancer Controller Ingress and Service
    policies.kyverno.io/category: PQ TLS
    policies.kyverno.io/description: >-
      ALB Ingresses and NLB Services that terminate TLS must name a -PQ-2025-09 ELB security policy.
      Without the annotation the controller uses ELBSecurityPolicy-2016-08 (no PQ).
spec:
  background: true
  rules:
    - name: alb-ingress-ssl-policy
      match:
        any:
          - resources:
              kinds: [ Ingress ]
      preconditions:
        all:
          - key: "{{ request.object.spec.ingressClassName || request.object.metadata.annotations.\"kubernetes.io/ingress.class\" || '' }}"
            operator: Equals
            value: alb
          - key: "{{ request.object.metadata.annotations.\"alb.ingress.kubernetes.io/certificate-arn\" || request.object.metadata.annotations.\"alb.ingress.kubernetes.io/listen-ports\" || '' }}"
            operator: NotEquals
            value: ""
          - key: "{{ request.object.metadata.annotations.\"pq-tls.example.com/exception\" || '' }}"
            operator: Equals
            value: ""
      validate:
        failureAction: Audit
        message: >-
          PQ-K1: set alb.ingress.kubernetes.io/ssl-policy to a -PQ-2025-09 policy
          (default choice ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09).
        deny:
          conditions:
            all:
              - key: "{{ request.object.metadata.annotations.\"alb.ingress.kubernetes.io/ssl-policy\" || '' }}"
                operator: AnyNotIn
                value:
                  - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
    - name: nlb-service-ssl-negotiation-policy
      match:
        any:
          - resources:
              kinds: [ Service ]
      preconditions:
        all:
          - key: "{{ request.object.spec.type || '' }}"
            operator: Equals
            value: LoadBalancer
          - key: "{{ request.object.metadata.annotations.\"service.beta.kubernetes.io/aws-load-balancer-ssl-cert\" || '' }}"
            operator: NotEquals
            value: ""
          - key: "{{ request.object.metadata.annotations.\"pq-tls.example.com/exception\" || '' }}"
            operator: Equals
            value: ""
      validate:
        failureAction: Audit
        message: >-
          PQ-K2: set service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy to a -PQ-2025-09 policy.
        deny:
          conditions:
            all:
              - key: "{{ request.object.metadata.annotations.\"service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy\" || '' }}"
                operator: AnyNotIn
                value:
                  - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
                  - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-ingress-nginx-curves
  annotations:
    policies.kyverno.io/title: ingress-nginx offers X25519MLKEM768
    policies.kyverno.io/description: >-
      The ingress-nginx controller ConfigMap must list X25519MLKEM768 first in ssl-ecdh-curve.
      Only effective when the controller image links OpenSSL 3.5+.
spec:
  background: true
  rules:
    - name: ssl-ecdh-curve-has-mlkem
      match:
        any:
          - resources:
              kinds: [ ConfigMap ]
              names: [ ingress-nginx-controller ]
      validate:
        failureAction: Audit
        message: "PQ-K3: set data.ssl-ecdh-curve to X25519MLKEM768:X25519:prime256v1"
        pattern:
          data:
            ssl-ecdh-curve: "X25519MLKEM768*"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-istio-compliance-policy
  annotations:
    policies.kyverno.io/title: Istio control plane runs with COMPLIANCE_POLICY=pqc
    policies.kyverno.io/description: >-
      Istio 1.27+: COMPLIANCE_POLICY=pqc on istiod restricts mesh mTLS to TLS 1.3 with X25519MLKEM768.
      Set the same value for proxies (meshConfig.defaultConfig.proxyMetadata) and ztunnel in ambient mode.
spec:
  background: true
  rules:
    - name: istiod-env
      match:
        any:
          - resources:
              kinds: [ Deployment ]
              namespaces: [ istio-system ]
              selector:
                matchLabels:
                  app: istiod
      validate:
        failureAction: Audit
        message: "PQ-K4: istiod container needs env COMPLIANCE_POLICY=pqc"
        deny:
          conditions:
            all:
              - key: pqc
                operator: AnyNotIn
                value: "{{ request.object.spec.template.spec.containers[?name=='discovery'].env[] | [?name=='COMPLIANCE_POLICY'].value || `[]` }}"
    - name: ztunnel-env
      match:
        any:
          - resources:
              kinds: [ DaemonSet ]
              namespaces: [ istio-system ]
              names: [ ztunnel ]
      validate:
        failureAction: Audit
        message: "PQ-K5: ztunnel needs env COMPLIANCE_POLICY=pqc"
        deny:
          conditions:
            all:
              - key: pqc
                operator: AnyNotIn
                value: "{{ request.object.spec.template.spec.containers[].env[] | [?name=='COMPLIANCE_POLICY'].value || `[]` }}"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: pq-tls-workload-env
  annotations:
    policies.kyverno.io/title: Workloads do not switch PQ off
    policies.kyverno.io/description: >-
      Blocks GODEBUG tlsmlkem=0, OPENSSL_CONF=/dev/null and jdk.tls.namedGroups without X25519MLKEM768 in Pod specs.
spec:
  background: true
  rules:
    - name: no-godebug-tlsmlkem-off
      match:
        any:
          - resources:
              kinds: [ Pod ]
      validate:
        failureAction: Audit
        message: "PQ-K6: GODEBUG tlsmlkem=0 disables X25519MLKEM768 in Go"
        foreach:
          - list: "request.object.spec.[containers, initContainers][][].env[?name=='GODEBUG'][]"
            deny:
              conditions:
                any:
                  - key: "{{ element.value || '' }}"
                    operator: Equals
                    value: "*tlsmlkem=0*"
    - name: no-openssl-conf-devnull
      match:
        any:
          - resources:
              kinds: [ Pod ]
      validate:
        failureAction: Audit
        message: "PQ-K7: OPENSSL_CONF=/dev/null drops the PQ group configuration"
        foreach:
          - list: "request.object.spec.[containers, initContainers][][].env[?name=='OPENSSL_CONF'][]"
            deny:
              conditions:
                any:
                  - key: "{{ element.value || '' }}"
                    operator: Equals
                    value: /dev/null
```

`rules/k8s/gatekeeper-pq-tls.yaml`

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8spqtlselbpolicy
spec:
  crd:
    spec:
      names:
        kind: K8sPqTlsElbPolicy
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedPolicies:
              type: array
              items: { type: string }
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8spqtlselbpolicy

        ann := object.get(input.review.object.metadata, "annotations", {})

        exempt { ann["pq-tls.example.com/exception"] }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Ingress"
          object.get(input.review.object.spec, "ingressClassName", "") == "alb"
          ann["alb.ingress.kubernetes.io/certificate-arn"]
          not exempt
          p := object.get(ann, "alb.ingress.kubernetes.io/ssl-policy", "")
          not allowed(p)
          msg := sprintf("PQ-K1: alb.ingress.kubernetes.io/ssl-policy %q is not a -PQ-2025-09 policy", [p])
        }

        violation[{"msg": msg}] {
          input.review.kind.kind == "Service"
          input.review.object.spec.type == "LoadBalancer"
          ann["service.beta.kubernetes.io/aws-load-balancer-ssl-cert"]
          not exempt
          p := object.get(ann, "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy", "")
          not allowed(p)
          msg := sprintf("PQ-K2: aws-load-balancer-ssl-negotiation-policy %q is not a -PQ-2025-09 policy", [p])
        }

        allowed(p) { p == input.parameters.allowedPolicies[_] }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPqTlsElbPolicy
metadata:
  name: pq-tls-elb-policy
spec:
  enforcementAction: warn
  match:
    kinds:
      - apiGroups: [ networking.k8s.io ]
        kinds: [ Ingress ]
      - apiGroups: [ "" ]
        kinds: [ Service ]
  parameters:
    allowedPolicies:
      - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext0-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext1-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext1-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext2-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
      - ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09
```

