# Databases and data services

(as of 2026-11-14; tests run 2026-11-14 on arm64 Docker, scripts and output in deep/data/)

## What decides PQ here
Two TLS stacks meet on every database connection. The server engine (its version, its group setting and the TLS library it links) decides which groups it accepts. The client driver's TLS stack decides which groups it offers. Hybrid X25519MLKEM768 needs both sides to support it, TLS 1.3, and no setting on either side that pins a classical list. On managed services AWS owns the server stack, so you change a parameter group or engine version; for self-managed engines you pick the image and set the group option or an OpenSSL config.

## Status matrix

### Managed AWS data services
| Service | PQ (server side) | Minimum / setting | Evidence |
|---|---|---|---|
| RDS for PostgreSQL | Yes, opt-in | Engine 18+; `ssl_groups` in the DB parameter group (default `prime256v1:X25519` has no ML-KEM). Allow-list: `X25519MLKEM768`, `SecP256r1MLKEM768`, `X25519`, `prime256v1`, `secp384r1`. Dynamic, no reboot. TLS library is AWS-LC. | Documented ([RDS PostgreSQL SSL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)) |
| Aurora PostgreSQL | Yes, opt-in | 18.x; `ssl_groups` in the **cluster** parameter group (family `aurora-postgresql18`). API rejects colon lists; use commas. | Claimed ([Classmethod, 2026-10-31](https://dev.classmethod.jp/articles/aurora-postgresql-pq-tls-terraform/)); handshake not tested by the author |
| RDS for MySQL | Yes | 8.4.11+. Mechanism and parameter not documented; RDS MySQL 8.4 links AWS-LC, so upstream `tls_kex` may not apply. | Documented (AWS What's New); parameter: not confirmed ([analysis](https://ecorpit.com/rds-mysql-8-4-11-post-quantum-tls-claim-release-notes-conflict-2026/), Claimed) |
| Aurora MySQL | Yes, on by default | Two engine lines: 8.4.8+ (MySQL 8.4-compatible, GA 2026-09-03) and 3.14.0+ (MySQL 8.0.46-compatible, 2026-10-26); groups X25519MLKEM768, SecP256r1MLKEM768; status variable `Aurora_ssl_named_group` | Documented ([3.14.0 notes](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraMySQLReleaseNotes/AuroraMySQL.Updates.3140.html), [8.4.8 notes](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraMySQLReleaseNotes/AuroraMySQL.Updates.848.html)) |
| RDS for MariaDB | Yes, opt-in | 12.3.3, 11.4.13, 11.8.9 per What's New; parameter name not confirmed here | Documented (versions) |
| RDS for Oracle, RDS for SQL Server | No statement found | – | Unverified |
| RDS Proxy | No (client-to-proxy leg classical) | – | Claimed |
| DynamoDB | Endpoint PQ (non-FIPS); FIPS endpoints and DAX not yet | Client side only | Documented |
| ElastiCache / MemoryDB (Valkey, Redis OSS) | Data plane not documented; control-plane API only | – | Unverified |
| MSK (Kafka) | TLS 1.3 policies announced 2026-10-30; ML-KEM not documented | – | Claimed |
| Amazon MQ, OpenSearch, DocumentDB, Neptune, Redshift, Keyspaces, Timestream | No PQ statement found in service docs (searched 2026-11-14) | – | Unverified |

### Self-managed engines (EC2, ECS/Fargate, EKS) — tested 2026-11-14
| Engine / image | TLS library | Default result | With setting | Evidence |
|---|---|---|---|---|
| PostgreSQL 18 (`postgres:18`, Debian 13) | OpenSSL 3.5.7 | Classical: default `ssl_groups = X25519:prime256v1`; PQ-only client gets `handshake failure` | `ssl_groups = 'X25519MLKEM768:X25519:prime256v1'` → `Negotiated TLS1.3 group: X25519MLKEM768`; X25519-only client still connects | Tested |
| PostgreSQL 17 and older | any | No: `ssl_ecdh_curve` takes one curve | Upgrade to 18 (some RHEL builds carry a patch) | Documented (PG 18 notes); patch Claimed |
| MySQL 8.4.13 and 9.7.4 (`mysql:8.4`, `mysql:9`, Oracle Linux 9.8) | OpenSSL 3.5.8 | No: server picks P-256 even when the client offers X25519MLKEM768 and X25519; no `tls_kex` variable | None available | Tested |
| MySQL 26.10 (`mysql:26`) | OpenSSL 3.5.8 | Yes: `Tls_key_exchange_algorithm = X25519MLKEM768`; classical clients still connect | `force_pqc=ON` rejects classical clients | Tested |
| MariaDB 11.8.9 and 12 (`mariadb:11.8`, `mariadb:12`, Ubuntu 24.04) | OpenSSL 3.0.13 | No | None (library too old) | Tested (11.8.9) |
| MariaDB 13.0.2 (`mariadb:latest`, Ubuntu 26.04) | OpenSSL 3.5.5 | Yes: X25519MLKEM768; X25519 client still connects | `OPENSSL_CONF` to change order | Tested |
| Valkey 8.1.11 (`valkey/valkey:8` Debian 13 and `:8-alpine` Alpine 3.24) | OpenSSL 3.5.x | Yes: X25519MLKEM768; X25519 client still connects | `OPENSSL_CONF` (no Valkey option for groups) | Tested |
| Redis OSS 7.x/8.x | system OpenSSL | Same as Valkey when built on OpenSSL 3.5 | `OPENSSL_CONF` | Unverified |
| Kafka, Cassandra (JVM) | JSSE | Follows the JDK: Temurin/Corretto 25.0.5 PQ; 21 not | JDK 25, or Bouncy Castle agent on 8–21 (see Java tab) | Unverified for Kafka/Cassandra (JDK behaviour Tested in Java tab) |
| MongoDB 7/8 | system OpenSSL | PQ only if `mongod` links OpenSSL 3.5 | Check `mongod --version` OpenSSL line | Unverified |

## Client side (app level)
The driver's TLS stack decides what the client offers. Follow the language tabs for runtime rules (Go, Python, Node.js, Java, .NET). Database-specific points:

| Client / driver | TLS stack | PQ when | Setting to require TLS | Evidence |
|---|---|---|---|---|
| `psql` / libpq (PostgreSQL 18 client, Debian 13) | System OpenSSL 3.5 | By default: connected to a PQ-only server | `sslmode=verify-full` (+ `sslrootcert`); `ssl_min_protocol_version=TLSv1.3` to force 1.3 | Tested |
| libpq on Debian 12 (OpenSSL 3.0) | OpenSSL 3.0 | Never: fails against PQ-only (`sslv3 alert handshake failure`), falls back to X25519 against PQ-first | Upgrade the base image | Tested |
| psycopg 3 / psycopg2 (libpq) | libpq's OpenSSL; `-binary` wheels bundle their own libpq + OpenSSL | System libpq on OpenSSL 3.5; wheel: check `psycopg.pq.version()` and the bundled OpenSSL | `sslmode=verify-full` | Unverified for wheels |
| asyncpg, PyMySQL, mysql-connector-python (pure), redis-py | Python `ssl` | Python linked to OpenSSL 3.5 (see Python tab) | driver `ssl=` context | Follows Python tab |
| node-postgres `pg`, `mysql2`, `ioredis`, `node-redis` | Node `tls` | Node 22.20+/24.9+ (see Node.js tab) | `ssl: { rejectUnauthorized: true, ca }` | Follows Node tab |
| JDBC (pgjdbc, Connector/J, MariaDB), Lettuce, Jedis, Kafka Java client | JSSE | JDK 25.0.5+, or 8–21 with Bouncy Castle agent (see Java tab) | `sslmode=verify-full` / `sslMode=VERIFY_IDENTITY` | Follows Java tab |
| pgx, `go-sql-driver/mysql`, go-redis, franz-go, sarama | Go `crypto/tls` | Go 1.24+ and `go.mod` ≥ 1.24; no explicit `CurvePreferences` (see Go tab) | `sslmode=verify-full` / `tls=custom` | Follows Go tab |
| Npgsql, MySqlConnector, StackExchange.Redis | .NET `SslStream` → OS OpenSSL on Linux | OS OpenSSL 3.5 with ML-KEM allowed (see .NET tab) | `SSL Mode=VerifyFull` | Follows .NET tab |
| `mysql` CLI 26.10 | OpenSSL 3.5.8 | By default; `--tls-kex`, `--force-pqc` | `--ssl-mode=VERIFY_IDENTITY` | Tested |
| `mysql` CLI 8.4/9.7 | OpenSSL 3.5.8 | Offers PQ as a client (server side is the limit) | `--ssl-mode=VERIFY_IDENTITY` | Unverified (client offer not traced) |
| `valkey-cli` 8.1 (Debian 13) | OpenSSL 3.5.7 | By default: ClientHello lists X25519MLKEM768 first; PQ-only server negotiates it | `--tls --cacert` | Tested |
| librdkafka (confluent-kafka wheels) | Bundled OpenSSL | Depends on bundled OpenSSL version | `security.protocol=SSL` | Unverified |

## Server side

### RDS for PostgreSQL 18 (instance) and Aurora PostgreSQL 18 (cluster)
- Parameter group family `postgres18` (RDS) or `aurora-postgresql18` (Aurora, cluster parameter group).
- `ssl_groups`: hybrid first, classical after for fallback: `X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1`. Use commas in the API, Terraform and CloudFormation (Claimed: colon lists are rejected by the RDS API).
- `rds.force_ssl = 1` (default on 15+).
- To enforce PQ: `ssl_groups = X25519MLKEM768,SecP256r1MLKEM768` and `ssl_min_protocol_version = TLSv1.3` (ML-KEM needs TLS 1.3). Documented.
- Excerpt (CLI):
```bash
aws rds modify-db-parameter-group --db-parameter-group-name pg18-pq \
  --parameters "ParameterName=ssl_groups,ParameterValue='X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1',ApplyMethod=immediate"
```
Full Terraform and CloudFormation are in Full configuration files.

### RDS / Aurora MySQL and RDS MariaDB
- Aurora MySQL 3.14.0: upgrade; no parameter. Check `SHOW STATUS LIKE 'Aurora_ssl_named_group'`. Keep `require_secure_transport = ON` and `tls_version = TLSv1.2,TLSv1.3` (TLS 1.2 clients fall back to classical).
- RDS for MySQL 8.4.11 / RDS for MariaDB (12.3.3, 11.4.13, 11.8.9): upgrade the minor version. The enabling parameter is not confirmed here; check the engine's parameter group for a groups or PQ parameter after upgrade and record what you find.

### Self-managed PostgreSQL 18
```ini
# postgresql.conf (excerpt)
ssl = on
ssl_groups = 'X25519MLKEM768:X25519:prime256v1'   # PG 18 name; ssl_ecdh_curve is an alias
ssl_min_protocol_version = 'TLSv1.2'               # 'TLSv1.3' to enforce PQ
```
`hostssl` lines in `pg_hba.conf` reject non-TLS clients. Reload (`SELECT pg_reload_conf();`) applies TLS settings to new connections.

### Self-managed MySQL
- 8.4 LTS and 9.x: no PQ path on the server (Tested). Plan for MySQL 26.x, or front with something else only if you accept a classical database leg.
- 26.x: PQ on by default. Options (Documented, [MySQL 26.10 manual](https://dev.mysql.com/doc/refman/26.10/en/post-quantum-crytpography-ssl.html)): `tls_kex` (colon list, case-sensitive names), `force_pqc`, `use_pqc_sign`, plus `admin_`, `replication_`, `group_replication_`, `mysqlx_` variants.
```ini
# my.cnf (excerpt)
[mysqld]
require_secure_transport = ON
tls_version = TLSv1.2,TLSv1.3
tls_kex = X25519MLKEM768:secp256r1MLKEM768:X25519:secp256r1
# force_pqc = ON          # enforcement: classical clients fail (Tested)
```

### Self-managed MariaDB, Valkey / Redis OSS
No group option of their own (none found). They follow OpenSSL's defaults: on OpenSSL 3.5 that is X25519MLKEM768 first. To change the order or enforce PQ-only, set `OPENSSL_CONF` to a file with `Groups = ...` (Tested on Valkey 8.1.11: PQ-only file rejected an X25519-only client).
```conf
# valkey.conf (excerpt)
port 0
tls-port 6379
tls-cert-file /etc/valkey/tls/server.crt
tls-key-file  /etc/valkey/tls/server.key
tls-ca-cert-file /etc/valkey/tls/ca.crt
tls-protocols "TLSv1.2 TLSv1.3"
```

### Kafka and Cassandra (JVM)
The broker's JDK decides. Run JDK 25.0.5+ (PQ by default) or attach the Bouncy Castle JSSE agent from the Java tab. Kafka: `ssl.enabled.protocols=TLSv1.3,TLSv1.2`; to pin groups use the JVM property `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1` in `KAFKA_OPTS`. Unverified on a broker (not tested here).

## Packaging per compute type
Database servers do not run on Lambda. Clients do: follow the language tab for each runtime (Lambda zip, image, Fargate, EC2).

| Where the engine runs | What to ship | Evidence |
|---|---|---|
| ECS/Fargate or EKS | Image with OpenSSL 3.5: `postgres:18` (Debian 13), `mysql:26`, `mariadb:13` (Ubuntu 26.04), `valkey/valkey:8` or `:8-alpine`. Pin by digest. Config via file mount (ConfigMap / EFS / baked-in). | Tested (images) |
| EC2 (AL2023) | OpenSSL 3.5 is present but the crypto policy omits ML-KEM: set `ssl_groups` explicitly (PostgreSQL) or `OPENSSL_CONF` for the service in its systemd unit. | Unverified for database daemons on AL2023 |
| Client containers | Debian 13 / Alpine 3.24 bases; avoid `-bookworm` tags (OpenSSL 3.0). | Tested |

Full pod spec, task definition and systemd drop-in are in Full configuration files.

## Verify
1. Posture: engine version and parameter values.
```bash
aws rds describe-db-parameters --db-parameter-group-name pg18-pq \
  --query "Parameters[?ParameterName=='ssl_groups'].[ParameterValue]" --output text
psql "host=$H sslmode=verify-full sslrootcert=global-bundle.pem" -c "SHOW ssl_groups"
```
2. Live test from a host with OpenSSL 3.5 (for example a `debian:trixie-slim` task in the same VPC):
```bash
# PostgreSQL: PQ must succeed, classical must still work (fallback)
openssl s_client -connect $H:5432 -starttls postgres -tls1_3 -groups X25519MLKEM768 -brief </dev/null
openssl s_client -connect $H:5432 -starttls postgres -groups X25519 -brief </dev/null
# MySQL / MariaDB
openssl s_client -connect $H:3306 -starttls mysql -groups X25519MLKEM768 -brief </dev/null
# Valkey / Redis (direct TLS)
openssl s_client -connect $H:6379 -groups X25519MLKEM768 -brief </dev/null
```
Expect `Negotiated TLS1.3 group: X25519MLKEM768`; the classical run shows `Peer Temp Key: X25519` (Tested on all self-managed engines above).
3. Observed signal:
   - PostgreSQL: `log_connections` prints protocol, cipher and bits only, not the group (Tested); `pg_stat_ssl` has no group column. Use the s_client probe.
   - MySQL 26: `SHOW SESSION STATUS LIKE 'Tls_key_exchange_algorithm'` (Tested). Aurora MySQL: `Aurora_ssl_named_group` (Claimed).
   - Valkey/MariaDB: no server-side field; probe.

## Pitfalls and rollback
- Fallback is silent. A Debian 12 libpq client still connects to a PQ-first server with X25519 (Tested). Only an enforcing setting (PQ-only groups, `force_pqc`) shows the gap, by breaking it.
- Server order is not always obeyed: with OpenSSL 3.5 a client that sends only an X25519 key share got X25519 even though the server listed ML-KEM first (Tested on Valkey). OpenSSL avoids a HelloRetryRequest. Fix the client, or enforce.
- MySQL 8.4 / 9.x self-managed cannot be fixed by OpenSSL 3.5 alone (server sticks to P-256, Tested).
- MariaDB official images before 13 are on Ubuntu 24.04 (OpenSSL 3.0): no PQ (Tested).
- RDS Proxy terminates TLS; that leg stays classical.
- ML-KEM needs TLS 1.3. Clients pinned to TLS 1.2 (old JDBC, `tls_version=TLSv1.2`) stay classical.
- Rollback: set `ssl_groups` back to `prime256v1:X25519` (dynamic, applies to new connections); unset `force_pqc`; remove `OPENSSL_CONF`. Existing sessions are not dropped.

## Full configuration files

### postgresql.conf (TLS section)
```ini
# /var/lib/postgresql/data/postgresql.conf  (PostgreSQL 18, OpenSSL 3.5) - TLS section
listen_addresses = '*'
ssl = on
ssl_cert_file = '/etc/postgresql/tls/server.crt'
ssl_key_file  = '/etc/postgresql/tls/server.key'        # mode 0600, owner postgres
ssl_ca_file   = '/etc/postgresql/tls/ca.crt'            # only for client-certificate auth
ssl_min_protocol_version = 'TLSv1.2'                    # 'TLSv1.3' to enforce PQ
ssl_groups = 'X25519MLKEM768:X25519:prime256v1'         # PQ-only: 'X25519MLKEM768'
ssl_tls13_ciphers = ''                                  # library default
log_connections = on
```

### pg_hba.conf
```conf
# /var/lib/postgresql/data/pg_hba.conf - TLS required for remote clients
# TYPE    DATABASE  USER  ADDRESS       METHOD
local     all       all                 peer
hostssl   all       all   10.0.0.0/8    scram-sha-256
hostnossl all       all   0.0.0.0/0     reject
```

### rds-pg-pq.tf (Terraform: RDS instance and Aurora cluster parameter groups)
```hcl
# rds-pg-pq.tf - hybrid PQ key exchange for RDS for PostgreSQL 18 and Aurora PostgreSQL 18
variable "enforce_pq" {
  type    = bool
  default = false
}

locals {
  ssl_groups = var.enforce_pq ? "X25519MLKEM768,SecP256r1MLKEM768" : "X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1"
  min_tls    = var.enforce_pq ? "TLSv1.3" : "TLSv1.2"
}

resource "aws_db_parameter_group" "pg18_pq" {
  name   = "pg18-pq"
  family = "postgres18"

  parameter {
    name         = "ssl_groups"
    value        = local.ssl_groups
    apply_method = "immediate"
  }
  parameter {
    name         = "ssl_min_protocol_version"
    value        = local.min_tls
    apply_method = "immediate"
  }
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster_parameter_group" "aurora_pg18_pq" {
  name   = "aurora-pg18-pq"
  family = "aurora-postgresql18"

  parameter {
    name         = "ssl_groups"
    value        = local.ssl_groups
    apply_method = "immediate"
  }
  parameter {
    name         = "ssl_min_protocol_version"
    value        = local.min_tls
    apply_method = "immediate"
  }
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

# Attach: aws_db_instance.db_parameter_group_name = aws_db_parameter_group.pg18_pq.name
#         aws_rds_cluster.db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_pg18_pq.name
```

### rds-pg-pq.yaml (CloudFormation)
```yaml
# rds-pg-pq.yaml - hybrid PQ key exchange parameter groups for PostgreSQL 18
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  EnforcePq:
    Type: String
    AllowedValues: ["true", "false"]
    Default: "false"
Conditions:
  Enforce: !Equals [!Ref EnforcePq, "true"]
Resources:
  Pg18PqParams:
    Type: AWS::RDS::DBParameterGroup
    Properties:
      Family: postgres18
      Description: RDS PostgreSQL 18 hybrid ML-KEM key exchange
      Parameters:
        ssl_groups: !If [Enforce, "X25519MLKEM768,SecP256r1MLKEM768", "X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1"]
        ssl_min_protocol_version: !If [Enforce, "TLSv1.3", "TLSv1.2"]
        rds.force_ssl: "1"
  AuroraPg18PqParams:
    Type: AWS::RDS::DBClusterParameterGroup
    Properties:
      Family: aurora-postgresql18
      Description: Aurora PostgreSQL 18 hybrid ML-KEM key exchange
      Parameters:
        ssl_groups: !If [Enforce, "X25519MLKEM768,SecP256r1MLKEM768", "X25519MLKEM768,SecP256r1MLKEM768,X25519,prime256v1"]
        ssl_min_protocol_version: !If [Enforce, "TLSv1.3", "TLSv1.2"]
        rds.force_ssl: "1"
Outputs:
  InstanceParameterGroup:
    Value: !Ref Pg18PqParams
  ClusterParameterGroup:
    Value: !Ref AuroraPg18PqParams
```

### my.cnf (MySQL 26.x)
```ini
# /etc/my.cnf.d/tls-pq.cnf - MySQL 26.x built with OpenSSL 3.5
[mysqld]
ssl_ca   = /etc/mysql/tls/ca.crt
ssl_cert = /etc/mysql/tls/server.crt
ssl_key  = /etc/mysql/tls/server.key
require_secure_transport = ON
tls_version = TLSv1.2,TLSv1.3
tls_kex = X25519MLKEM768:secp256r1MLKEM768:X25519:secp256r1
replication_tls_kex = X25519MLKEM768:X25519
# Enforcement (classical clients fail; TLS 1.2-only configs are rejected):
# force_pqc = ON
# replication_force_pqc = ON

[client]
ssl-mode = VERIFY_IDENTITY
ssl-ca   = /etc/mysql/tls/ca.crt
tls-kex  = X25519MLKEM768:X25519
```

### mariadb tls.cnf (MariaDB 13 on OpenSSL 3.5)
```ini
# /etc/mysql/mariadb.conf.d/90-tls.cnf
[mariadbd]
ssl_ca   = /etc/mysql/tls/ca.crt
ssl_cert = /etc/mysql/tls/server.crt
ssl_key  = /etc/mysql/tls/server.key
require_secure_transport = ON
tls_version = TLSv1.2,TLSv1.3
# Groups come from OpenSSL: X25519MLKEM768 first by default on OpenSSL 3.5.
# To change order or enforce PQ-only, set OPENSSL_CONF (see openssl-groups.cnf).
```

### valkey.conf (TLS)
```conf
# /etc/valkey/valkey.conf - TLS section (Valkey 8.x on OpenSSL 3.5)
port 0
tls-port 6379
tls-cert-file /etc/valkey/tls/server.crt
tls-key-file  /etc/valkey/tls/server.key
tls-ca-cert-file /etc/valkey/tls/ca.crt
tls-auth-clients optional
tls-protocols "TLSv1.2 TLSv1.3"
tls-replication yes
tls-cluster yes
# Group order: OPENSSL_CONF=/etc/ssl/openssl-groups.cnf in the service environment
```

### openssl-groups.cnf (process-wide groups for daemons without a group option)
```ini
# /etc/ssl/openssl-groups.cnf - use with OPENSSL_CONF=/etc/ssl/openssl-groups.cnf
# OpenSSL 3.5+ (Debian 13, Alpine 3.22+, Ubuntu 26.04). Tested with Valkey 8.1.11.
openssl_conf = openssl_init

[openssl_init]
ssl_conf = ssl_module
providers = provider_sect

[provider_sect]
default = default_sect

[default_sect]
activate = 1

[ssl_module]
system_default = tls_defaults

[tls_defaults]
MinProtocol = TLSv1.2
Groups = X25519MLKEM768:X25519:secp256r1:secp384r1
# PQ-only enforcement variant (openssl-pq-only.cnf):
#   MinProtocol = TLSv1.3
#   Groups = X25519MLKEM768
```

### Kafka server.properties (TLS excerpt) and JVM options
```properties
# /opt/kafka/config/server.properties - TLS listener (broker on JDK 25.0.5+)
listeners=SSL://:9093
security.inter.broker.protocol=SSL
ssl.enabled.protocols=TLSv1.3,TLSv1.2
ssl.protocol=TLSv1.3
ssl.keystore.type=PKCS12
ssl.keystore.location=/opt/kafka/tls/broker.p12
ssl.keystore.password=${file:/opt/kafka/tls/secrets.properties:keystore.password}
ssl.truststore.type=PKCS12
ssl.truststore.location=/opt/kafka/tls/truststore.p12
ssl.truststore.password=${file:/opt/kafka/tls/secrets.properties:truststore.password}
ssl.client.auth=required
# Environment (Unverified on a broker):
# KAFKA_OPTS="-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1"
# JDK 8-21: add -javaagent from the Java tab instead.
```

### postgres-pq.yaml (EKS: StatefulSet excerpt)
```yaml
# postgres-pq.yaml - PostgreSQL 18 on EKS with hybrid PQ groups (same -c flags as the tests)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres }
    spec:
      securityContext:
        fsGroup: 999
      containers:
        - name: postgres
          image: postgres:18   # Debian 13, OpenSSL 3.5.x; pin by digest for your architecture
          args:
            - "-c"
            - "ssl=on"
            - "-c"
            - "ssl_cert_file=/etc/postgresql/tls/tls.crt"
            - "-c"
            - "ssl_key_file=/etc/postgresql/tls/tls.key"
            - "-c"
            - "ssl_min_protocol_version=TLSv1.2"
            - "-c"
            - "ssl_groups=X25519MLKEM768:X25519:prime256v1"
          env:
            - name: POSTGRES_PASSWORD
              valueFrom: { secretKeyRef: { name: postgres-auth, key: password } }
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          ports: [{ containerPort: 5432 }]
          volumeMounts:
            - { name: tls, mountPath: /etc/postgresql/tls, readOnly: true }
            - { name: data, mountPath: /var/lib/postgresql/data }
      volumes:
        - name: tls
          secret: { secretName: postgres-tls-cert, defaultMode: 0640 }   # key must be readable by uid 999 only
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 20Gi } }
```

### valkey task definition (ECS/Fargate excerpt)
```json
{
  "family": "valkey-pq",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [
    {
      "name": "valkey",
      "image": "valkey/valkey:8-alpine",
      "command": ["valkey-server", "/etc/valkey/valkey.conf"],
      "environment": [
        { "name": "OPENSSL_CONF", "value": "/etc/ssl/openssl-groups.cnf" }
      ],
      "portMappings": [{ "containerPort": 6379 }],
      "mountPoints": [{ "sourceVolume": "valkey-config", "containerPath": "/etc/valkey" }]
    }
  ],
  "volumes": [{ "name": "valkey-config", "efsVolumeConfiguration": { "fileSystemId": "fs-REPLACE" } }]
}
```
Bake `openssl-groups.cnf`, `valkey.conf` and certificates into the image (or EFS) and pin the image by digest.

### systemd drop-in (EC2, any OpenSSL-based daemon)
```ini
# /etc/systemd/system/valkey.service.d/10-pq-groups.conf
[Service]
Environment=OPENSSL_CONF=/etc/ssl/openssl-groups.cnf
```
Then `systemctl daemon-reload && systemctl restart valkey`.

### Test scripts (this tab's evidence)
`run-db.sh`, `run-db2.sh`, `run-db3.sh`, `run-db4.sh`, `run-valkey-conf.sh` with outputs `db*-results.txt`, `valkey-conf-results.txt` in the deep/data work directory. Image digests in `digests.txt`.
