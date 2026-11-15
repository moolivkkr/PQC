# Pin both images by digest in your registry mirror.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/server ./cmd/server \
 && go version -m /out/server | grep -q 'tlsmlkem=0' && { echo 'classical build: raise go line'; exit 1; } || true

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
# Optional while go.mod is < 1.26:
# ENV GODEBUG=tlsmlkem=1,tlssecpmlkem=1
USER nonroot:nonroot
EXPOSE 8443 9443
ENTRYPOINT ["/server"]
