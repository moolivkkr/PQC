// Load balancer target probe - Go (net/http ListenAndServeTLS, default tls.Config).
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func main() {
	caseID, port, obs := env("PQC_CASE_ID", "adhoc"), env("PQC_SERVER_PORT", "9443"), env("PQC_OBSERVER", "pq-observer")
	exe, _ := os.Executable()
	dir := filepath.Dir(exe)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"ok":true,"server":"go"}`)
	})
	go func() {
		if err := http.ListenAndServeTLS(":"+port, filepath.Join(dir, "server-rsa.crt"), filepath.Join(dir, "server-rsa.key"), nil); err != nil {
			fmt.Println("listen:", err)
			os.Exit(1)
		}
	}()
	time.Sleep(300 * time.Millisecond)
	out := map[string]any{"case_id": caseID, "lang": "go", "role": "server", "runtime": runtime.Version(),
		"compute": env("PQC_COMPUTE", "unknown"), "mode": env("PQC_MODE", "baseline"), "godebug": os.Getenv("GODEBUG")}
	results := map[string]map[string]any{}
	c := &http.Client{Timeout: 30 * time.Second}
	for _, t := range strings.Split(env("PQC_TARGETS", "alb-pq,alb-classic"), ",") {
		if t == "" {
			continue
		}
		res := map[string]any{}
		r, err := c.Get(fmt.Sprintf("http://%s:8080/dialback?id=%s&port=%s&policy=%s", obs, caseID, port, t))
		if err == nil {
			err = json.NewDecoder(r.Body).Decode(&res)
			r.Body.Close()
		}
		if err != nil {
			res = map[string]any{"ok": false, "error": err.Error()}
		}
		st := "failed"
		if ok, _ := res["ok"].(bool); ok {
			st = "classical"
			if pq, _ := res["pq"].(bool); pq {
				st = "pq"
			}
		}
		res["pq_status"] = st
		results[t] = res
		line := map[string]any{"event": "tls_handshake", "role": "server", "case_id": caseID, "lang": "go",
			"runtime": out["runtime"], "compute": out["compute"], "mode": out["mode"], "target": t}
		for k, v := range res {
			line[k] = v
		}
		b, _ := json.Marshal(line)
		fmt.Println(string(b))
	}
	out["results"] = results
	b, _ := json.Marshal(out)
	fmt.Println("PQC_RESULT " + string(b))
}
