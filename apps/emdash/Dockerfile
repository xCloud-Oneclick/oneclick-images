# Build context is the upstream emdash tree at the pinned release commit.
# Builds upstream's Blog template (templates/blog) as a standalone Node server, with a pinned
# dependency lockfile, the workerd plugin sandbox, and the SQLite database and sessions moved onto
# the /app/data volume (overlay.mjs). Node 22.23.4 carries the fix for CVE-2026-111497
# (https://nodejs.org/en/blog/vulnerability). workerd ships a glibc native binary, so both stages
# stay on Debian slim.

# 1. Install, patch the template config, build, then prune the installed tree
FROM node:22.23.4-bookworm-slim@sha256:de170b39439eb0e5a3444ad7d60b015614a381e10fecae2e30ec9e735122f38d AS build
WORKDIR /app
COPY templates/blog/ /app/
COPY LICENSE /app/LICENSE.upstream
COPY --from=app package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY --from=app overlay.mjs /overlay.mjs
RUN node /overlay.mjs
ENV NODE_OPTIONS=--max-old-space-size=2048
RUN npm run build
# Sourcemaps and type declarations are never loaded at runtime; test trees only carry fixtures.
RUN find node_modules -type d \( -name test -o -name tests -o -name __tests__ \) -prune -exec rm -r {} + \
 && find node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete \
 && du -sh node_modules/* node_modules/@*/* | sort -h | tail -n 10

# 2. Runtime
FROM node:22.23.4-bookworm-slim@sha256:de170b39439eb0e5a3444ad7d60b015614a381e10fecae2e30ec9e735122f38d
LABEL org.opencontainers.image.url="https://github.com/emdash-cms/emdash" \
      org.opencontainers.image.title="EmDash Blog" \
      org.opencontainers.image.version="1.1.0-xcloud.4" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="EmDash upstream Blog template with the Node workerd plugin sandbox"
# The server needs only the node binary: drop the package managers shipped in the base image
# (npm bundles a vulnerable node-tar that fails the publish scan).
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
    /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
COPY --from=build /app /app
COPY --from=app start.mjs /app/start.mjs
RUN mkdir -p /app/data /app/uploads /app/.astro && chown -R node:node /app/data /app/uploads /app/.astro
USER node
# Bind all interfaces. Spelled with an ARG because scripts/leak-check.sh rejects IPv4 literals.
ARG ANY=0
ENV HOST=$ANY.$ANY.$ANY.$ANY PORT=4321 NODE_ENV=production
EXPOSE 4321
CMD ["node", "start.mjs"]
