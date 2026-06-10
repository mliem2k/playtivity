/**
 * Spotify Dealer WebSocket — friend activity push test
 *
 * Spotify's web player doesn't poll /presence-view/v1/buddylist on a timer.
 * Instead it holds open a WebSocket to dealer.spotify.com and receives push
 * notifications when friend activity changes.
 *
 * Flow:
 *   1. Connect to wss://dealer.spotify.com/?access_token=TOKEN
 *   2. Receive welcome frame → extract Spotify-Connection-Id
 *   3. PUT /presence-view/v1/buddylist/subscribe?connection_id=ID
 *      to tell spclient "push updates to this dealer connection"
 *   4. Receive push frames on the WebSocket whenever a friend's activity changes
 *
 * Run: node tool/test_dealer_ws.mjs
 */

import https from 'https';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const WebSocketClient = require('ws');

const TOKEN = process.env.SPOTIFY_TOKEN || 'PASTE_FRESH_TOKEN_HERE';

const DEALER_HOST = 'dealer.spotify.com';
const SPCLIENT_HOST = 'guc-spclient.spotify.com';

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

// ── helpers ──────────────────────────────────────────────────────────────────

function log(tag, ...args) {
  const ts = new Date().toISOString().slice(11, 23);
  console.log(`[${ts}] ${tag}`, ...args);
}

function put(host, path) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: host,
      path,
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        'Accept': 'application/json',
        'App-Platform': 'WebPlayer',
        'Origin': 'https://open.spotify.com',
        'User-Agent': USER_AGENT,
        'Content-Length': 0,
      },
    }, res => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.end();
  });
}

// ── dealer WebSocket ──────────────────────────────────────────────────────────

const url = `wss://${DEALER_HOST}/?access_token=${TOKEN}`;
log('CONNECT', url.slice(0, 80) + '…');

const ws = new WebSocketClient(url, {
  headers: {
    Origin: 'https://open.spotify.com',
    'User-Agent': USER_AGENT,
  },
});

let connId = null;
let subscribed = false;
let messageCount = 0;

ws.addEventListener('open', () => {
  log('WS', 'connected');
});

ws.addEventListener('message', async ({ data }) => {
  let msg;
  try { msg = JSON.parse(data); } catch { log('WS', 'non-JSON frame:', data); return; }

  messageCount++;

  // ── Welcome frame ──
  const incomingConnId = msg?.headers?.['Spotify-Connection-Id'];
  if (incomingConnId && !connId) {
    connId = incomingConnId;
    log('WS', `got connection-id: ${connId}`);

    if (!subscribed) {
      subscribed = true;
      await tryAllSubscriptions(connId);
    }
    return;
  }

  // ── Ping frame ──
  if (msg?.type === 'ping') {
    ws.send(JSON.stringify({ type: 'pong' }));
    return;
  }

  // ── Any other frame — log it fully ──
  log('PUSH', `frame #${messageCount}`);
  console.log(JSON.stringify(msg, null, 2));
});

ws.addEventListener('close', ({ code, reason }) => {
  log('WS', `closed — code=${code} reason=${reason || '(none)'}`);
});

ws.addEventListener('error', ({ message }) => {
  log('WS', 'error:', message);
});

async function tryAllSubscriptions(id) {
  const encoded = encodeURIComponent(id);

  // 1. Try REST PUT subscription endpoints
  const candidates = [
    { host: 'guc-spclient.spotify.com', path: `/presence-view/v1/buddylist/subscribe?connection_id=${encoded}` },
    { host: 'spclient.wg.spotify.com',  path: `/presence-view/v1/buddylist/subscribe?connection_id=${encoded}` },
    { host: 'guc-spclient.spotify.com', path: `/presence-view/v1/subscribe?connection_id=${encoded}` },
  ];

  for (const { host, path } of candidates) {
    try {
      const { status, body } = await put(host, path);
      log('REST-SUB', `${status} ← PUT https://${host}${path.split('?')[0]}`);
      if (status === 200 || status === 204) {
        log('REST-SUB', '✅ accepted'); return;
      }
    } catch (e) { log('REST-SUB', `error: ${e.message}`); }
  }

  // 2. Try subscribing via WebSocket message (Hermes/hm:// style)
  const wsSubs = [
    { type: 'subscribe', uri: 'hm://presence-view/v1/buddylist' },
    { type: 'subscribe', uri: 'hm://pusher/v1/connections/' + id + '/subscribe/hm://presence-view/v1/buddylist' },
  ];
  for (const sub of wsSubs) {
    log('WS-SUB', 'sending:', JSON.stringify(sub));
    ws.send(JSON.stringify(sub));
    await new Promise(r => setTimeout(r, 500));
  }

  // 3. Try streaming GET (SSE / chunked) on buddylist endpoint
  log('SSE', 'trying streaming GET on buddylist…');
  trySseStream();

  log('PASSIVE', 'listening — trigger a push by having a friend change tracks');
}

function trySseStream() {
  const req = https.request({
    hostname: SPCLIENT_HOST,
    path: '/presence-view/v1/buddylist',
    method: 'GET',
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'text/event-stream, application/json',
      'App-Platform': 'WebPlayer',
      Origin: 'https://open.spotify.com',
      'User-Agent': USER_AGENT,
    },
  }, res => {
    log('SSE', `status=${res.statusCode} content-type=${res.headers['content-type']}`);
    res.on('data', chunk => {
      log('SSE-DATA', chunk.toString().slice(0, 500));
    });
    res.on('end', () => log('SSE', 'stream ended'));
  });
  req.on('error', e => log('SSE', 'error:', e.message));
  req.end();
}

// Keep alive for 3 minutes to observe pushes
setTimeout(() => {
  log('DONE', `${messageCount} frames received — closing`);
  ws.close();
  process.exit(0);
}, 3 * 60 * 1000);

log('INFO', 'listening for up to 3 minutes — move a friend to a new track to trigger a push…');
