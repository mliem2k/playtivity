#!/usr/bin/env node

/**
 * Deprecated: This script has been replaced by nightly.js
 *
 * This file now redirects to the unified nightly.js script.
 * Please update your scripts to use nightly.js directly.
 */

console.log('\n🌙 Playtivity Nightly Build System\n');
console.log('⚠️  Note: nightly-github-release.js is deprecated.\n');
console.log('Redirecting to unified nightly.js...\n');

// Redirect to new script
const { spawn } = require('child_process');
const args = process.argv.slice(2);

// The new script releases to GitHub by default, so just pass through args
const child = spawn('node', ['nightly.js', ...args], {
    stdio: 'inherit',
    shell: process.platform === 'win32'
});

child.on('exit', (code) => {
    process.exit(code || 0);
});

child.on('error', (err) => {
    console.error('\n❌ Failed to execute nightly.js:', err.message);
    console.log('\n📘 Please run nightly.js directly instead:');
    console.log('   node nightly.js\n');
    process.exit(1);
});
