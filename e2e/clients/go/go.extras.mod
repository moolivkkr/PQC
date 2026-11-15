module pqc-e2e/probe-go

// Extras build (aws-sdk-go-v2, PKCS#12 loaders): go build -modfile=go.extras.mod -tags extras. Go 1.26+ only.
go 1.26.0

require (
	github.com/aws/aws-lambda-go v1.54.0
	github.com/aws/aws-sdk-go-v2 v1.48.0
	golang.org/x/crypto v0.59.0
	software.sslmate.com/src/go-pkcs12 v0.7.4
)

require github.com/aws/smithy-go v1.28.9 // indirect
