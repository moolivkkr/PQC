# Legacy AMI: Amazon Linux 2 (end of life 2026-06-30), OpenSSL 1.0.2 system library.
FROM public.ecr.aws/amazonlinux/amazonlinux:2
COPY ec2/al2/packages.d/ /tmp/packages.d/
RUN yum -y -q install openssh-server openssh-clients $(cat /tmp/packages.d/*.txt | grep -v '^#') && yum clean all && rm -rf /var/cache/yum
COPY .work/certs/ca.crt .work/certs/client.crt .work/certs/client.key .work/certs/client.p12 .work/certs/truststore.p12 /etc/pqc/certs/
COPY .work/artifacts/ec2/ /opt/pqc/
COPY ec2/al2/setup.d/ /tmp/setup.d/
RUN for s in /tmp/setup.d/*.sh; do [ -f "$s" ] && bash -eux "$s"; done; chmod -R a+rX /opt/pqc /etc/pqc
RUN cat /etc/system-release > /etc/pqc/ami-release
CMD ["/bin/bash"]
