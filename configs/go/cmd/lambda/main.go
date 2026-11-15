package main

import (
    "context"

    "github.com/aws/aws-lambda-go/lambda"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/sts"
)

func handler(ctx context.Context) (string, error) {
    cfg, err := config.LoadDefaultConfig(ctx) // default HTTP client: PQ outside FIPS mode
    if err != nil {
        return "", err
    }
    out, err := sts.NewFromConfig(cfg).GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
    if err != nil {
        return "", err
    }
    return *out.Arn, nil
}

func main() { lambda.Start(handler) }
