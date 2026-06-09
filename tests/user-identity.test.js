#!/usr/bin/env node
// Tests for the getUser() JS function injected into the Spotify WebView.
// Validates that email and country are correctly extracted from /v1/me,
// not hardcoded to 'user@spotify.com' / 'US'.

import assert from 'assert';

// ---------------------------------------------------------------------------
// The function under test — extracted from spotify_webview_login.dart
// Dependencies (localStorage, fetch) are injected so we can mock them.
// ---------------------------------------------------------------------------
function makeGetUser({ localStorage, fetch }) {
  return async function getUser(token) {
    // Extract userId from localStorage key prefix (Spotify namespaces keys as "{userId}:setting")
    let userId = null;
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i) || '';
      const m = key.match(/^([a-z0-9]{20,}):/);
      if (m && m[1] !== 'anonymous') { userId = m[1]; break; }
    }

    if (userId) {
      // Call spclient (name/image/followers) and /v1/me (email/country) in parallel
      const [spResult, meResult] = await Promise.allSettled([
        fetch(
          'https://guc-spclient.spotify.com/user-profile-view/v3/profile/' + userId,
          { headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'App-Platform': 'WebPlayer' } }
        ).then(r => r.ok ? r.json() : null).catch(() => null),
        fetch('https://api.spotify.com/v1/me', {
          headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json' }
        }).then(r => r.ok ? r.json() : null).catch(() => null),
      ]);
      const sp = spResult.status === 'fulfilled' ? spResult.value : null;
      const me = meResult.status === 'fulfilled' ? meResult.value : null;

      return {
        id: userId,
        displayName: (sp && sp.name) || (me && me.display_name) || userId,
        imageUrl: (sp && sp.image_url) || (me && me.images && me.images.length ? me.images[0].url : null) || null,
        email: (me && me.email) || null,
        country: (me && me.country) || null,
        followers: (sp && sp.followers_count) || (me && me.followers && me.followers.total) || 0,
      };
    }

    // Fallback: /v1/me from browser context (no localStorage prefix found)
    try {
      const r = await fetch('https://api.spotify.com/v1/me', {
        headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json' }
      });
      if (r.ok) {
        const d = await r.json();
        return {
          id: d.id,
          displayName: d.display_name,
          imageUrl: (d.images && d.images.length) ? d.images[0].url : null,
          email: d.email || null,
          country: d.country || null,
          followers: d.followers ? d.followers.total : 0,
        };
      }
    } catch (_) {}
    return null;
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function makeLocalStorage(keys) {
  return {
    length: keys.length,
    key: (i) => keys[i],
  };
}

function makeFetch({ spClient = null, me = null } = {}) {
  return async (url, _opts) => {
    if (url.includes('spclient.spotify.com')) {
      if (spClient === null) throw new Error('spclient network error');
      return { ok: spClient !== 'error', json: async () => spClient };
    }
    if (url.includes('/v1/me')) {
      if (me === null) throw new Error('/v1/me network error');
      return { ok: me !== 'error', json: async () => me };
    }
    return { ok: false, json: async () => ({}) };
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
let passed = 0;
let failed = 0;

async function test(name, fn) {
  try {
    await fn();
    console.log(`  PASS  ${name}`);
    passed++;
  } catch (err) {
    console.error(`  FAIL  ${name}`);
    console.error(`        ${err.message}`);
    failed++;
  }
}

console.log('\ngetUser — localStorage + spclient + /v1/me primary path\n');

await test('returns michael_liem2000@yahoo.com and ID (Indonesia) from /v1/me', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:setting', 'anonymous:other']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem', image_url: 'https://img', followers_count: 48 },
      me: { id: '21fvdxlt6ejvha6jnrgdwamja', display_name: 'Michael Liem', email: 'michael_liem2000@yahoo.com', country: 'ID', followers: { total: 48 }, images: [] },
    }),
  });
  const result = await getUser('tok123');
  assert.strictEqual(result.email, 'michael_liem2000@yahoo.com', 'email should come from /v1/me');
  assert.strictEqual(result.country, 'ID', 'country should be ID (Indonesia)');
  assert.notStrictEqual(result.email, 'user@spotify.com', 'must not be hardcoded placeholder');
  assert.notStrictEqual(result.country, 'US', 'must not be hardcoded US');
});

await test('prefers spclient displayName but uses /v1/me email+country', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem (spclient)', image_url: 'https://sp-img', followers_count: 48 },
      me: { id: '21fvdxlt6ejvha6jnrgdwamja', display_name: 'Michael Liem (me)', email: 'mich@example.com', country: 'GB', followers: { total: 48 }, images: [] },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.displayName, 'Michael Liem (spclient)', 'spclient name takes priority');
  assert.strictEqual(result.email, 'mich@example.com');
  assert.strictEqual(result.country, 'GB');
});

await test('falls back to /v1/me displayName when spclient fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: 'error',
      me: { id: '21fvdxlt6ejvha6jnrgdwamja', display_name: 'Michael Liem', email: 'mich@example.com', country: 'AU', followers: { total: 48 }, images: [{ url: 'https://me-img' }] },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.displayName, 'Michael Liem');
  assert.strictEqual(result.email, 'mich@example.com');
  assert.strictEqual(result.country, 'AU');
});

await test('email is null (not hardcoded) when /v1/me fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem', followers_count: 48 },
      me: 'error',
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.email, null, 'email must be null, not hardcoded placeholder');
  assert.strictEqual(result.country, null, 'country must be null, not hardcoded US');
  assert.strictEqual(result.displayName, 'Michael Liem', 'spclient name still used');
});

await test('skips anonymous prefix and finds real userId', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage([
      'anonymous:someSetting',
      'shortid:x',
      '21fvdxlt6ejvha6jnrgdwamja:setting',
    ]),
    fetch: makeFetch({
      spClient: { name: 'Michael', followers_count: 10 },
      me: { id: '21fvdxlt6ejvha6jnrgdwamja', display_name: 'Michael', email: 'mich@ex.com', country: 'AU', followers: { total: 10 }, images: [] },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.id, '21fvdxlt6ejvha6jnrgdwamja');
  assert.strictEqual(result.email, 'mich@ex.com');
});

console.log('\ngetUser — /v1/me fallback (no localStorage userId)\n');

await test('fallback path returns email from /v1/me', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['anonymous:setting']),
    fetch: makeFetch({
      me: { id: 'userid123', display_name: 'User', email: 'user@real.com', country: 'SG', followers: { total: 5 }, images: [] },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.email, 'user@real.com');
  assert.strictEqual(result.country, 'SG');
});

await test('fallback path returns null when /v1/me fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage([]),
    fetch: makeFetch({ me: null }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result, null);
});

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
