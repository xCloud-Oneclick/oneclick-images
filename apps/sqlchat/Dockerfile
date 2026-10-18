# Build context is the upstream SQL Chat tree at the pinned commit (upstream publishes no release tags).
# Stages follow the upstream Dockerfile (pnpm install, prisma generate, next build with output: "standalone");
# the base image is pinned by digest and the pnpm version is pinned.
# Like the upstream image, it is built without NEXT_PUBLIC_USE_DATABASE (database-less mode).
# Dependency bumps (only change vs upstream): the locked next 13.5.6, next-auth 4.24.7 and form-data 4.0.0 carry
# CRITICAL advisories whose fixes exist only in newer releases (next 13 is end-of-life), so they are pinned to
# patched versions at build time and the lockfile is regenerated.

# 1. Build: dependencies, prisma client, Next.js standalone output
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS build
RUN apk add --no-cache libc6-compat openssl
RUN npm install -g pnpm@9.15.9
ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /app
COPY . .
RUN node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('package.json'));\
p.dependencies.next='15.5.24';p.dependencies['next-auth']='4.24.15';\
p.pnpm={overrides:{'form-data@>=4.0.0 <4.0.4':'4.0.4'}};\
fs.writeFileSync('package.json',JSON.stringify(p,null,2))"
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --no-frozen-lockfile
# next build lints with the old eslint-config-next; lint is not part of the image
RUN sed -i 's/typescript: {/eslint: { ignoreDuringBuilds: true },\n  typescript: {/' next.config.js \
 && grep -q ignoreDuringBuilds next.config.js
RUN pnpm run build

# 2. Slim the standalone tree: no sourcemaps, type declarations, database CLI engines, or sharp/typescript
#    (the app does not use next/image, and next.config is plain JS)
FROM build AS slim
RUN cp -a .next/standalone /out && cp -a .next/static /out/.next/static && cp -a public /out/public \
 && find /out -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete \
 && find /out -type f \( -name 'migration-engine*' -o -name 'schema-engine*' -o -name 'introspection-engine*' -o -name 'prisma-fmt*' \) -delete \
 && find /out -type f \( -name '.env*' -o -name '*.md' \) -delete \
 && rm -rf /out/node_modules/.pnpm/@img+* /out/node_modules/.pnpm/sharp@* /out/node_modules/sharp /out/node_modules/@img \
    /out/node_modules/.pnpm/typescript@* /out/node_modules/typescript \
 && du -sh /out/* /out/node_modules/.pnpm/* 2>/dev/null | sort -h | tail -n 15

# 3. Runtime: plain alpine plus the distro nodejs package (no npm, corepack or yarn)
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
LABEL org.opencontainers.image.url="https://github.com/sqlchat/sqlchat" \
      org.opencontainers.image.title="SQL Chat" \
      org.opencontainers.image.version="main-7a63884-xcloud.1" \
      org.opencontainers.image.licenses="MIT"
# openssl: needed by the Prisma query engine.
RUN apk add --no-cache nodejs openssl \
 && adduser -D -u 1000 node
WORKDIR /app
COPY --from=slim --chown=node:node /out ./
COPY --from=build /app/LICENSE ./LICENSE.upstream
USER node
# HOSTNAME=0 binds all IPv4 interfaces (Docker sets HOSTNAME to the container id, which the server would otherwise bind to)
ENV NODE_ENV=production PORT=3000 HOSTNAME=0 NEXT_TELEMETRY_DISABLED=1
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["node", "-e", "fetch('http://localhost:3000/api/ping').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
CMD ["node", "server.js"]
