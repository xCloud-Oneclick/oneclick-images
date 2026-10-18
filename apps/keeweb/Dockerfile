# KeeWeb static web app. The build context is the upstream tree at the pinned release commit, but
# the web app is not rebuilt from it: upstream's lock file does not install with `npm ci` today, so
# the stage below fetches the release's own `KeeWeb-<version>.html.zip` asset and checks it against
# a pinned SHA-256 (the value upstream publishes in the release's Verify.sha256).
# The runtime is an unprivileged nginx on alpine-slim serving the files on port 8080 over plain
# HTTP (TLS is terminated by the proxy in front); upstream's image is root nginx with a generated
# self-signed certificate and a redirect to HTTPS, which does not suit that setup.

FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS fetch
ARG KEEWEB_VERSION=1.18.7
ARG KEEWEB_SHA256=6f3d06891117072e62b43b08a84bdaf4fc43c0aae6127ac6c2e7564299d8a890
RUN apk add --no-cache curl unzip
WORKDIR /w
RUN curl -fsSL -o app.zip "https://github.com/keeweb/keeweb/releases/download/v${KEEWEB_VERSION}/KeeWeb-${KEEWEB_VERSION}.html.zip" \
 && echo "${KEEWEB_SHA256}  app.zip" | sha256sum -c - \
 && unzip -q app.zip -d site \
 && rm app.zip \
 && test -s site/index.html \
 && find site -type d -exec chmod 755 {} + && find site -type f -exec chmod 644 {} + \
 && du -sh site site/* | sort -hr | head -n 10

FROM nginxinc/nginx-unprivileged:stable-alpine-slim@sha256:4ac59c85c8c46d9e91eaabd2122cda4923ba380cf11f4138e389f069bcdc77a3

LABEL org.opencontainers.image.title="KeeWeb" \
      org.opencontainers.image.description="KeeWeb password manager web app (KeePass compatible), served by nginx" \
      org.opencontainers.image.url="https://keeweb.info" \
      org.opencontainers.image.source="https://github.com/keeweb/keeweb" \
      org.opencontainers.image.version="1.18.7" \
      org.opencontainers.image.licenses="MIT"

COPY --from=app nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -rf /usr/share/nginx/html/*
COPY --from=fetch /w/site/ /usr/share/nginx/html/

USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:8080/ || exit 1
