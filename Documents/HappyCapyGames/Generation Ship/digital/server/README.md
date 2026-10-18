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

All votes, scores, translation comments and crash reports are in `data/votes.db` (SQLite). Back up that one file.

## API

| Method | Path | What |
|---|---|---|
| GET | `/v1/votes?keys=k1,k2&voter=...` | up/down counts per card (+ `mine` if `voter` given), max 50 keys |
| POST | `/v1/votes` `{"key", "voter", "value"}` | cast (+1/−1) or retract (0) a vote; returns new counts |
| GET | `/v1/votes/report?lang=PL&min_votes=1` | cards sorted by most "needs work" votes |

| POST | `/v1/comments` `{"key", "voter", "field", "text", "version"}` | a translation comment on one card's `name`, `flavor` or `effect` (max 500 chars, any number per player, 10/min per IP) |
| GET | `/v1/comments/report?lang=PL&field=effect&status=open&format=json\|csv` | **admin:** comments grouped per card + field (most players first), with the card's votes |
| POST | `/v1/comments/{id}/status` `{"status": "open"\|"done"\|"ignored"}` | **admin:** triage a comment |

| POST | `/v1/crashes` `{"install", "build", "exit_code", "phase", "safe_mode", "os", "gpu", "log"}` | a crash report from the Windows launcher (only when the player ticks "send an error report"; 5/min per IP) |
| GET | `/v1/crashes/report?days=30&format=json\|csv` | **admin:** crashes grouped by cause (exit code + first error + first crash frame), most players first |
| GET | `/v1/crashes/{id}` | **admin:** one report with its full log |
| POST | `/v1/uprising/bugs` `{"card_sheet", "card_name", "card_kind", "category", "severity", "summary", "actual", "expected", "steps", "reporter", "build", "source", "context", "log", "state"}` | an Uprising Digital bug report (Collection / card test / Escape menu; `state` = the game's save JSON, stored gzipped in `data/uprising_bugs/`; 5/min per IP) |
| GET | `/v1/uprising/bugs/report?since_id=0&status=&format=json\|csv` | **admin:** reports after an id, without logs and snapshots (the "Uprising Bug Reports" sheet's Apps Script polls this) |
| GET | `/v1/uprising/bugs/{id}` · `/v1/uprising/bugs/{id}/state` | **admin:** one report with its log · its game state snapshot |
| POST | `/v1/uprising/bugs/{id}/status` `{"status", "fixed_in", "note"}` · DELETE `/v1/uprising/bugs/{id}` | **admin:** triage (new/fixing/fixed/cant_reproduce/not_a_bug/needs_info) · remove |

Admin endpoints need the header `X-Admin-Token: <ADMIN_TOKEN>`. The token is set in
`/opt/hcg-api/.env` on the server (`ADMIN_TOKEN=...`, not in git); without it they always answer 403.
`tools/translation_comments_report.py` in the game repo pulls the report into a CSV + readable summary;
`tools/crash_report.py` lists the crash reports.

Keys look like `tv_PL_Tech_GSTechs44x67mm12` (language, deck, card file).
Voters are `steam:<steam id>` or `dev:<random device id>`.
Writes are limited to 30 per minute per IP.

## Local development

```
pip install -r requirements.txt httpx pytest
pytest tests                      # run the tests
uvicorn app.main:app --reload     # http://127.0.0.1:8000/docs
```
