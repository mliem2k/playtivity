#!/usr/bin/env node

// This script has been replaced by the unified nightly.js
console.log(`
⚠️  This script is deprecated!

Please use the new unified nightly builder instead:

  node nightly.js              # Build and release to GitHub
  node nightly.js --skip-github # Local build only  
  node nightly.js --help        # Show all options

Or use npm scripts:
  npm run nightly       # Build and release to GitHub
  npm run nightly:local # Local build only

The new script combines building and GitHub release in one command.
`);

// Redirect to new script with --skip-github flag for backward compatibility
const { spawn } = require('child_process');
const args = process.argv.slice(2);

// Add --skip-github flag to maintain old behavior (local only)
if (!args.includes('--help') && !args.includes('-h')) {
    args.push('--skip-github');
}

const child = spawn('node', ['nightly.js', ...args], {
    stdio: 'inherit',
    shell: true
});

child.on('exit', (code) => {
    process.exit(code);
});