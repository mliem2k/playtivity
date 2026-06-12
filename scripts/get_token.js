#!/usr/bin/env node
// Fetches a Spotify web-player JWT access token using an sp_dc cookie.
// Mirrors SpotifyTokenService + SpotifyTotpHelper from the Flutter app.
//
// Usage:
//   node scripts/get_token.js <sp_dc_value>
//   node scripts/get_token.js   (reads SP_DC from .env or environment)

const https = require('https');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// --- TOTP secrets (same as SpotifyTotpHelper.secretCipherDict) ---
const SECRET_CIPHER_DICT = {
  '59': [123,105,79,70,110,59,52,125,60,49,80,70,89,75,80,86,63,53,123,37,117,49,52,93,77,62,47,86,48,104,68,72],
  '60': [79,109,69,123,90,65,46,74,94,34,58,48,70,71,92,85,122,63,91,64,87,87],
  '61': [44,55,47,42,70,40,34,114,76,74,50,111,120,97,75,76,94,102,43,69,49,120,118,80,64,78],
};

function activeVersion(dict) {
  return String(Math.max(...Object.keys(dict).map(Number)));
}

function asciiToHex(str) {
  return Array.from(str).map(c => c.charCodeAt(0).toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex) {
  const bytes = [];
  for (let i = 0; i < hex.length; i += 2) bytes.push(parseInt(hex.slice(i, i + 2), 16));
  return bytes;
}

function base32Encode(hexStr) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bytes = hexToBytes(hexStr);
  let result = '';
  for (let i = 0; i < bytes.length; i += 5) {
    const block = [0, 0, 0, 0, 0];
    for (let j = 0; j < 5 && i + j < bytes.length; j++) block[j] = bytes[i + j];
    let n = BigInt(0);
    for (let j = 0; j < 5; j++) n = (n << 8n) | BigInt(block[j]);
    for (let j = 7; j >= 0; j--) {
      result += alphabet[Number((n >> BigInt(j * 5)) & 31n)];
    }
  }
  return result.replace(/=+$/, '');
}

function intToBytes(value) {
  return [0, 0, 0, 0,
    (value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

function base32DecodeToBytes(encoded) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const buf = [];
  let bits = 0, value = 0;
  for (const char of encoded.toUpperCase()) {
    const idx = alphabet.indexOf(char);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) { buf.push((value >> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(buf);
}

function generateTotp(timestampMs) {
  const seconds = Math.floor(timestampMs / 1000);
  const ver = activeVersion(SECRET_CIPHER_DICT);
  const cipherBytes = SECRET_CIPHER_DICT[ver];
  const transformed = cipherBytes.map((b, i) => b ^ ((i % 33) + 9));
  const joined = transformed.join('');
  const hexStr = asciiToHex(joined);
  const secret = base32Encode(hexStr);

  const timeStep = Math.floor(seconds / 30);
  const key = base32DecodeToBytes(secret);
  const msg = Buffer.from(intToBytes(timeStep));
  const hmac = crypto.createHmac('sha1', key).update(msg).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code = (
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff)
  ) % 1_000_000;
  return { totp: String(code).padStart(6, '0'), totpVer: ver };
}

function fetchServerTime() {
  return new Promise((resolve) => {
    const req = https.get('https://open.spotify.com/', { timeout: 10000 }, (res) => {
      res.resume();
      const dateStr = res.headers['date'];
      resolve(dateStr ? new Date(dateStr).getTime() : Date.now());
    });
    req.on('error', () => resolve(Date.now()));
    req.on('timeout', () => { req.destroy(); resolve(Date.now()); });
  });
}

function httpsGet(url, headers) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers, timeout: 15000 }, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

function loadEnv() {
  try {
    const envPath = path.join(__dirname, '..', '.env');
    const lines = fs.readFileSync(envPath, 'utf8').split('\n');
    for (const line of lines) {
      const m = line.match(/^([^=]+)=(.*)$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
    }
  } catch (_) {}
}

async function main() {
  loadEnv();

  const spDc = process.argv[2] || process.env.SP_DC || process.env.sp_dc;
  if (!spDc) {
    console.error('Usage: node scripts/get_token.js <sp_dc_value>');
    console.error('   or: set SP_DC in .env');
    process.exit(1);
  }

  const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

  console.error('Fetching server time...');
  const serverTime = await fetchServerTime();
  const { totp, totpVer } = generateTotp(serverTime);
  console.error(`TOTP ver=${totpVer} code=${totp}`);

  const tokenUrl = `https://open.spotify.com/api/token?reason=transport&productType=web-player&totp=${totp}&totpServer=${totp}&totpVer=${totpVer}`;

  console.error('Fetching JWT access token...');
  const { status, body } = await httpsGet(tokenUrl, {
    'Cookie': `sp_dc=${spDc}`,
    'User-Agent': USER_AGENT,
    'Accept': 'application/json',
    'App-Platform': 'WebPlayer',
    'Content-Type': 'application/json',
    'Referer': 'https://open.spotify.com/',
    'Origin': 'https://open.spotify.com',
  });

  if (status !== 200) {
    console.error(`Token endpoint returned HTTP ${status}`);
    console.error(body);
    process.exit(1);
  }

  const data = JSON.parse(body);
  if (data.isAnonymous) {
    console.error('Got anonymous token — sp_dc is expired or invalid.');
    process.exit(1);
  }

  const token = data.accessToken;
  if (!token) {
    console.error('No accessToken in response:', body);
    process.exit(1);
  }

  // Verify it looks like a JWT (3 dot-separated parts)
  const parts = token.split('.');
  if (parts.length === 3) {
    console.error('JWT confirmed (3 parts)');
    try {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
      console.error(`User: ${payload.sub || '(unknown)'}, expires: ${new Date((payload.exp || 0) * 1000).toISOString()}`);
    } catch (_) {}
  } else {
    console.error(`Warning: token has ${parts.length} parts (expected 3 for JWT)`);
  }

  // Write to .env
  const envPath = path.join(__dirname, '..', '.env');
  let envContent = '';
  try { envContent = fs.readFileSync(envPath, 'utf8'); } catch (_) {}
  const newLine = `SPOTIFY_BEARER=${token}`;
  if (envContent.match(/^SPOTIFY_BEARER=.*/m)) {
    envContent = envContent.replace(/^SPOTIFY_BEARER=.*/m, newLine);
  } else {
    envContent = (envContent.trimEnd() + '\n' + newLine + '\n').trimStart();
  }
  fs.writeFileSync(envPath, envContent);
  console.error('.env updated with new JWT token.');

  // Print the token to stdout for piping
  console.log(token);
}

main().catch(e => { console.error(e); process.exit(1); });
