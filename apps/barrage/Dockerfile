# Build context is the upstream barrage tree at the pinned commit (tag 0.3.0).
# Stages follow the upstream root Dockerfile unchanged; only the Node base moves from the
# EOL node:16-alpine (CVE-2026-111497, no fix) to the fixed node:22.23.4-alpine.

# Install dependencies only when needed
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi
# Upstream pins next@13.0.1, which carries CVE-2025-29927 (middleware auth bypass, CRITICAL).
# Barrage has no middleware.ts, so it isn't exploitable in this app, but the published image
# must still clear the CRITICAL gate: pull the same 13.x line's fixed patch release instead
# of upstream's package.json/lockfile.
RUN npm install next@13.5.9 --no-save

# Rebuild the source code only when needed
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
ENV NEXT_TELEMETRY_DISABLED 1

RUN npm run build
RUN du -sh .next/standalone/node_modules/* 2>/dev/null | sort -h | tail -n 8 || true

# Production image, copy all the files and run next
FROM node:22.23.4-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS runner
LABEL org.opencontainers.image.url="https://github.com/maulik9898/barrage" \
      org.opencontainers.image.title="Barrage" \
      org.opencontainers.image.version="0.3.0-xcloud.1" \
      org.opencontainers.image.licenses="MIT"
# The server needs only the node binary: drop the package managers shipped in the base image
# (npm bundles a vulnerable node-tar that fails the publish scan).
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT 3000

CMD ["node", "server.js"]
