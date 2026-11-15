FROM postgres@sha256:b9f6b8ff03b62f3cfd9d9ba3fe56226a9991c79d3fb46fd46536263bf02be553
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends openssl redis-server mariadb-server >/dev/null && rm -rf /var/lib/apt/lists/*
