//go:debug tlsmlkem=1
package main

import (
    "context"
    "crypto/fips140"
    "crypto/tls"
    "log"
    "net/http"
    "time"

    awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/sts"
)

// The //go:debug line is optional: needed only while go.mod says go < 1.24.

func httpClient() *http.Client {
    tr := http.DefaultTransport.(*http.Transport).Clone()
    tr.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12} // no CurvePreferences
    return &http.Client{Transport: tr, Timeout: 30 * time.Second}
}

func awsHTTPClient() *awshttp.BuildableClient {
    return awshttp.NewBuildableClient().WithTransportOptions(func(t *http.Transport) {
        if fips140.Enabled() {
            // aws-sdk-go-v2 v1.48.0 forces P-256/384/521 in FIPS mode; keep the approved hybrids.
            t.TLSClientConfig.CurvePreferences = []tls.CurveID{
                tls.SecP256r1MLKEM768, tls.X25519MLKEM768, tls.CurveP256, tls.CurveP384}
        }
    })
}

func main() {
    ctx := context.Background()
    cfg, err := config.LoadDefaultConfig(ctx, config.WithHTTPClient(awsHTTPClient()))
    if err != nil {
        log.Fatal(err)
    }
    out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
    if err != nil {
        log.Fatal(err)
    }
    log.Printf("caller=%s", *out.Arn)

    resp, err := httpClient().Get("https://api.internal.example.com/health")
    if err != nil {
        log.Fatal(err)
    }
    defer resp.Body.Close()
    log.Printf("status=%d tls_group=%v", resp.StatusCode, resp.TLS.CurveID)
}
