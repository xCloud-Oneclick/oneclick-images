// Usage: node collect-runtime-deps.mjs <build-dir> <out-dir> <node_modules-dir>...
// Finds the packages the built adapter-node server imports (everything the bundler left external),
// then copies those packages and their dependencies from the already-installed node_modules.
import fs from 'node:fs';
import path from 'node:path';
import { builtinModules } from 'node:module';

const [buildDir, outDir, ...modulesDirs] = process.argv.slice(2);
const builtins = new Set(builtinModules);
const clientDir = path.join(buildDir, 'client');
const specifier = /(?:\bfrom|\bimport)\s*\(?\s*["']([^"'./][^"']*)["']/g;

function* sources(dir) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const file = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (file !== clientDir) yield* sources(file);
		} else if (/\.(m?js|cjs)$/.test(entry.name)) {
			yield file;
		}
	}
}

function packageName(spec) {
	const parts = spec.split('/');
	return spec.startsWith('@') ? parts.slice(0, 2).join('/') : parts[0];
}

function locate(name) {
	return modulesDirs.map((dir) => path.join(dir, name)).find((dir) => fs.existsSync(path.join(dir, 'package.json')));
}

const queue = [];
for (const file of sources(buildDir)) {
	for (const match of fs.readFileSync(file, 'utf8').matchAll(specifier)) {
		const spec = match[1];
		if (spec.startsWith('node:') || builtins.has(spec) || builtins.has(packageName(spec))) continue;
		queue.push(packageName(spec));
	}
}
console.log('imported by the server bundle:', [...new Set(queue)].sort().join(' '));

// Optional peers (for example mysql2 for drizzle-orm) are only installed by the app itself.
const appDependencies = new Set(
	Object.keys(JSON.parse(fs.readFileSync(path.join(buildDir, '..', 'package.json'), 'utf8')).dependencies ?? {}),
);

const copied = new Map();
while (queue.length) {
	const name = queue.pop();
	if (copied.has(name)) continue;
	const dir = locate(name);
	if (!dir) {
		console.warn('not installed, skipped:', name);
		continue;
	}
	copied.set(name, dir);
	const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
	queue.push(...Object.keys({ ...manifest.dependencies, ...manifest.optionalDependencies }));
	queue.push(...Object.keys(manifest.peerDependencies ?? {}).filter((peer) => appDependencies.has(peer)));
}

for (const [name, dir] of copied) {
	fs.cpSync(dir, path.join(outDir, 'node_modules', name), { recursive: true, dereference: true });
}
console.log(`copied ${copied.size} packages`);
