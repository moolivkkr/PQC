//go:build fipsonly

package main

// Go tab case G: boringcrypto + import _ "crypto/tls/fipsonly" (build with -tags fipsonly and GOEXPERIMENT=boringcrypto).
import _ "crypto/tls/fipsonly"

const fipsOnlyImported = true
