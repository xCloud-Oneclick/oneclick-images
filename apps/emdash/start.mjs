import { spawn } from 'node:child_process';
const hex = process.env.EMDASH_ENCRYPTION_KEY_HEX;
if (!hex || !/^[a-f0-9]{64}$/.test(hex)) throw new Error('EMDASH_ENCRYPTION_KEY_HEX must be 64 lowercase hex characters');
process.env.EMDASH_ENCRYPTION_KEY = 'emdash_enc_v1_' + Buffer.from(hex, 'hex').toString('base64url');
delete process.env.EMDASH_ENCRYPTION_KEY_HEX;
const child = spawn(process.execPath, ['./dist/server/entry.mjs'], { stdio: 'inherit', env: process.env });
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => child.kill(signal));
child.on('exit', (code) => process.exit(code ?? 1));
