#!/bin/sh
# Round 2 probes. $1 = profile.
case $1 in
  awscli)
    aws --version 2>&1
    for port in 4433 4434; do
      out=$(AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=x AWS_EC2_METADATA_DISABLED=true aws s3 ls --endpoint-url https://srv:$port --no-verify-ssl --region us-east-1 --cli-connect-timeout 5 --cli-read-timeout 5 2>&1 | grep -vi 'warn' | tail -3 | cut -c1-220 | tr '\n' ' ')
      echo "aws port=$port :: $out"
    done
    ;;
  awscli1)
    pip install -q awscli >/dev/null 2>&1
    aws --version 2>&1; python -c 'import ssl;print(ssl.OPENSSL_VERSION)'
    for port in 4433 4434; do
      out=$(AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=x AWS_EC2_METADATA_DISABLED=true aws s3 ls --endpoint-url https://srv:$port --no-verify-ssl --region us-east-1 --cli-connect-timeout 5 --cli-read-timeout 5 2>&1 | grep -vi 'warn' | tail -3 | cut -c1-220 | tr '\n' ' ')
      echo "aws1 port=$port :: $out"
    done
    ;;
  kubectl)
    for port in 4433 4434; do
      out=$(kubectl --server=https://srv:$port --token=x --insecure-skip-tls-verify=true --request-timeout=5s get --raw / 2>&1 | head -3 | cut -c1-200 | tr '\n' ' ')
      echo "kubectl port=$port :: $out"
    done
    ;;
  helm)
    for port in 4433 4434; do
      out=$(helm pull https://srv:$port/c-0.1.0.tgz --insecure-skip-tls-verify 2>&1; echo "rc=$?")
      echo "helm port=$port :: $(echo "$out" | head -3 | cut -c1-200 | tr '\n' ' ')"
    done
    ;;
  gnutls)
    export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq gnutls-bin >/dev/null 2>&1
    gnutls-cli --version | head -1
    echo "groups with MLKEM: $(gnutls-cli --list 2>/dev/null | grep -i -o '[A-Z0-9-]*MLKEM[A-Z0-9-]*' | sort -u | tr '\n' ' ')"
    for pri in NORMAL NORMAL:-GROUP-ALL:+GROUP-X25519-MLKEM768:+GROUP-X25519; do
      out=$(echo | gnutls-cli --insecure --priority "$pri" -p 4433 srv 2>&1 | grep -iE 'Description|Handshake was completed|fatal|error|unknown' | head -2 | tr '\n' ' ')
      echo "gnutls-cli pri=$pri port=4433 :: $out"
    done
    ;;
  al2023-wget-sshd)
    dnf install -y -q crypto-policies-scripts wget openssh-server openssh-clients gnutls-utils >/dev/null 2>&1
    rpm -q wget gnutls openssh-server
    update-crypto-policies --set DEFAULT:PQ >/dev/null 2>&1; echo "policy $(update-crypto-policies --show)"
    for port in 4433 4434; do
      out=$(wget -O /dev/null --no-check-certificate -T 8 -t 1 https://srv:$port/ 2>&1); rc=$?
      echo "wget port=$port rc=$rc :: $(echo "$out" | grep -iE 'error|fail|200|unable' | head -1)"
    done
    out=$(echo | gnutls-cli --insecure -p 4433 srv 2>&1 | grep -iE 'Description|Handshake was completed|fatal' | head -2 | tr '\n' ' ')
    echo "gnutls-cli DEFAULT:PQ port=4433 :: $out"
    ssh-keygen -A >/dev/null 2>&1
    /usr/sbin/sshd -T 2>/dev/null | grep -i '^kexalgorithms'
    ;;
esac
