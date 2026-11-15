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
