FROM amazon/aws-cli:2.40.3 AS cli
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
COPY --from=cli /usr/local/aws-cli /usr/local/aws-cli
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
 && aws --version | awk '{split($1,v,"/"); split(v[2],n,"."); if (n[1]<2 || (n[1]==2 && (n[2]<34 || (n[2]==34 && n[3]<54)))) {print "AWS CLI too old for PQ"; exit 1}}'
