# Build context is the upstream invoice-builder tree at the pinned release commit.
# Stages follow the upstream Dockerfile; base images are pinned. Toolchains, devDependencies and
# sources stay in builder stages, and the runtime carries no package manager.

# 1. Build the frontend, server and migrations (full install: the build scripts call root devDependencies)
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS builder
# python3/make/g++ only matter when sqlite3 has no prebuilt binary for the architecture
RUN apk add --no-cache python3 make g++
WORKDIR /app
COPY package.json package-lock.json* ./
COPY packages/contracts/package.json ./packages/contracts/
COPY packages/core/package.json ./packages/core/
COPY apps/renderer/package.json ./apps/renderer/
COPY apps/server/package.json ./apps/server/
COPY apps/desktop/package.json ./apps/desktop/
COPY apps/website/package.json ./apps/website/
COPY scripts/postinstall.cjs ./scripts/postinstall.cjs
ENV SKIP_ELECTRON_REBUILD=true
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build:renderer && npm run build:webserver && npm run build:migrations
# Browsers negotiate precompressed assets only if the server does; nginx here does not, so keep plain files
RUN find dist-renderer -type f \( -name '*.map' -o -name '*.gz' -o -name '*.br' \) -delete \
 && du -sh dist-renderer dist-server dist-migrations packages/*/dist

# 2. Production dependencies of the server workspace only
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS deps
RUN apk add --no-cache python3 make g++
WORKDIR /app
COPY --from=builder /app/package.json /app/package-lock.json ./
COPY --from=builder /app/packages/contracts/package.json /app/packages/contracts/package.json
COPY --from=builder /app/packages/contracts/dist /app/packages/contracts/dist
COPY --from=builder /app/packages/core/package.json /app/packages/core/package.json
COPY --from=builder /app/packages/core/dist /app/packages/core/dist
COPY --from=builder /app/apps/server/package.json /app/apps/server/package.json
COPY scripts/postinstall.cjs ./scripts/postinstall.cjs
ENV SKIP_ELECTRON_REBUILD=true
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev --workspace @invoice-builder/server
# sqlite3 keeps its C sources and the install-time helpers are not needed at runtime
RUN rm -rf node_modules/sqlite3/deps node_modules/sqlite3/src node_modules/sqlite3/build/Release/obj* \
           node_modules/sqlite3/build/Release/.deps node_modules/sqlite3/build/deps \
 && find node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete \
 && du -sh node_modules/* node_modules/@*/* | sort -h | tail -n 8

# 3. Runtime: nginx serves the frontend and proxies /api to the node backend (SERVICE=all)
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914
LABEL org.opencontainers.image.url="https://github.com/piratuks/invoice-builder" \
      org.opencontainers.image.title="Invoice Builder" \
      org.opencontainers.image.version="3.1.2-xcloud.2" \
      org.opencontainers.image.licenses="MIT"
# gettext provides envsubst for the nginx config template. The server needs only the node binary,
# so the package managers shipped in the base image are removed (npm bundles a vulnerable node-tar).
RUN apk add --no-cache nginx gettext-envsubst \
 && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg \
 && rm -f /etc/nginx/http.d/default.conf \
 && mkdir -p /app-data /run/nginx /var/lib/nginx/tmp /var/log/nginx /etc/nginx/http.d \
 && chown -R node:node /app-data /run/nginx /var/lib/nginx /var/log/nginx /etc/nginx/http.d
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages ./packages
COPY --from=deps /app/apps ./apps
COPY --from=deps /app/package.json /app/package-lock.json ./
COPY --from=builder /app/dist-renderer ./dist-renderer
COPY --from=builder /app/dist-server ./dist-server
COPY --from=builder /app/dist-migrations ./dist-migrations
COPY --from=builder /app/LICENSE ./LICENSE.upstream
COPY scripts/docker-start.sh scripts/nginx.conf.template ./scripts/
RUN sed -i 's/\r$//' scripts/docker-start.sh
USER node
# Single container: the backend listens on localhost:3000 and nginx on 3001
ENV SERVICE=all \
    NODE_ENV=docker \
    DB_DIRECTORY=/app-data \
    PORT=3000 \
    DEV_SERVER_URL=localhost \
    FE_SERVER_URL=http://localhost:3001 \
    MIGRATIONS_PATH=/app/dist-migrations \
    BACKEND_HOST=localhost \
    BACKEND_PORT=3000
VOLUME ["/app-data"]
EXPOSE 3001
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["node", "-e", "require('http').get({host:'localhost',port:3001,path:'/api/health',family:4},r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]
CMD ["sh", "/app/scripts/docker-start.sh"]
