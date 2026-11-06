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
Copies named `data/votes.db.bak*` are deleted automatically after 30 days (privacy policy), so keep long-term
backups somewhere else, or not at all.

## Privacy

The privacy policies are in `../legal/` and served by Caddy at `/datenschutz` (Windows/Steam) and
`/datenschutz-android` (Android), both Happy Capy Games, LLC; `/privacy` and `/privacy-android` open their English half.
`/delete-data` (`../legal/delete_data.html`, German half at `/daten-loeschen`) is the deletion page Google Play asks for.
The server keeps what they promise (`app/privacy.py`):

- **Retention**, checked daily: crash reports and daily leaderboard standings 12 months, translation votes and
  comments 24 months, `votes.db.bak*` 30 days.
- **IP addresses** only in memory (rate limits), dropped one hour after a client's last request. No access log
  (`--no-access-log` in the Dockerfile). Container logs go to journald, which keeps 7 days: one time on the VPS,
  `cp deploy/journald-7days.conf /etc/systemd/journald.conf.d/ && systemctl restart systemd-journald`.
- **Players' requests** (access, erasure): `python tools/privacy_request.py find|show|forget` in the game repo,
  with the player id the game shows under Settings → Privacy.

If a new feature stores something about players, add it to `PLAYER_TABLES` (erasure) or `RETENTION_DAYS` in
`app/privacy.py`, and to both policies.

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

| GET | `/v1/admin/privacy/find?name=...` | **admin:** player ids whose leaderboard name contains the text |
| GET · DELETE | `/v1/admin/privacy/{player id or crash install id}` | **admin:** everything stored for it · erase it (names in daily standings become "(removed)") |

| POST | `/v1/mail/send` `{"to", "subject", "text", "html"?, "reply_to"?, "from_name"?}` | **mail token:** send a mail through the company mailbox (Hostinger SMTP) for the HCG Hub sheet: opt-in, support and digest mails. Max 10 recipients, 300 mails/hour |
| GET | `/v1/mail/status` | **mail token:** configured?, mails sent/failed in the last 24 h, last error |

The mail endpoints need `X-Mail-Token: <MAIL_TOKEN>` and these lines in `/opt/hcg-api/.env`:
`SMTP_HOST=smtp.hostinger.com`, `SMTP_PORT=465`, `SMTP_USER=info@happycapygames.com`, `SMTP_PASSWORD=...`,
`MAIL_TOKEN=<long random string>` (the same token goes into the hub script's Script Properties as `MAIL_TOKEN`).

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

## HCG backend (company data and dashboards)

`app/hub.py`, `hub_collect.py`, `hub_dash.py`: what was the HCG Hub Google Sheet (contacts, sales, money, stock,
checklists...), the numbers collected every day, and the dashboards the team sees in the print-files site on Hostinger
(`_Shared/PrintFiles`, team password; its `hub.php` adds the token). Tables and columns come from `app/hub_schema.json`,
written by `_Shared/Claude/hub/export_backend_schema.py`. Its own database: `data/hub.db` (company data, not player
data), copied to `data/hub-backups/` every morning (30 days kept). Every endpoint needs the header `X-Hub-Token`.

`.env` lines:

```
HUB_TOKEN=...          # the same as ~/.hcg_hub_token on the PC that builds the Hostinger site (deploy.py)
YOUTUBE_API_KEY=...    # optional: YouTube channel numbers (Google Cloud, YouTube Data API v3, key restricted to it)
BGG_TOKEN=...          # optional: only if BoardGameGeek's XML API asks for one
```

Daily run, one time on the VPS:
`chmod +x deploy/hub_collect.sh && cp deploy/hub-collect.service deploy/hub-collect.timer /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now hub-collect.timer`

| Method | Path | What |
|---|---|---|
| GET | `/v1/hub/schema` | tables, columns, the Audience channels |
| GET / PUT | `/v1/hub/settings`, PUT `/v1/hub/lists` | company settings (collector ids live here) and dropdown lists |
| GET / POST | `/v1/hub/rows/{table}` | every row with its calculated columns / add a row |
| PUT / DELETE | `/v1/hub/rows/{table}/{id}` `{data, base}` | change a row (409 if someone saved it in between) / delete it |
| POST | `/v1/hub/import` `{tab, rows, replace}` | bulk load (the move from the sheet: `_Shared/Claude/hub/move_to_backend.py`) |
| GET / POST | `/v1/hub/metrics` | daily numbers; POST only for the channels typed in by hand |
| GET | `/v1/hub/dash` | everything the dashboards show |
| POST / GET | `/v1/hub/collect?only=` | run the collectors (the daily timer) / their last runs |
