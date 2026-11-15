"""Check the Athena RegexSerDe patterns in athena.sql against AWS's documented sample lines
(plus 15-field / PQ variants). Java and Python regex agree on these constructs."""
import re, sys

sql = open(sys.argv[1]).read()
pats = re.findall(r"'input\.regex' = '(.*?)'\n", sql)
alb_re, nlb_re = [re.compile(p.replace('\\"', '"')) for p in pats]

alb_lines = [
    # AWS doc sample (12 fields, mTLS verify)
    '2023-10-04T17:05:15.514108Z 203.0.113.1 36280 443 TLSv1.2 ECDHE-RSA-AES128-GCM-SHA256 4.036 "CN=amazondomains.com,O=endEntity,L=Seattle,ST=Washington,C=US" NotBefore=2023-09-21T22:43:21Z;NotAfter=2026-06-17T22:43:21Z FEF257372D5C14D4 Success TID_3180a73013c8ca4bac2f731159d4b0fe',
    # 15 fields, no mTLS, PQ (value spelling assumed)
    '2026-11-14T10:00:00.000000Z 198.51.100.7 51234 443 TLSv1.3 TLS_AES_128_GCM_SHA256 0.012 - - - Success TID_abc X25519MLKEM768 app/app-pq/0123456789abcdef 10.0.1.23',
    # 15 fields, classical TLS 1.2
    '2026-11-14T10:00:01.000000Z 198.51.100.8 51235 443 TLSv1.2 ECDHE-RSA-AES128-GCM-SHA256 0.020 - - - Success TID_abd x25519 app/app-pq/0123456789abcdef 10.0.1.23',
    # future trailing field must be ignored
    '2026-11-14T10:00:02.000000Z 198.51.100.9 51236 443 TLSv1.3 TLS_AES_256_GCM_SHA384 0.011 - - - Success TID_abe X25519MLKEM768 app/app-pq/0123456789abcdef 10.0.1.23 newfield',
]
nlb_lines = [
    # AWS doc samples (joined onto one line)
    'tls 2.0 2018-12-20T02:59:40 net/my-network-loadbalancer/c6e77e28c25b2234 g3d4b5e8bb8464cd 72.21.218.154:51341 172.100.100.185:443 5 2 98 246 - arn:aws:acm:us-east-2:671290407336:certificate/2a108f19-aded-46b0-8493-c63eb1ef4a99 - ECDHE-RSA-AES128-SHA tlsv12 - my-network-loadbalancer-c6e77e28c25b2234.elb.us-east-2.amazonaws.com - - - 2018-12-20T02:59:30',
    'tls 2.0 2020-04-01T08:51:42 net/my-network-loadbalancer/c6e77e28c25b2234 g3d4b5e8bb8464cd 72.21.218.154:51341 172.100.100.185:443 5 2 98 246 - arn:aws:acm:us-east-2:671290407336:certificate/2a108f19-aded-46b0-8493-c63eb1ef4a99 - ECDHE-RSA-AES128-SHA tlsv12 - my-network-loadbalancer-c6e77e28c25b2234.elb.us-east-2.amazonaws.com h2 h2 "h2","http/1.1" 2020-04-01T08:51:20',
    'tls 2.0 2026-11-14T10:00:00 net/svc-pq/0123456789abcdef 0123456789abcdef 198.51.100.7:51234 10.0.1.40:443 40 3 512 2048 - arn:aws:acm:us-east-1:111122223333:certificate/x - TLS_AES_128_GCM_SHA256 tlsv13 X25519MLKEM768 api.example.com h2 h2 "h2","http/1.1" 2026-11-14T09:59:59',
]
fails = 0
for name, rx, lines, kx_idx, n in (("alb", alb_re, alb_lines, 13, 15), ("nlb", nlb_re, nlb_lines, 19, 24)):
    for ln in lines:
        m = rx.match(ln)
        if not m:
            print(f"FAIL {name}: no match: {ln[:60]}"); fails += 1; continue
        g = m.groups()
        print(f"OK   {name}: groups={len(g)} tls={g[4] if name=='alb' else g[17]} kx={g[kx_idx-1]!r} last={g[n-1]!r}")
print("FAILURES", fails)
sys.exit(1 if fails else 0)
