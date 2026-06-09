#!/usr/bin/env node
// Tests for the getUser() JS function injected into the Spotify WebView.
// Validates that email and country are correctly extracted from
// www.spotify.com/api/account-settings/v1/profile (not deprecated /v1/me).

import assert from 'assert';

// ---------------------------------------------------------------------------
// The function under test — mirrors spotify_webview_login.dart JS injection
// ---------------------------------------------------------------------------
function makeGetUser({ localStorage, fetch }) {
  return async function getUser(token) {
    let userId = null;
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i) || '';
      const m = key.match(/^([a-z0-9]{20,}):/);
      if (m && m[1] !== 'anonymous') { userId = m[1]; break; }
    }

    if (userId) {
      // spclient: name/image/followers  |  account-settings: email/country
      const [spResult, accountResult] = await Promise.allSettled([
        fetch(
          'https://guc-spclient.spotify.com/user-profile-view/v3/profile/' + userId,
          { headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'App-Platform': 'WebPlayer' } }
        ).then(r => r.ok ? r.json() : null).catch(() => null),
        fetch('https://www.spotify.com/api/account-settings/v1/profile', {
          headers: { 'Accept': 'application/json' }
        }).then(r => r.ok ? r.json() : null).catch(() => null),
      ]);
      const sp = spResult.status === 'fulfilled' ? spResult.value : null;
      const account = accountResult.status === 'fulfilled' ? accountResult.value : null;
      const ap = account && account.profile;
      return {
        id: userId,
        displayName: (sp && sp.name) || userId,
        imageUrl: (sp && sp.image_url) || null,
        email: (ap && ap.email) || null,
        country: (ap && ap.country) || null,
        followers: (sp && sp.followers_count) || 0,
      };
    }

    // Fallback: account-settings gives us userId via profile.username
    try {
      const r = await fetch('https://www.spotify.com/api/account-settings/v1/profile', {
        headers: { 'Accept': 'application/json' }
      });
      if (r.ok) {
        const data = await r.json();
        const p = data && data.profile;
        if (p && p.username) {
          let spFallback = null;
          try {
            const sr = await fetch('https://guc-spclient.spotify.com/user-profile-view/v3/profile/' + p.username, {
              headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'App-Platform': 'WebPlayer' }
            });
            if (sr.ok) spFallback = await sr.json();
          } catch (_) {}
          return { id: p.username, displayName: (spFallback && spFallback.name) || p.username, imageUrl: (spFallback && spFallback.image_url) || null, email: p.email || null, country: p.country || null, followers: (spFallback && spFallback.followers_count) || 0 };
        }
      }
    } catch (_) {}
    return null;
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function makeLocalStorage(keys) {
  return { length: keys.length, key: (i) => keys[i] };
}

// account: the account-settings/v1/profile response (or null/error to simulate failure)
function makeFetch({ spClient = null, account = null } = {}) {
  return async (url, _opts) => {
    if (url.includes('spclient.spotify.com')) {
      if (spClient === null) throw new Error('spclient network error');
      return { ok: spClient !== 'error', json: async () => spClient };
    }
    if (url.includes('account-settings/v1/profile')) {
      if (account === null) throw new Error('account-settings network error');
      return { ok: account !== 'error', json: async () => account };
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

console.log('\ngetUser — localStorage + spclient + account-settings primary path\n');

await test('returns michael_liem2000@yahoo.com and ID (Indonesia) from account-settings', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:setting', 'anonymous:other']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem', image_url: 'https://img', followers_count: 48 },
      account: { profile: { username: '21fvdxlt6ejvha6jnrgdwamja', email: 'michael_liem2000@yahoo.com', country: 'ID' } },
    }),
  });
  const result = await getUser('tok123');
  assert.strictEqual(result.email, 'michael_liem2000@yahoo.com', 'email should come from account-settings');
  assert.strictEqual(result.country, 'ID', 'country should be ID (Indonesia)');
  assert.notStrictEqual(result.email, 'user@spotify.com', 'must not be hardcoded placeholder');
  assert.notStrictEqual(result.country, 'US', 'must not be hardcoded US');
});

await test('spclient displayName takes priority; email+country from account-settings', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem (spclient)', image_url: 'https://sp-img', followers_count: 48 },
      account: { profile: { username: '21fvdxlt6ejvha6jnrgdwamja', email: 'mich@example.com', country: 'GB' } },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.displayName, 'Michael Liem (spclient)', 'spclient name takes priority');
  assert.strictEqual(result.email, 'mich@example.com');
  assert.strictEqual(result.country, 'GB');
});

await test('falls back to userId as displayName when spclient fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: 'error',
      account: { profile: { username: '21fvdxlt6ejvha6jnrgdwamja', email: 'mich@example.com', country: 'AU' } },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.displayName, '21fvdxlt6ejvha6jnrgdwamja', 'falls back to userId');
  assert.strictEqual(result.email, 'mich@example.com');
  assert.strictEqual(result.country, 'AU');
});

await test('email is null (not hardcoded) when account-settings fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['21fvdxlt6ejvha6jnrgdwamja:x']),
    fetch: makeFetch({
      spClient: { name: 'Michael Liem', followers_count: 48 },
      account: 'error',
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.email, null, 'email must be null when account-settings fails');
  assert.strictEqual(result.country, null, 'country must be null when account-settings fails');
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
      account: { profile: { username: '21fvdxlt6ejvha6jnrgdwamja', email: 'mich@ex.com', country: 'ID' } },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.id, '21fvdxlt6ejvha6jnrgdwamja');
  assert.strictEqual(result.email, 'mich@ex.com');
  assert.strictEqual(result.country, 'ID');
});

console.log('\ngetUser — account-settings fallback (no localStorage userId)\n');

await test('fallback path gets userId from account-settings profile.username', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage(['anonymous:setting']),
    fetch: makeFetch({
      spClient: { name: 'User Name', image_url: 'https://img', followers_count: 5 },
      account: { profile: { username: 'userid123', email: 'user@real.com', country: 'SG' } },
    }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result.id, 'userid123');
  assert.strictEqual(result.email, 'user@real.com');
  assert.strictEqual(result.country, 'SG');
  assert.strictEqual(result.displayName, 'User Name', 'spclient name used in fallback');
});

await test('fallback path returns null when account-settings fails', async () => {
  const getUser = makeGetUser({
    localStorage: makeLocalStorage([]),
    fetch: makeFetch({ account: null }),
  });
  const result = await getUser('tok');
  assert.strictEqual(result, null);
});

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
