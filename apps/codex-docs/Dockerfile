# Build context is the upstream codex.docs tree at the pinned release commit.
# Follows upstream docker/Dockerfile.prod (yarn install, yarn build-all, production node_modules),
# on a maintained Node LTS instead of the end-of-life Node 16 / Alpine 3.15 upstream pins.
# The toolchain, dev dependencies and sources stay in builder stages.

# 1. Frontend (webpack) and backend (tsc) build
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS build
WORKDIR /usr/src/app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --ignore-engines
COPY . .
RUN yarn build-all

# 2. Production node_modules only, pruned of types, sourcemaps, docs and tests
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS deps
WORKDIR /usr/src/app
COPY package.json yarn.lock ./
RUN yarn install --production --frozen-lockfile --ignore-engines
RUN rm -rf node_modules/@types \
 && find node_modules -type d \( -name test -o -name tests -o -name __tests__ -o -name docs -o -name example -o -name examples \) -prune -exec rm -rf {} + \
 && find node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.md' -o -name '*.markdown' -o -name 'CHANGELOG*' \) -delete \
 && du -sh node_modules/* node_modules/@*/* | sort -h | tail -n 8

# 3. Runtime
FROM node:22.23.3-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
LABEL org.opencontainers.image.url="https://github.com/codex-team/codex.docs" \
      org.opencontainers.image.title="CodeX Docs" \
      org.opencontainers.image.version="2.2.5-xcloud.1" \
      org.opencontainers.image.licenses="Apache-2.0"
# The server needs only the node binary: drop the package managers shipped in the base image
# (npm bundles a vulnerable node-tar that fails the publish scan).
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /usr/src/app
COPY --from=deps /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/dist ./dist
COPY --from=build /usr/src/app/public ./public
COPY --from=build /usr/src/app/package.json ./package.json
# The server reads ./docs-config.yaml at start and fails without it; upstream expects it to be
# mounted. An empty default keeps the built-in defaults; mount a file over it or use APP_CONFIG_* env.
RUN echo '{}' > docs-config.yaml \
 && mkdir -p db uploads \
 && chown -R node:node db uploads docs-config.yaml
USER node
ENV NODE_ENV=production
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/').then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/backend/app.js"]
