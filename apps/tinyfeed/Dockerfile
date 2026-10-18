# Build context is the upstream tinyfeed tree at the pinned release commit.
# Follows the upstream dockerfile (static Go binary on scratch); base images are pinned by digest.

FROM golang:1.26.9-alpine3.24@sha256:3082400e369fa24d5fc60bca20edab3f6d604e0c5a690ec66b295eff4dd87ade AS build
RUN apk add --no-cache upx
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /tinyfeed .
# Compress the binary (as upstream does); an unchanged binary is kept if upx cannot pack it.
RUN upx --best -q /tinyfeed || echo "upx skipped"; /tinyfeed --help >/dev/null 2>&1
RUN mkdir /app && chown 10001:10001 /app \
 && echo 'feed:x:10001:10001::/app:/sbin/nologin' > /passwd

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS certs

FROM scratch
LABEL org.opencontainers.image.title="tinyfeed" \
      org.opencontainers.image.description="Aggregates RSS, Atom and JSON feeds into one static HTML page" \
      org.opencontainers.image.url="https://github.com/TheBigRoomXXL/tinyfeed" \
      org.opencontainers.image.source="https://github.com/TheBigRoomXXL/tinyfeed" \
      org.opencontainers.image.version="1.5.1" \
      org.opencontainers.image.licenses="MIT"
COPY --from=build /passwd /etc/passwd
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /tinyfeed /usr/local/bin/tinyfeed
COPY --from=build --chown=10001:10001 /app /app
USER 10001:10001
WORKDIR /app
# tinyfeed only writes an HTML file and has no HTTP server; the check proves the static binary starts.
HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/tinyfeed", "--help"]
ENTRYPOINT ["/usr/local/bin/tinyfeed"]
