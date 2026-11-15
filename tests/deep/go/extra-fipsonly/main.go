// extra: error text for a failing handshake, plus MLKEM1024 and fipsonly checks.
// MODE=err (default config, prints error per target) | mlkem1024 (CurvePreferences=[MLKEM1024,X25519MLKEM768,X25519])
package main

import (
	"crypto/tls"
	"fmt"
	"os"
	"runtime"
)

func main() {
	c := &tls.Config{InsecureSkipVerify: true}
	if os.Getenv("MODE") == "mlkem1024" {
		c.CurvePreferences = []tls.CurveID{tls.CurveID(514), tls.CurveID(4588), tls.X25519}
	}
	for _, a := range []string{"pqsrv:8443", "pqsrv:8444", "pqsrv:8446", "pqsrv:8448"} {
		conn, err := tls.Dial("tcp", a, c)
		if err != nil {
			fmt.Printf("%s %s %s ERR %v\n", runtime.Version(), os.Getenv("GODEBUG"), a, err)
			continue
		}
		fmt.Printf("%s %s %s OK %v\n", runtime.Version(), os.Getenv("GODEBUG"), a, conn.ConnectionState().CurveID)
		conn.Close()
	}
}
