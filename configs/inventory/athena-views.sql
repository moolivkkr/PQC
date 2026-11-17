-- PQ TLS inventory and observed-signal views for Athena (engine v3).
-- Unverified: written against the AWS and Zeek log formats, not run on Athena (no AWS account here).
-- Assumes these tables already exist:
--   cloudtrail_logs   stock CloudTrail DDL with keyexchange:string added to tlsdetails (enforcement: cloudtrail-non-pq.sql)
--   alb_connection_logs, nlb_tls_logs   from enforcement/rules/runtime/elb-logs-athena.sql
-- and creates: pq_inventory (posture, from pq_inventory.py), zeek_ssl (Zeek JSON ssl.log),
-- app_handshake (the tls_handshake JSON lines our probes and handshake logging write, exported from CloudWatch Logs).

CREATE EXTERNAL TABLE IF NOT EXISTS pq_inventory (
  resource_type string, arn string, name string, compute string, language string, runtime string,
  status string, action string, fix string, signal string, block_update string, role string,
  account string, account_label string, region string, scanned_at string)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://<inventory-bucket>/pq-inventory/';

-- Zeek: LogAscii::use_json=T; ship ssl.log to S3 (Firehose or the sensor's own sync), one folder per day.
CREATE EXTERNAL TABLE IF NOT EXISTS zeek_ssl (
  ts double, uid string, id_orig_h string, id_resp_h string, id_resp_p int,
  version string, cipher string, curve string, server_name string, established boolean,
  ja4 string, pq boolean)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('mapping.id_orig_h'='id.orig_h', 'mapping.id_resp_h'='id.resp_h', 'mapping.id_resp_p'='id.resp_p')
LOCATION 's3://<sensor-bucket>/zeek/ssl/';

CREATE EXTERNAL TABLE IF NOT EXISTS app_handshake (
  event string, lang string, runtime string, compute string, target string, ok boolean,
  tls_version string, `group` string, pq boolean, pq_status string, function_name string, service string)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://<logs-bucket>/tls-handshake/';

-- One row per observed handshake (or call), whatever the source. who = the caller we can name.
CREATE OR REPLACE VIEW pq_observed AS
SELECT 'cloudtrail' AS source, from_iso8601_timestamp(eventtime) AS ts, recipientaccountid AS account,
       useridentity.sessioncontext.sessionissuer.arn AS who, eventsource AS dest,
       tlsdetails.tlsversion AS tls_version, tlsdetails.keyexchange AS grp,
       coalesce(tlsdetails.keyexchange LIKE '%MLKEM%', false) AS pq
FROM cloudtrail_logs
WHERE tlsdetails.tlsversion IS NOT NULL AND useridentity.invokedby IS NULL
UNION ALL
SELECT 'alb', from_iso8601_timestamp(time), NULL, client_ip, elb || ':' || cast(listener_port AS varchar),
       tls_protocol, tls_keyexchange, coalesce(tls_keyexchange LIKE '%MLKEM%', false)
FROM alb_connection_logs WHERE tls_protocol <> '-'
UNION ALL
SELECT 'nlb', from_iso8601_timestamp(time), NULL, NULL, elb || ':' || listener, tls_protocol_version,
       tls_keyexchange, coalesce(tls_keyexchange LIKE '%MLKEM%', false)
FROM nlb_tls_logs WHERE tls_protocol_version <> '-'
UNION ALL
SELECT 'zeek', from_unixtime(ts), NULL, id_orig_h, coalesce(server_name, id_resp_h), version, curve,
       coalesce(lower(curve) LIKE '%mlkem%', false)
FROM zeek_ssl WHERE established
UNION ALL
SELECT 'app', NULL, NULL, coalesce(function_name, service), target, tls_version, "group", pq
FROM app_handshake WHERE event = 'tls_handshake' AND ok;

-- Dashboard 1: classical share per source and day.
-- SELECT source, date(ts) AS day, count(*) AS handshakes, avg(CASE WHEN pq THEN 0.0 ELSE 1.0 END) AS classical_share
-- FROM pq_observed GROUP BY 1, 2 ORDER BY 2, 1;

-- Dashboard 2: posture burndown, latest scan per component.
CREATE OR REPLACE VIEW pq_inventory_latest AS
SELECT * FROM (
  SELECT i.*, row_number() OVER (PARTITION BY arn ORDER BY scanned_at DESC) AS rn FROM pq_inventory i) WHERE rn = 1;
-- SELECT compute, language, status, count(*) FROM pq_inventory_latest GROUP BY 1, 2, 3;

-- Dashboard 3: observed vs posture per workload. CloudTrail names the role, so join on it.
CREATE OR REPLACE VIEW pq_workload AS
SELECT i.account, i.compute, i.language, i.name, i.runtime, i.status AS posture, i.block_update,
       count(o.who) AS aws_calls_seen,
       sum(CASE WHEN o.pq THEN 0 ELSE 1 END) AS aws_calls_classical
FROM pq_inventory_latest i
LEFT JOIN pq_observed o ON o.source = 'cloudtrail' AND o.who = i.role AND o.ts > current_timestamp - interval '7' day
GROUP BY 1, 2, 3, 4, 5, 6, 7;
-- "Done" = posture in ('pq', 'pq-fixed') AND aws_calls_classical = 0. A pq-fixed row with classical calls is a
-- failed fix (library pinning its own groups, a second TLS stack): investigate before closing it.

-- Dashboard 4: classical east-west and egress flows from Zeek, by client and destination.
-- SELECT id_orig_h, coalesce(server_name, id_resp_h) AS dest, version, curve, count(*) AS n
-- FROM zeek_ssl WHERE established AND NOT coalesce(lower(curve) LIKE '%mlkem%', false)
-- GROUP BY 1, 2, 3, 4 ORDER BY n DESC LIMIT 100;
