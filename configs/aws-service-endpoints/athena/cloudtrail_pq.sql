-- Add keyExchange to the tlsDetails struct of the AWS sample CloudTrail table.
CREATE EXTERNAL TABLE cloudtrail_pq (
  eventVersion STRING,
  userIdentity STRUCT<type:STRING, principalId:STRING, arn:STRING, accountId:STRING, invokedBy:STRING>,
  eventTime STRING,
  eventSource STRING,
  eventName STRING,
  awsRegion STRING,
  sourceIpAddress STRING,
  userAgent STRING,
  recipientAccountId STRING,
  vpcEndpointId STRING,
  tlsDetails STRUCT<tlsVersion:STRING, cipherSuite:STRING, keyExchange:STRING, clientProvidedHostHeader:STRING>
)
PARTITIONED BY (account STRING, region STRING, day STRING)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://<trail-bucket>/AWSLogs/<org-id>/'
TBLPROPERTIES (
  'projection.enabled'='true',
  'projection.account.type'='enum', 'projection.account.values'='<acct1>,<acct2>',
  'projection.region.type'='enum',  'projection.region.values'='us-east-1,us-west-2',
  'projection.day.type'='date', 'projection.day.range'='2026/01/01,NOW', 'projection.day.format'='yyyy/MM/dd',
  'storage.location.template'='s3://<trail-bucket>/AWSLogs/<org-id>/${account}/CloudTrail/${region}/${day}'
);

-- Non-PQ calls by account, service and role, last 7 days.
SELECT recipientAccountId, eventSource, userIdentity.arn AS caller,
       coalesce(tlsDetails.keyExchange, '(none)') AS kx, count(*) AS calls
FROM cloudtrail_pq
WHERE day >= date_format(current_date - interval '7' day, '%Y/%m/%d')
  AND eventSource IN ('kms.amazonaws.com','secretsmanager.amazonaws.com','sts.amazonaws.com',
                      'iam.amazonaws.com','acm.amazonaws.com','rolesanywhere.amazonaws.com')
  AND userIdentity.invokedBy IS NULL
  AND (tlsDetails.keyExchange IS NULL OR tlsDetails.keyExchange NOT LIKE '%MLKEM%')
GROUP BY 1,2,3,4
ORDER BY calls DESC;
