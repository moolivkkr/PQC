-- elb-logs-athena.sql: classical vs PQ handshakes at ALB (connection logs) and NLB (TLS access logs).

-- ALB connection logs (15 space-separated fields; tls_keyexchange = field 13).
CREATE EXTERNAL TABLE IF NOT EXISTS alb_connection_logs (
  time string, client_ip string, client_port int, listener_port int,
  tls_protocol string, tls_cipher string, tls_handshake_latency double,
  leaf_client_cert_subject string, leaf_client_cert_validity string, leaf_client_cert_serial_number string,
  tls_verify_status string, conn_trace_id string, tls_keyexchange string, elb string, ip_address string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([0-9]*) ([0-9]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ("[^"]*"|[^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ?([^ ]*)? ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, listener_port, tls_protocol, tls_keyexchange, count(*) AS conns,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY elb), 1) AS pct
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_verify_status = 'Success'
GROUP BY 1, 2, 3, 4 ORDER BY elb, conns DESC;

-- Top classical clients (for the exception register / client upgrade list)
SELECT client_ip, tls_protocol, tls_keyexchange, count(*) AS conns
FROM alb_connection_logs
WHERE tls_protocol <> '-' AND tls_keyexchange NOT LIKE '%MLKEM%'
GROUP BY 1, 2, 3 ORDER BY conns DESC LIMIT 100;

-- NLB TLS access logs (tls_keyexchange = field 17).
CREATE EXTERNAL TABLE IF NOT EXISTS nlb_tls_logs (
  type string, version string, time string, elb string, listener string, client_port string,
  destination_port string, connection_time double, tls_handshake_time string, received_bytes bigint,
  sent_bytes bigint, incoming_tls_alert string, chosen_cert_arn string, chosen_cert_serial string,
  tls_cipher string, tls_protocol_version string, tls_keyexchange string, domain_name string,
  alpn_fe_protocol string, alpn_be_protocol string, alpn_client_preference_list string,
  tls_connection_creation_time string)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' =
  '([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([-.0-9]*) ([^ ]*) ([-0-9]*) ([-0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ("[^"]*"|[^ ]*) ?([^ ]*)?.*')
LOCATION 's3://LOG_BUCKET/PREFIX/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

SELECT elb, tls_protocol_version, tls_keyexchange, count(*) AS conns
FROM nlb_tls_logs
WHERE tls_protocol_version <> '-'
GROUP BY 1, 2, 3 ORDER BY conns DESC;

-- Alarm feed: run hourly (EventBridge Scheduler -> Athena StartQueryExecution via Step Functions)
-- and publish the share of non-ML-KEM TLS 1.3+1.2 handshakes as a CloudWatch metric.
SELECT count_if(tls_keyexchange NOT LIKE '%MLKEM%') AS classical,
       count(*) AS total
FROM alb_connection_logs
WHERE tls_protocol <> '-'
  AND from_iso8601_timestamp(time) > now() - interval '1' hour;
