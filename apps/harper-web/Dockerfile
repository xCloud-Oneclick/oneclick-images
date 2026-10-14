# Build context is the upstream Harper tree at the pinned release commit.
# Stages follow the upstream root Dockerfile; base images and the Rust toolchain are pinned.
# Everything heavy (Rust toolchain, wasm-pack, pnpm store, dev dependencies) stays in builder stages.

# 1. harper-wasm: Rust -> WebAssembly
FROM rust:1.98.1-bookworm@sha256:93ce27a88655056a51dbdd8f5f2d7ddc071c7b0070fb288a37b5a285fc83971e AS wasm-build
RUN apt-get update -y && apt-get install -y --no-install-recommends clang && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/build
COPY . .
COPY --from=app rust-toolchain.toml ./rust-toolchain.toml
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo install wasm-pack --version 0.15.0 --locked
WORKDIR /usr/build/harper-wasm
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/build/target \
    wasm-pack build --target web --out-name harper_wasm \
 && wasm-pack build --target web --out-name harper_wasm_slim --no-default-features

# 2. SvelteKit build of packages/web (adapter-node)
FROM node:24.15.0-bookworm@sha256:f22d6a1f082c02f292e86929b5b0442ac2e5eaf438a5dea9b1566601c3e05940 AS node-build
ENV npm_config_store_dir=/pnpm-store npm_config_package_import_method=copy
RUN apt-get update && apt-get install -y --no-install-recommends git parallel && rm -rf /var/lib/apt/lists/*
RUN corepack enable
WORKDIR /usr/build
COPY . .
COPY --from=wasm-build /usr/build/harper-wasm/pkg /usr/build/harper-wasm/pkg
RUN --mount=type=cache,target=/pnpm-store \
    pnpm install --engine-strict=false --shamefully-hoist
WORKDIR /usr/build/packages/components
RUN --mount=type=cache,target=/pnpm-store \
    pnpm install --engine-strict=false --shamefully-hoist && pnpm build
WORKDIR /usr/build/packages/harper.js
RUN pnpm build && ./docs.sh
WORKDIR /usr/build/packages/lint-framework
RUN pnpm build
WORKDIR /usr/build/packages/harper-editor
RUN pnpm build
WORKDIR /usr/build/packages/web
ENV ENABLE_ADMIN_ROUTES=false
RUN --mount=type=cache,target=/pnpm-store \
    pnpm install --engine-strict=false --shamefully-hoist && pnpm build

# 3. Production node_modules: only packages the built server actually imports, plus their dependencies
FROM node-build AS runtime-deps
COPY --from=app collect-runtime-deps.mjs /tmp/collect-runtime-deps.mjs
RUN node /tmp/collect-runtime-deps.mjs /usr/build/packages/web/build /out \
    /usr/build/packages/web/node_modules /usr/build/node_modules \
 && find /out/node_modules -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' \) -delete \
 && du -sh /out/node_modules/* /out/node_modules/@*/* | sort -h | tail -n 8

# 3b. Built server without sourcemaps and gzip copies (the .br copies stay and are served to every modern browser)
FROM node-build AS web-out
WORKDIR /usr/build/packages/web
RUN cp -a build /out && find /out -type f \( -name '*.map' -o -name '*.gz' \) -delete \
 && cd /out && du -sh * client/* | sort -h | tail -n 15 \
 && find . -type f -size +3M -exec ls -l {} + | awk '{print $5, $9}' | sort -n | tail -n 25

# 4. Runtime: built server, production modules, package.json
FROM node:24.15.0-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f
LABEL org.opencontainers.image.url="https://github.com/Automattic/harper" \
      org.opencontainers.image.title="Harper web editor" \
      org.opencontainers.image.version="2.12.0-xcloud.1" \
      org.opencontainers.image.licenses="Apache-2.0"
WORKDIR /app
COPY --from=runtime-deps /out/node_modules ./node_modules
COPY --from=web-out /out ./build
COPY --from=node-build /usr/build/packages/web/drizzle ./build/drizzle
COPY --from=node-build /usr/build/packages/web/package.json ./package.json
COPY --from=node-build /usr/build/LICENSE ./LICENSE.upstream
WORKDIR /app/build
USER node
ENV PORT=3000 NODE_ENV=production
EXPOSE 3000
ENTRYPOINT ["node", "index"]
