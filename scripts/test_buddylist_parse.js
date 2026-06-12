#!/usr/bin/env node
// Tests buddylist API fetch + JSON parsing against the live endpoint.
// Mirrors parseFriendsJson logic from lib/services/spotify_buddy_service.dart.
//
// Usage:
//   node scripts/test_buddylist_parse.js [bearer_token]
//   (reads SPOTIFY_BEARER from .env if no arg provided)

const https = require('https');
const fs = require('fs');
const path = require('path');

function loadEnv() {
  try {
    const lines = fs.readFileSync(path.join(__dirname, '..', '.env'), 'utf8').split('\n');
    for (const line of lines) {
      const m = line.match(/^([^=]+)=(.*)$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
    }
  } catch (_) {}
}

function str(val) {
  return (typeof val === 'string' && val.length > 0) ? val : null;
}

const CURRENTLY_PLAYING_THRESHOLD_MS = 30 * 60 * 1000; // 30 min

function parseFriendsJson(responseBody, nowMs) {
  const now = nowMs || Date.now();
  const data = JSON.parse(responseBody);
  const friends = data.friends;
  if (!friends) return { error: 'no "friends" key', activities: [] };

  const activities = [];
  const skips = { null: 0, noUser: 0, noActivity: 0, exception: 0 };

  for (const friend of friends) {
    if (friend == null) { skips.null++; continue; }
    try {
      // Support envelope-wrapped {"friend":{...}} format
      const envelopeCandidate = friend.friend;
      const friendData = (envelopeCandidate && envelopeCandidate.user)
        ? envelopeCandidate
        : friend;

      const userInfo = friendData.user;
      if (!userInfo) { skips.noUser++; continue; }

      const rawTs = friendData.timestamp;
      const ts = typeof rawTs === 'number' ? rawTs : now;

      const userUri = str(userInfo.uri) || '';
      const userId = userUri.startsWith('spotify:user:')
        ? userUri.slice('spotify:user:'.length)
        : userUri;

      const user = {
        id: userId,
        displayName: str(userInfo.name) || 'Unknown User',
        imageUrl: str(userInfo.imageUrl),
      };

      const trackInfo = (friendData.track && typeof friendData.track === 'object') ? friendData.track : null;
      const playlistInfo = (friendData.playlist && typeof friendData.playlist === 'object') ? friendData.playlist : null;
      const episodeInfo = (friendData.episode && typeof friendData.episode === 'object') ? friendData.episode : null;

      if (playlistInfo) {
        const playlistUri = str(playlistInfo.uri) || '';
        activities.push({
          type: 'playlist',
          user,
          playlist: {
            id: playlistUri.split(':').pop(),
            name: str(playlistInfo.name) || 'Unknown Playlist',
            imageUrl: str(playlistInfo.imageUrl),
            trackCount: typeof playlistInfo.trackCount === 'number' ? playlistInfo.trackCount : 0,
            uri: playlistUri,
            ownerId: str(playlistInfo.owner?.id) || '',
            ownerName: str(playlistInfo.owner?.name) || '',
          },
          timestamp: new Date(ts).toISOString(),
          isCurrentlyPlaying: false,
        });
      } else if (trackInfo) {
        const albumInfo = (trackInfo.album && typeof trackInfo.album === 'object') ? trackInfo.album : {};
        const artistInfo = (trackInfo.artist && typeof trackInfo.artist === 'object') ? trackInfo.artist : {};
        const elapsedMs = now - ts;
        const isCurrentlyPlaying = elapsedMs >= 0 && elapsedMs < CURRENTLY_PLAYING_THRESHOLD_MS;

        activities.push({
          type: 'track',
          user,
          track: {
            id: str(trackInfo.uri) || '',
            name: str(trackInfo.name) || 'Unknown Track',
            artists: [str(artistInfo.name) || 'Unknown Artist'],
            artistUris: str(artistInfo.uri) ? [artistInfo.uri] : [],
            album: str(albumInfo.name) || 'Unknown Album',
            albumUri: str(albumInfo.uri),
            imageUrl: str(trackInfo.imageUrl) || str(albumInfo.imageUrl),
            uri: str(trackInfo.uri) || '',
            context: trackInfo.context ? {
              uri: str(trackInfo.context.uri) || '',
              name: str(trackInfo.context.name) || '',
            } : null,
          },
          timestamp: new Date(ts).toISOString(),
          isCurrentlyPlaying,
        });
      } else if (episodeInfo) {
        const showInfo = (episodeInfo.show && typeof episodeInfo.show === 'object') ? episodeInfo.show : {};
        const showName = str(showInfo.name) || 'Unknown Podcast';
        const elapsedMs = now - ts;
        const isCurrentlyPlaying = elapsedMs >= 0 && elapsedMs < CURRENTLY_PLAYING_THRESHOLD_MS;

        activities.push({
          type: 'track',
          user,
          track: {
            id: str(episodeInfo.uri) || '',
            name: str(episodeInfo.name) || 'Unknown Episode',
            artists: [showName],
            artistUris: [],
            album: showName,
            albumUri: str(showInfo.uri),
            imageUrl: str(episodeInfo.imageUrl) || str(showInfo.imageUrl),
            uri: str(episodeInfo.uri) || '',
          },
          timestamp: new Date(ts).toISOString(),
          isCurrentlyPlaying,
        });
      } else {
        const contextInfo = (friendData.context && typeof friendData.context === 'object') ? friendData.context : null;
        const contextUri = str(contextInfo?.uri) || '';
        if (contextUri) {
          activities.push({
            type: 'playlist',
            user,
            playlist: {
              id: contextUri.split(':').pop(),
              name: str(contextInfo?.name) || 'Spotify',
              imageUrl: null,
              trackCount: 0,
              uri: contextUri,
              ownerId: '',
              ownerName: '',
            },
            timestamp: new Date(ts).toISOString(),
            isCurrentlyPlaying: false,
          });
        } else {
          skips.noActivity++;
          console.warn(`  SKIP "${user.displayName}" — no track/episode/playlist/context`);
        }
      }
    } catch (e) {
      skips.exception++;
      console.error(`  EXCEPTION parsing friend entry:`, e.message);
    }
  }

  activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  return { friends: friends.length, parsed: activities.length, skips, activities };
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

async function main() {
  loadEnv();
  const token = process.argv[2] || process.env.SPOTIFY_BEARER;
  if (!token) {
    console.error('No bearer token. Pass as arg or set SPOTIFY_BEARER in .env');
    process.exit(1);
  }

  const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

  console.log('Fetching buddylist...');
  const { status, body } = await httpsGet(
    'https://guc-spclient.spotify.com/presence-view/v1/buddylist',
    {
      'Authorization': `Bearer ${token}`,
      'App-Platform': 'WebPlayer',
      'accept': 'application/json',
      'origin': 'https://open.spotify.com',
      'referer': 'https://open.spotify.com/',
      'User-Agent': USER_AGENT,
    }
  );

  console.log(`HTTP ${status}, body ${body.length} bytes`);

  if (status !== 200) {
    console.error('Non-200 response:', body.slice(0, 200));
    process.exit(1);
  }

  const result = parseFriendsJson(body);
  if (result.error) { console.error('Parse error:', result.error); process.exit(1); }

  console.log(`\nResults: ${result.parsed}/${result.friends} parsed`);
  const skipTotal = Object.values(result.skips).reduce((a, b) => a + b, 0);
  if (skipTotal > 0) console.log('Skips:', result.skips);

  console.log('\nActivity feed (newest first):');
  for (const a of result.activities) {
    const age = Math.round((Date.now() - new Date(a.timestamp).getTime()) / 1000 / 60);
    const playingMark = a.isCurrentlyPlaying ? ' [NOW]' : ` [${age}m ago]`;
    if (a.type === 'track') {
      console.log(`  ${a.user.displayName}${playingMark}`);
      console.log(`    ${a.track.name} — ${a.track.artists.join(', ')}`);
      console.log(`    Album: ${a.track.album}`);
      if (a.track.context) console.log(`    Context: ${a.track.context.name}`);
    } else {
      console.log(`  ${a.user.displayName}${playingMark}`);
      console.log(`    Playlist: ${a.playlist.name}`);
    }
  }

  // Validate round-trip serialization (mirrors Track.toJson / Track.fromJson)
  console.log('\nRound-trip serialization check:');
  let rtOk = 0, rtFail = 0;
  for (const a of result.activities) {
    if (a.type !== 'track') continue;
    const t = a.track;
    // toJson flat format
    const flat = {
      id: t.id, name: t.name,
      artists: t.artists,
      artist_uris: t.artistUris,
      album: t.album,
      album_uri: t.albumUri,
      image_url: t.imageUrl,
      duration_ms: 0,
      uri: t.uri,
    };
    // fromJson: album is now a plain string (flat format)
    const albumRaw = flat.album;
    let albumName, albumUri, imageUrl;
    if (typeof albumRaw === 'object' && albumRaw !== null) {
      albumName = albumRaw.name || '';
      albumUri = albumRaw.uri;
      imageUrl = flat.image_url || albumRaw.imageUrl;
    } else {
      albumName = typeof albumRaw === 'string' ? albumRaw : '';
      albumUri = flat.album_uri;
      imageUrl = flat.image_url;
    }
    const ok = albumName === t.album && albumUri === t.albumUri && imageUrl === t.imageUrl;
    if (ok) rtOk++;
    else {
      rtFail++;
      console.log(`  FAIL round-trip for "${t.name}": album="${albumName}" (expected "${t.album}")`);
    }
  }
  console.log(`  ${rtOk} passed, ${rtFail} failed`);
}

main().catch(e => { console.error(e); process.exit(1); });
