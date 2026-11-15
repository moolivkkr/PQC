# Load balancer target probes (server role)

One small HTTPS server per language, on the language's standard server stack, with no TLS group or version setting
in code. Each one:

1. listens on `PQC_SERVER_PORT` (default 9443) with the test RSA server certificate (`server-rsa.crt`/`.key`,
   `server.p12` for Java),
2. asks the observer to connect back the way a load balancer connects to an HTTPS target:
   `GET http://pq-observer:8080/dialback?id=<case>&port=9443&policy=<target>` for each target in `PQC_TARGETS`
   (`alb-pq`, `alb-classic`; see observer/main.go),
3. prints one `{"event":"tls_handshake",...}` line per target (what the target negotiated with the load balancer)
   and the `PQC_RESULT` line, then exits.

The images are the client images from build/<lang>.sh plus these files (build/server.sh), so the fix under test
(config file, crypto policy, base image, JDK kit, Go toolchain) is applied exactly as in the client cases.
