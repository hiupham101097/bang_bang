# blue-frog-fec8 — BANG BANG match server

Cloudflare Worker + one Durable Object per match. The Durable Object is the
authoritative owner of a room: clients never write game state directly.

## What is implemented

- Room creation/joining, ready state, bots, and host-only start.
- Role distribution for 4–8 players.
- Private hand snapshots over WebSocket; other players only receive card counts.
- Turn state, draw two cards, BANG target validation, a 10-second dodge window,
  Beer healing, gun range equipment, discard phase, elimination, and win checks.
- An alarm resolves a missed dodge or advances a timed-out turn even if no client
  is currently sending requests.

## Run locally

```powershell
cd cloudflare
npm install
npx wrangler dev --local --var AUTH_SECRET:replace-with-a-long-random-secret
```

The local API is `http://127.0.0.1:8787`. Start Flutter with:

```powershell
flutter run --dart-define=CLOUDFLARE_MATCH_URL=http://10.0.2.2:8787
```

Use the computer's LAN IP instead of `10.0.2.2` for a physical phone.

## Deploy

1. Create a free Cloudflare account and run `npx wrangler login` in this folder.
2. Create the Worker once: `npx wrangler deploy`.
3. Set the signing secret (never put it in `wrangler.jsonc`):

```powershell
npx wrangler secret put AUTH_SECRET
```

4. Deploy again: `npx wrangler deploy`.
5. Copy the reported `https://...workers.dev` address and build/run Flutter with:

```powershell
flutter run --dart-define=CLOUDFLARE_MATCH_URL=https://blue-frog-fec8.<tai-khoan-cloudflare>.workers.dev
```

The Flutter app creates and stores its own player ID locally; no Firebase
service is required.
