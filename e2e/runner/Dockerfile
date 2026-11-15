FROM public.ecr.aws/docker/library/python:3.13-slim
RUN pip install --no-cache-dir boto3==1.40.70 && apt-get update -qq && apt-get install -y -qq zip >/dev/null && rm -rf /var/lib/apt/lists/*
WORKDIR /e2e
ENV AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
    AWS_ENDPOINT_URL=http://10.250.0.10:4566 PQC_OBSERVER_ADMIN=http://10.250.0.20:8080 PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "-I", "-m", "runner"]
