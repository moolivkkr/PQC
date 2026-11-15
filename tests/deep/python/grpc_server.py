"""grpcio TLS server with no services: enough to test the TLS handshake (BoringSSL inside grpcio)."""
import sys
from concurrent import futures

import grpc

port = int(sys.argv[1]) if len(sys.argv) > 1 else 9446
key = open("/w/certs/leaf.key", "rb").read()
crt = open("/w/certs/leaf.pem", "rb").read()
server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
server.add_secure_port("[::]:%d" % port, grpc.ssl_server_credentials([(key, crt)]))
server.start()
print("grpc server on %d, grpcio %s" % (port, grpc.__version__), flush=True)
server.wait_for_termination()
