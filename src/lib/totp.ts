import { hmac } from "@noble/hashes/hmac.js";
import { sha1 } from "@noble/hashes/legacy.js";

// Fallback secrets, replaced at runtime by secrets.ts when Spotify rotates them.
const FALLBACK: Record<string, number[]> = {
  "59": [123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72],
  "60": [79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63, 91, 64, 87, 87],
  "61": [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78],
};

let secrets: Record<string, number[]> = FALLBACK;

export const applySecrets = (s: Record<string, number[]>) => {
  secrets = s;
};
export const clearSecrets = () => {
  secrets = FALLBACK;
};
export const activeVersion = () => String(Math.max(...Object.keys(secrets).map(Number)));

/** Spotify's web player TOTP: XOR-masked secret, decimal-joined, used as the HMAC key as ASCII. */
export function generateCode(timestampMs: number): string {
  const cipher = secrets[activeVersion()];
  const joined = cipher.map((b, i) => b ^ ((i % 33) + 9)).join("");
  // The reference pads the key to a multiple of 5 bytes (base32 encode/decode round trip).
  const ascii = new TextEncoder().encode(joined);
  const key = new Uint8Array(Math.ceil(ascii.length / 5) * 5);
  key.set(ascii);

  const step = BigInt(Math.floor(timestampMs / 1000 / 30));
  const msg = new Uint8Array(8);
  new DataView(msg.buffer).setBigUint64(0, step);
  const d = hmac(sha1, key, msg);
  const o = d[d.length - 1] & 0x0f;
  const n = (((d[o] & 0x7f) << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]) % 1_000_000;
  return String(n).padStart(6, "0");
}

export function generateParams(timestampMs: number) {
  const totp = generateCode(timestampMs);
  return { totp, totpServer: totp, totpVer: activeVersion() };
}
