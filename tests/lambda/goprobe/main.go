package main
import ("crypto/tls";"fmt";"runtime")
func try(port int) string { c, err := tls.Dial("tcp", fmt.Sprintf("pqsrv:%d", port), &tls.Config{InsecureSkipVerify: true}); if err != nil { return "FAIL" }; defer c.Close(); return fmt.Sprintf("OK %x", c.ConnectionState().Version) }
func main() { fmt.Printf("{\"go\":%q,\"pq_only\":%q,\"classical_only\":%q}\n", runtime.Version(), try(8443), try(8444)) }
