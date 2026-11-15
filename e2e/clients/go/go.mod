module pqc-e2e/probe-go

// The go line is rewritten per build by build/go.sh (go mod edit -go=...): it sets DefaultGODEBUG, one of the
// five inputs the Go tab lists. aws-lambda-go v1.54.0 is the newest release whose own go line (1.18) lets a
// Go 1.23 main module build; v1.55+ require go 1.26.
go 1.23

require github.com/aws/aws-lambda-go v1.54.0
