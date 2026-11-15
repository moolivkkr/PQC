# Golden AMI for LocalStack EC2 (docker VM manager): the AL2023 release that matches
# AMI al2023-ami-2023.12.20261109.0, plus every language runtime from the AL2023 repos.
# Context: e2e/.  Languages add packages.d/<lang>.txt, setup.d/<lang>.sh and .work/artifacts/ec2/<lang>/.
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.12.20261109.0
COPY ec2/al2023/packages.d/ /tmp/packages.d/
RUN dnf -y -q install openssh-server openssh-clients crypto-policies-scripts $(cat /tmp/packages.d/*.txt | grep -v '^#') \
 && dnf clean all && rm -rf /var/cache/dnf
COPY .work/certs/ca.crt .work/certs/client.crt .work/certs/client.key .work/certs/client.p12 .work/certs/truststore.p12 /etc/pqc/certs/
COPY .work/artifacts/ec2/ /opt/pqc/
COPY ec2/al2023/setup.d/ /tmp/setup.d/
RUN for s in /tmp/setup.d/*.sh; do [ -f "$s" ] && bash -euxo pipefail "$s"; done; chmod -R a+rX /opt/pqc /etc/pqc
RUN cat /etc/system-release > /etc/pqc/ami-release
CMD ["/bin/bash"]
