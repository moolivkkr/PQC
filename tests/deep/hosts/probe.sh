#!/bin/sh
# Client probes. $1 = profile. Runs inside the client container; server host is "srv".
P=$1
inst() {
  if command -v apt-get >/dev/null 2>&1; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq "$@" >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then apk add -q "$@" >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then dnf install -y -q "$@" >/dev/null 2>&1
  fi
}
curlt() { # curl against PQ-only and classical-only
  for port in 4433 4434; do
    out=$(curl -sk -v -o /dev/null --max-time 8 https://srv:$port/ 2>&1)
    line=$(echo "$out" | grep -iE 'SSL connection using|handshake failure|alert|error' | head -2 | tr '\n' ' ')
    echo "curl port=$port rc=$? :: $line"
  done
}
sslt() { # openssl s_client using the system default groups (no -groups)
  for port in 4433 4434; do
    out=$(echo | openssl s_client -connect srv:$port -servername srv 2>&1)
    g=$(echo "$out" | grep -E 'Negotiated TLS1.3 group|Server Temp Key|handshake failure|alert' | head -1)
    echo "s_client port=$port :: $g"
  done
}
sshtest() {
  for port in 22 2222; do
    out=$(ssh -v -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p $port nobody@srv true 2>&1)
    k=$(echo "$out" | grep -E 'kex: algorithm|no matching key exchange|Unable to negotiate' | head -1)
    echo "ssh port=$port :: $k"
  done
}
wgett() {
  for port in 4433 4434; do
    out=$(wget -O /dev/null --no-check-certificate -T 8 -t 1 https://srv:$port/ 2>&1); rc=$?
    echo "wget port=$port rc=$rc :: $(echo "$out" | grep -iE 'error|fail|200|saved|unable' | head -2 | tr '\n' ' ')"
  done
}
case $P in
  al2023)
    inst crypto-policies-scripts openssl openssh-clients
    rpm -q system-release openssl-libs crypto-policies openssh-clients curl-minimal gnutls nss 2>/dev/null
    echo "policy: $(update-crypto-policies --show)"
    echo "--- modules:"; ls /usr/share/crypto-policies/policies/modules/
    echo "--- PQ.pmod:"; cat /usr/share/crypto-policies/policies/modules/PQ.pmod 2>/dev/null
    echo "=== DEFAULT"; sslt; curlt; sshtest
    grep -i groups /etc/crypto-policies/back-ends/opensslcnf.config
    update-crypto-policies --set DEFAULT:PQ 2>&1 | tail -1
    echo "=== DEFAULT:PQ policy: $(update-crypto-policies --show)"; sslt; curlt; sshtest
    grep -i groups /etc/crypto-policies/back-ends/opensslcnf.config
    grep -i kex /etc/crypto-policies/back-ends/openssh.config
    grep -iE 'curve|group' /etc/crypto-policies/back-ends/gnutls.config | head -5
    echo "=== custom subpolicy PQ-HYBRID (X25519MLKEM768 first, nothing else changed)"
    cp /t/PQ-HYBRID.pmod /etc/crypto-policies/policies/modules/PQ-HYBRID.pmod
    update-crypto-policies --set DEFAULT:PQ-HYBRID 2>&1 | tail -1
    echo "policy: $(update-crypto-policies --show)"; sslt; curlt
    grep -i groups /etc/crypto-policies/back-ends/opensslcnf.config
    echo "=== rollback to DEFAULT"; update-crypto-policies --set DEFAULT 2>&1 | tail -1
    echo "policy: $(update-crypto-policies --show)"; sslt
    echo "=== OPENSSL_CONF per-process (policy DEFAULT)"
    cp /t/openssl-pq.cnf /tmp/openssl-pq.cnf
    OPENSSL_CONF=/tmp/openssl-pq.cnf curlt
    ;;
  ssh-curl-wget)
    inst openssh-client curl wget openssl ca-certificates 2>/dev/null || true
    inst openssh-client curl wget openssl ca-certificates openssh 2>/dev/null || true
    cat /etc/os-release | grep PRETTY; ssh -V 2>&1; curl -V | head -1; openssl version; wget --version 2>&1 | head -1
    sslt; curlt; sshtest; wgett
    ;;
  busybox-wget)
    busybox | head -1; wgett
    ;;
  curlimage)
    curl -V | head -2; curlt
    ;;
  git)
    inst git ca-certificates
    git --version
    (ldd $(git --exec-path)/git-remote-https 2>/dev/null || true) | grep -E 'curl|gnutls|ssl' | head -3
    for port in 4433 4434; do
      out=$(GIT_SSL_NO_VERIFY=1 git ls-remote https://srv:$port/r.git 2>&1 | head -2 | tr '\n' ' ')
      echo "git port=$port :: $out"
    done
    ;;
  awscli2)
    aws --version
    for port in 4433 4434; do
      out=$(AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=x AWS_EC2_METADATA_DISABLED=true aws s3 ls --endpoint-url https://srv:$port --no-verify-ssl --region us-east-1 --cli-connect-timeout 5 --cli-read-timeout 5 2>&1 | grep -v InsecureRequestWarning | tail -2 | tr '\n' ' ')
      echo "aws port=$port :: $out"
    done
    ;;
  awscli1)
    pip install -q awscli 2>&1 | tail -1
    aws --version 2>&1
    python -c 'import ssl;print(ssl.OPENSSL_VERSION)'
    for port in 4433 4434; do
      out=$(AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=x AWS_EC2_METADATA_DISABLED=true aws s3 ls --endpoint-url https://srv:$port --no-verify-ssl --region us-east-1 --cli-connect-timeout 5 --cli-read-timeout 5 2>&1 | grep -v InsecureRequestWarning | tail -2 | tr '\n' ' ')
      echo "aws1 port=$port :: $out"
    done
    ;;
  kubectl)
    kubectl version --client 2>&1 | head -2
    for port in 4433 4434; do
      out=$(kubectl --server=https://srv:$port --insecure-skip-tls-verify=true --request-timeout=5s get --raw / 2>&1 | head -2 | cut -c1-200 | tr '\n' ' ')
      echo "kubectl port=$port :: $out"
    done
    ;;
  helm)
    helm version 2>&1 | head -1
    for port in 4433 4434; do
      out=$(helm pull https://srv:$port/c-0.1.0.tgz --insecure-skip-tls-verify 2>&1 | head -2 | cut -c1-200 | tr '\n' ' ')
      echo "helm port=$port :: $out"
    done
    ;;
esac
