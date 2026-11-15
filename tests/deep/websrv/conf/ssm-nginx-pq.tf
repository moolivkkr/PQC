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
