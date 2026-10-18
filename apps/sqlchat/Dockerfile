# Build context is the upstream SQL Chat tree at the pinned commit (upstream publishes no release tags).
# Stages follow the upstream Dockerfile (pnpm install, prisma generate, next build with output: "standalone");
# the base image is pinned by digest and the pnpm version is pinned.
# Like the upstream image, it is built without NEXT_PUBLIC_USE_DATABASE (database-less mode).

# 1. Build: dependencies, prisma client, Next.js standalone output
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS build
RUN apk add --no-cache libc6-compat openssl
RUN npm install -g pnpm@9.15.9
ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

# 2. Slim the standalone tree: no sourcemaps, type declarations or database CLI engines
FROM build AS slim
RUN cp -a .next/standalone /out && cp -a .next/static /out/.next/static && cp -a public /out/public \
 && find /out -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete \
 && find /out -type f \( -name 'migration-engine*' -o -name 'schema-engine*' -o -name 'introspection-engine*' -o -name 'prisma-fmt*' \) -delete \
 && find /out -type f \( -name '.env*' -o -name '*.md' \) -delete \
 && du -sh /out/* /out/node_modules/.pnpm/* 2>/dev/null | sort -h | tail -n 15

# 3. Runtime
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
LABEL org.opencontainers.image.url="https://github.com/sqlchat/sqlchat" \
      org.opencontainers.image.title="SQL Chat" \
      org.opencontainers.image.version="main-7a63884-xcloud.1" \
      org.opencontainers.image.licenses="MIT"
# openssl: needed by the Prisma query engine. The server needs only the node binary:
# drop the package managers shipped in the base image (npm bundles a vulnerable node-tar).
RUN apk add --no-cache openssl \
 && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
COPY --from=slim --chown=node:node /out ./
COPY --from=build /app/LICENSE ./LICENSE.upstream
USER node
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0 NEXT_TELEMETRY_DISABLED=1
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/api/ping').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
CMD ["node", "server.js"]
