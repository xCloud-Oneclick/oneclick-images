import fs from 'node:fs';
const path = '/app/astro.config.mjs';
let config = fs.readFileSync(path, 'utf8');
if (!config.includes('file:./data.db')) throw new Error('Upstream SQLite config changed');
config = config.replace('file:./data.db', 'file:./data/data.db');
config = config.replace('defineConfig, fontProviders', 'defineConfig, fontProviders, sessionDrivers');
config = config.replace('output: "server",', `output: "server",
    session: { driver: sessionDrivers.fsLite({ base: "/app/data/sessions" }) },`);
config = config.replace('emdash({', 'emdash({\n            sandboxRunner: "@emdash-cms/sandbox-workerd/sandbox",');
fs.writeFileSync(path, config);
