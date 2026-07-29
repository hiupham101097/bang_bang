/// Public match backend. Kept in source so copied projects do not need a
/// machine-specific launch flag. It contains no secret.
const cloudflareMatchUrl = String.fromEnvironment(
  'CLOUDFLARE_MATCH_URL',
  defaultValue: 'https://blue-frog-fec8.hieupham101097.workers.dev',
);

/// Firebase Realtime Database for player accounts and progression only.
/// Match state remains authoritative in the Cloudflare Durable Object.
const firebaseRealtimeDatabaseUrl = String.fromEnvironment(
  'FIREBASE_RTDB_URL',
  defaultValue: 'https://bangbang-76e28-default-rtdb.firebaseio.com/',
);
