#!/bin/sh
# Same steps as upstream's scripts/start.sh, without yarn, npx or turbo.
set -eu
cd /calcom

# Replace the statically built BUILT_NEXT_PUBLIC_WEBAPP_URL with the run-time NEXT_PUBLIC_WEBAPP_URL.
# The script does nothing when both values are the same.
sh scripts/replace-placeholder.sh "$BUILT_NEXT_PUBLIC_WEBAPP_URL" "$NEXT_PUBLIC_WEBAPP_URL"

# Wait for the database from DATABASE_URL to accept connections (up to two minutes).
node -e '
const net = require("net");
const url = new URL(process.env.DATABASE_URL);
const port = Number(url.port) || 5432;
let tries = 0;
(function attempt() {
  const socket = net.connect(port, url.hostname);
  socket.on("connect", () => { socket.end(); console.log("database is up"); });
  socket.on("error", () => {
    socket.destroy();
    if (++tries >= 60) { console.error("database is not reachable"); process.exit(1); }
    setTimeout(attempt, 2000);
  });
})();
'

node node_modules/prisma/build/index.js migrate deploy --schema packages/prisma/schema.prisma
node node_modules/ts-node/dist/bin.js --transpile-only scripts/seed-app-store.ts || echo "app store seed failed; continuing"

cd apps/web
exec node ../../node_modules/next/dist/bin/next start
