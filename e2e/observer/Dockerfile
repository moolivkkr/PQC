FROM golang@sha256:eb61c3873c97416fff0116553fff65d67a3549f72e11d9758849a689cdd8b523 AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -o /observer .
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.12.20261109.0
COPY --from=build /observer /usr/local/bin/observer
RUN dnf -y install wget && dnf clean all
EXPOSE 8080 8443 8444 8445 8446 8447
ENTRYPOINT ["/usr/local/bin/observer"]
