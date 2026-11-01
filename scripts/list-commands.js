#!/usr/bin/env bun

const fs = require('fs');
const path = require('path');
const scripts = require('../package.json').scripts;

console.log('Playtivity commands');
for (const [name, command] of Object.entries(scripts)) {
    console.log(`  bun run ${name.padEnd(24)} ${command}`);
}

const versionFile = path.join(__dirname, '..', 'version.yml');
const version = fs.readFileSync(versionFile, 'utf8').match(/^version:\s*(.+)$/m)?.[1];
if (version) console.log(`\nCurrent version: ${version}`);
console.log('\nRequirements: Bun, JDK 21, Android SDK. Production builds also need a release keystore.');
