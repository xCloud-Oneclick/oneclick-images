# Build context is the upstream Parseable tree at the pinned release commit.
# The builder is upstream's root Dockerfile (upstream's own `release-lto` profile: fat LTO, one codegen unit; no Kafka feature) with the base image
# pinned by digest and the binary stripped. The runtime is distroless cc (glibc, no package manager),
# the `debug-nonroot` variant only for its busybox wget, which serves the HEALTHCHECK. It runs as the
# unprivileged uid 65532 and owns the two data directories.

FROM rust:1.96.0-bookworm@sha256:5e2214abe154fe26e39f64488952e5c991eeed1d6d6da7cc8381ae83927f0cfc AS builder

WORKDIR /parseable
COPY . .
ENV CARGO_PROFILE_RELEASE_STRIP=symbols \
    CARGO_PROFILE_RELEASE_DEBUG=false
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/parseable/target \
    cargo build --profile release-lto --locked \
 && install -D target/release-lto/parseable /out/usr/bin/parseable \
 && mkdir -p /out/data /out/staging \
 && du -sh /out/usr/bin/parseable

FROM gcr.io/distroless/cc-debian12:debug-nonroot@sha256:923320b891f20d5f4bd43ed3a72eeee2f3323d481d6f4bd8d0b2c96d1c0758bc

LABEL org.opencontainers.image.title="Parseable" \
      org.opencontainers.image.description="Parseable log and observability server" \
      org.opencontainers.image.url="https://www.parseable.com" \
      org.opencontainers.image.source="https://github.com/parseablehq/parseable" \
      org.opencontainers.image.version="3.2.5" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

COPY --from=builder /out/usr/bin/parseable /usr/bin/parseable
COPY --from=builder --chown=65532:65532 /out/data /data
COPY --from=builder --chown=65532:65532 /out/staging /staging

ENV P_FS_DIR=/data \
    P_STAGING_DIR=/staging

WORKDIR /parseable
USER 65532:65532
EXPOSE 8000
VOLUME ["/data", "/staging"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["/busybox/wget", "-q", "-O", "/dev/null", "http://127.1:8000/api/v1/liveness"]
CMD ["/usr/bin/parseable", "local-store"]
