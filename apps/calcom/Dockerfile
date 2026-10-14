# Build context is the upstream Cal.diy tree at the pinned release commit.
# The builder stage is upstream's root Dockerfile with the base image pinned by digest and the build
# arguments that upstream's release workflow passes (public web URL, API URL, consent) as defaults.
# builder-two removes what `next start` does not need (source maps, the standalone copy, type
# declarations, build and test tooling). The runtime stage is a slim, pinned base that runs as the
# unprivileged `node` user, without npm, yarn or corepack. apps/calcom/start.sh replaces upstream's
# scripts/start.sh with the same steps (rewrite the public URL, migrate, seed the app store, start the
# server) and no yarn, npx or turbo.

FROM --platform=$BUILDPLATFORM node:20@sha256:8f693eaa7e0a8e71560c9a82b55fd54c2ae920a2ba5d2cde28bac7d1c01c9ba5 AS builder

WORKDIR /calcom

## If we want to read any ENV variable from .env file, we need to first accept and pass it as an argument to the Dockerfile
ARG NEXT_PUBLIC_LICENSE_CONSENT=agree
ARG NEXT_PUBLIC_WEBSITE_TERMS_URL
ARG NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL
ARG CALCOM_TELEMETRY_DISABLED
ARG DATABASE_URL=postgresql://build:build@localhost:5432/calendso
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret
ARG MAX_OLD_SPACE_SIZE=6144
ARG NEXT_PUBLIC_API_V2_URL=http://localhost:5555/api/v2
ARG CSP_POLICY

## We need these variables as required by Next.js build to create rewrites
ARG NEXT_PUBLIC_SINGLE_ORG_SLUG
ARG ORGANIZATIONS_ENABLED

ENV NEXT_PUBLIC_WEBAPP_URL=http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER \
  NEXT_PUBLIC_API_V2_URL=$NEXT_PUBLIC_API_V2_URL \
  NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
  NEXT_PUBLIC_WEBSITE_TERMS_URL=$NEXT_PUBLIC_WEBSITE_TERMS_URL \
  NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL=$NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL \
  CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
  DATABASE_URL=$DATABASE_URL \
  DATABASE_DIRECT_URL=$DATABASE_URL \
  NEXTAUTH_SECRET=${NEXTAUTH_SECRET} \
  CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY} \
  NEXT_PUBLIC_SINGLE_ORG_SLUG=$NEXT_PUBLIC_SINGLE_ORG_SLUG \
  ORGANIZATIONS_ENABLED=$ORGANIZATIONS_ENABLED \
  NODE_OPTIONS=--max-old-space-size=${MAX_OLD_SPACE_SIZE} \
  BUILD_STANDALONE=true \
  CSP_POLICY=$CSP_POLICY

COPY package.json yarn.lock .yarnrc.yml playwright.config.ts turbo.json i18n.json ./
COPY .yarn ./.yarn
COPY apps/web ./apps/web
COPY apps/api/v2 ./apps/api/v2
COPY packages ./packages

RUN yarn config set httpTimeout 1200000
RUN npx turbo prune --scope=@calcom/web --scope=@calcom/trpc --docker
RUN yarn install
# Build and make embed servable from web/public/embed folder
RUN yarn workspace @calcom/trpc run build
RUN yarn --cwd packages/embeds/embed-core workspace @calcom/embed-core run build
RUN yarn --cwd apps/web workspace @calcom/web run copy-app-store-static
RUN yarn --cwd apps/web workspace @calcom/web run build
RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache

FROM node:20@sha256:8f693eaa7e0a8e71560c9a82b55fd54c2ae920a2ba5d2cde28bac7d1c01c9ba5 AS builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000

ENV NODE_ENV=production

COPY package.json .yarnrc.yml turbo.json i18n.json ./
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages
COPY --from=builder /calcom/apps/web ./apps/web
COPY --from=builder /calcom/packages/prisma/schema.prisma ./prisma/schema.prisma
COPY scripts scripts
COPY --from=app start.sh scripts/start.sh
RUN chmod +x scripts/*

# Save value used during this build stage. If NEXT_PUBLIC_WEBAPP_URL and BUILT_NEXT_PUBLIC_WEBAPP_URL differ at
# run-time, start.sh will find/replace static values again.
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
  BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

RUN sh scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}

# The runtime needs the built app, `next start`, prisma migrate and ts-node (for the app store seed).
# Source maps, the standalone copy of the server, type declarations, end-to-end tests and build/test
# tooling are not used.
RUN rm -rf apps/web/.next/standalone apps/web/.next/cache apps/web/.next/trace apps/web/playwright \
 && find apps/web packages -type f \( -name '*.e2e.ts' -o -name '*.e2e.tsx' \) -not -path '*/node_modules/*' -delete \
 && find apps/web/.next -type f -name '*.map' -delete \
 && find node_modules packages -type f \( -name '*.js.map' -o -name '*.mjs.map' -o -name '*.cjs.map' -o -name '*.css.map' -o -name '*.d.ts.map' \) -delete \
 && find node_modules -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -not -path '*/typescript/*' -delete \
 && rm -rf node_modules/@types \
 && for p in @biomejs lingo.dev trigger.dev @trigger.dev/build @trigger.dev/schema-to-json prismock @depot @nestjs/cli \
      @microsoft/api-extractor react-devtools-core vite playwright playwright-core @playwright; do rm -rf "node_modules/$p"; done \
 && find /calcom -type d \( -name 'turbo' -o -name 'turbo-linux-*' \) -path '*/node_modules/*' -prune -exec rm -rf {} + \
 && rm -f node_modules/.bin/turbo

FROM node:20-slim@sha256:2cf067cfed83d5ea958367df9f966191a942351a2df77d6f0193e162b5febfc0 AS runner

LABEL org.opencontainers.image.url="https://github.com/calcom/cal.diy" \
      org.opencontainers.image.title="Cal.diy" \
      org.opencontainers.image.version="6.2.0-xcloud.1" \
      org.opencontainers.image.licenses="AGPL-3.0"

# openssl is needed by the prisma schema engine. The package managers shipped in the base image are not
# needed to run the app (npm bundles libraries that trip the vulnerability scan).
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/* /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /calcom

COPY --from=builder-two --chown=node:node /calcom/package.json /calcom/turbo.json /calcom/i18n.json ./
COPY --from=builder-two --chown=node:node /calcom/node_modules ./node_modules
COPY --from=builder-two --chown=node:node /calcom/packages ./packages
COPY --from=builder-two --chown=node:node /calcom/apps/web ./apps/web
COPY --from=builder-two --chown=node:node /calcom/prisma ./prisma
COPY --from=builder-two --chown=node:node /calcom/scripts ./scripts

ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ENV NODE_ENV=production \
  NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
  BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

USER node
EXPOSE 3000

CMD ["/calcom/scripts/start.sh"]
