# Happy Capy Games API

Backend for Generation Ship. Currently: community translation votes.
Later: the multiplayer service can live here too.

## Deploy on a VPS (one time)

1. **DNS:** add an `A` record `api.happycapygames.com` → the VPS's IP address.
2. **Install Docker** on the VPS (Ubuntu): `curl -fsSL https://get.docker.com | sh`
3. **Copy this `server/` folder** to the VPS, e.g. to `/opt/hcg-api`.
4. In that folder: `docker compose up -d --build`

Caddy fetches the HTTPS certificate automatically. Check it works:
`https://api.happycapygames.com/health` → `{"ok": true}`

## Update

Copy the changed files over, then `docker compose up -d --build`.

## Data & backups

All votes are in `data/votes.db` (SQLite). Back up that one file.

## API

| Method | Path | What |
|---|---|---|
| GET | `/v1/votes?keys=k1,k2&voter=...` | up/down counts per card (+ `mine` if `voter` given), max 50 keys |
| POST | `/v1/votes` `{"key", "voter", "value"}` | cast (+1/−1) or retract (0) a vote; returns new counts |
| GET | `/v1/votes/report?lang=PL&min_votes=1` | cards sorted by most "needs work" votes |

Keys look like `tv_PL_Tech_GSTechs44x67mm12` (language, deck, card file).
Voters are `steam:<steam id>` or `dev:<random device id>`.
Writes are limited to 30 per minute per IP.

## Local development

```
pip install -r requirements.txt httpx pytest
pytest tests                      # run the tests
uvicorn app.main:app --reload     # http://127.0.0.1:8000/docs
```
