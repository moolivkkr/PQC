-- ALB connection logs: 15 fields (tls_keyexchange = field 13). AWS's published Athena DDL
-- stops at conn_trace_id; this one adds tls_keyexchange, elb and ip_address, and accepts
-- an unquoted "-" in leaf_client_cert_subject (listeners without mTLS).
CREATE EXTERNAL TABLE IF NOT EXISTS alb_connection_logs (
  time string, client_ip string, client_port int, listener_port int,
  tls_protocol string, tls_cipher string, tls_handshake_latency double,
  leaf_client_cert_subject string, leaf_client_cert_validity string,
  leaf_client_cert_serial_number string, tls_verify_status string,
  conn_trace_id string, tls_keyexchange string, elb string, ip_address string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
  'serialization.format' = '1',
  'input.regex' = '^([^ ]*) ([^ ]*) ([0-9]*) ([0-9]*) ([A-Za-z0-9.-]*) ([^ ]*) ([-.0-9]*) (\"[^\"]*\"|[^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ?([^ ]*)? ?([^ ]*)? ?([^ ]*)?(?: .*)?$'
)
LOCATION 's3://LOG_BUCKET/alb-conn/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

-- NLB access logs v2.0: 22 fields (tls_keyexchange = field 17). "ip:port" fields split in two.
CREATE EXTERNAL TABLE IF NOT EXISTS nlb_tls_logs (
  type string, version string, time string, elb string, listener_id string,
  client_ip string, client_port int, destination_ip string, destination_port int,
  connection_time_ms double, tls_handshake_time_ms double,
  received_bytes bigint, sent_bytes bigint, incoming_tls_alert string,
  chosen_cert_arn string, chosen_cert_serial string, tls_cipher string,
  tls_protocol_version string, tls_keyexchange string, domain_name string,
  alpn_fe_protocol string, alpn_be_protocol string,
  alpn_client_preference_list string, tls_connection_creation_time string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
  'serialization.format' = '1',
  'input.regex' = '^([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*):([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-0-9]*) ([-0-9]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*) ?([^ ]*)?(?: .*)?$'
)
LOCATION 's3://LOG_BUCKET/nlb-access/AWSLogs/ACCOUNT_ID/elasticloadbalancing/REGION/';

-- Q1. Key-exchange mix per ALB, last 7 days.
SELECT elb, tls_protocol, tls_keyexchange, count(*) AS connections,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY elb), 2) AS pct
FROM alb_connection_logs
WHERE tls_protocol <> '-'
  AND from_iso8601_timestamp(time) > current_timestamp - interval '7' day
GROUP BY elb, tls_protocol, tls_keyexchange
ORDER BY elb, connections DESC;

-- Q2. Classical clients on an ALB: top client IPs without ML-KEM.
SELECT client_ip, tls_protocol, tls_keyexchange, count(*) AS connections
FROM alb_connection_logs
WHERE tls_protocol <> '-'
  AND lower(tls_keyexchange) NOT LIKE '%mlkem%'
  AND from_iso8601_timestamp(time) > current_timestamp - interval '7' day
GROUP BY client_ip, tls_protocol, tls_keyexchange
ORDER BY connections DESC
LIMIT 100;

-- Q3. Gate for the TLS 1.3-only move: TLS 1.2 or older per listener port.
SELECT elb, listener_port, tls_protocol, count(*) AS connections
FROM alb_connection_logs
WHERE tls_protocol IN ('TLSv1', 'TLSv1.1', 'TLSv1.2')
  AND from_iso8601_timestamp(time) > current_timestamp - interval '30' day
GROUP BY elb, listener_port, tls_protocol
ORDER BY connections DESC;

-- Q4. User agents of classical connections (ALB access logs carry the same conn_trace_id).
-- Assumes an alb_access_logs table with a conn_trace_id column.
SELECT a.user_agent, c.tls_keyexchange, count(*) AS requests
FROM alb_connection_logs c
JOIN alb_access_logs a ON a.conn_trace_id = c.conn_trace_id
WHERE lower(c.tls_keyexchange) NOT LIKE '%mlkem%' AND c.tls_protocol <> '-'
GROUP BY a.user_agent, c.tls_keyexchange
ORDER BY requests DESC
LIMIT 50;

-- Q5. NLB TLS listeners: key-exchange mix, then classical clients by SNI.
SELECT elb, domain_name, tls_protocol_version, tls_keyexchange, count(*) AS connections
FROM nlb_tls_logs
WHERE tls_protocol_version <> '-'
GROUP BY elb, domain_name, tls_protocol_version, tls_keyexchange
ORDER BY connections DESC;

SELECT client_ip, domain_name, tls_protocol_version, tls_keyexchange, count(*) AS connections
FROM nlb_tls_logs
WHERE tls_protocol_version <> '-' AND lower(tls_keyexchange) NOT LIKE '%mlkem%'
GROUP BY client_ip, domain_name, tls_protocol_version, tls_keyexchange
ORDER BY connections DESC
LIMIT 100;
