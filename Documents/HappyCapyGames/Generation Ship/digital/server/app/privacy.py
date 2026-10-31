"""Privacy housekeeping: what the privacy policies (digital/legal/) promise about the server.

Retention: a background task deletes old rows once a day (crash reports after 12 months, translation votes
and comments after 24 months, daily leaderboard standings after 12 months) and votes.db.bak* copies in the
data folder after 30 days.

IP addresses: the per-IP rate limits (votes, scores, comments, crash reports, code redemptions) keep an address
in memory only; the task drops every address not seen for an hour.

Player requests (GDPR access and erasure), admin only (header X-Admin-Token); tools/privacy_request.py in the
game repo wraps them:
    GET    /v1/admin/privacy/find?name=...   player ids whose leaderboard name contains the text
    GET    /v1/admin/privacy/{subject}       everything stored for a player id (steam:... / dev:...)
                                             or a crash-report install id
    DELETE /v1/admin/privacy/{subject}       erase it; the player's names in old daily standings become "(removed)"
"""
import glob
import json
import os
import sqlite3
import sys
import threading
import time

from fastapi import APIRouter, Header, HTTPException, Query

from .comments import _require_admin
from .crashes import INSTALL_RE
from .main import DB_PATH, VOTER_RE, db

router = APIRouter()
DAY = 86400
RETENTION_DAYS = (  # table, time column, days kept
    ("crashes", "created_at", 365),
    ("comments", "created_at", 730),
    ("votes", "updated_at", 730),
    ("score_snapshots", "taken_at", 365),
)
BACKUP_DAYS = 30
IP_KEEP_SEC = 3600            # longest rate-limit window (wrong unlock codes per hour)
TICK_SEC = 600                # IP pruning every 10 minutes, retention once a day
# Per-IP rate-limit stores, by module. Only modules this server has loaded are looked at.
IP_STORES = {
    "app.main": ("_writes",),
    "app.comments": ("_posts",),
    "app.crashes": ("_posts",),
    "app.unlock": ("_fails", "_misses"),
    "app.uprising_bugs": ("_posts", "_comment_posts"),
}
PLAYER_TABLES = (("scores", "player"), ("votes", "voter"), ("comments", "voter"), ("unlock_redemptions", "player"))
INSTALL_TABLES = (("crashes", "install"),)
REMOVED_NAME = "(removed)"


def _has_table(c: sqlite3.Connection, name: str) -> bool:
    return c.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (name,)).fetchone() is not None


def prune_ips(now: float | None = None) -> int:
    """Forget client IPs whose last request is older than IP_KEEP_SEC. Returns how many were dropped."""
    now = time.monotonic() if now is None else now
    dropped = 0
    for module, attrs in IP_STORES.items():
        mod = sys.modules.get(module)
        for attr in attrs:
            store = getattr(mod, attr, None)
            if not isinstance(store, dict):
                continue
            try:
                items = list(store.items())
            except RuntimeError:      # changed by a request thread mid-copy: next tick
                continue
            for ip, q in items:
                try:
                    stale = not q or now - q[-1] > IP_KEEP_SEC
                except IndexError:
                    stale = True
                if stale:
                    store.pop(ip, None)
                    dropped += 1
    return dropped


def _purge_backups(now: float) -> int:
    removed = 0
    for path in glob.glob(DB_PATH + ".bak*"):
        try:
            if now - os.path.getmtime(path) > BACKUP_DAYS * DAY:
                os.remove(path)
                removed += 1
        except OSError:
            pass
    return removed


def purge_old(now: int | None = None) -> dict:
    """Delete everything older than the retention periods. Returns rows/files removed per table."""
    now = int(time.time()) if now is None else now
    out: dict[str, int] = {}
    with db() as c:
        c.execute("PRAGMA secure_delete = ON")
        for table, column, days in RETENTION_DAYS:
            if _has_table(c, table):
                out[table] = c.execute(f"DELETE FROM {table} WHERE {column} < ?", (now - days * DAY,)).rowcount
    out["backups"] = _purge_backups(now)
    return out


def _housekeeping() -> None:
    # First run one tick after start (tests never get there), then every tick; retention once a day.
    last_purge = 0.0
    while True:
        time.sleep(TICK_SEC)
        try:
            prune_ips()
            if time.time() - last_purge >= DAY:
                removed = purge_old()
                last_purge = time.time()
                if any(removed.values()):
                    print(f"privacy: removed {removed}", flush=True)
        except Exception as e:  # never let housekeeping die
            print(f"privacy: housekeeping failed: {e!r}", flush=True)


threading.Thread(target=_housekeeping, name="privacy-housekeeping", daemon=True).start()


def _tables_for(subject: str) -> tuple:
    if VOTER_RE.match(subject):
        return PLAYER_TABLES
    if INSTALL_RE.match(subject):
        return INSTALL_TABLES
    raise HTTPException(400, "Give a player id (steam:... or dev:...) or a crash-report install id")


@router.get("/v1/admin/privacy/find")
def find_players(name: str = Query(..., min_length=1, max_length=64), x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    with db() as c:
        rows = c.execute(
            "SELECT player, source, name, score, platform, updated_at FROM scores "
            "WHERE instr(lower(name), ?) > 0 ORDER BY updated_at DESC LIMIT 100",
            (name.strip().lower(),),
        ).fetchall()
    keys = ("player", "source", "name", "score", "platform", "updated_at")
    return {"players": [dict(zip(keys, r)) for r in rows]}


@router.get("/v1/admin/privacy/{subject}")
def export_subject(subject: str, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    tables = _tables_for(subject)
    data: dict[str, list[dict]] = {}
    with db() as c:
        c.row_factory = sqlite3.Row
        for table, column in tables:
            if _has_table(c, table):
                data[table] = [dict(r) for r in c.execute(f"SELECT * FROM {table} WHERE {column} = ?", (subject,))]
    return {"subject": subject, "data": data}


def _blank_names_in_standings(c: sqlite3.Connection, names: set[str]) -> int:
    changed = 0
    if not names or not _has_table(c, "score_snapshots"):
        return 0
    for snap_id, raw in c.execute("SELECT id, entries FROM score_snapshots").fetchall():
        entries = json.loads(raw)
        hit = False
        for e in entries:
            if e.get("name") in names:
                e["name"] = REMOVED_NAME
                hit = True
                changed += 1
        if hit:
            c.execute("UPDATE score_snapshots SET entries = ? WHERE id = ?", (json.dumps(entries), snap_id))
    return changed


@router.delete("/v1/admin/privacy/{subject}")
def forget_subject(subject: str, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    tables = _tables_for(subject)
    deleted: dict[str, int] = {}
    with db() as c:
        c.execute("PRAGMA secure_delete = ON")
        names: set[str] = set()
        if tables is PLAYER_TABLES and _has_table(c, "scores"):
            names = {n for (n,) in c.execute("SELECT DISTINCT name FROM scores WHERE player = ?", (subject,))}
        linked = 0
        if tables is PLAYER_TABLES and _has_table(c, "unlock_redemptions"):
            # a code linked to a Play Games account: its rows from the player's other installs go too
            games = [g for (g,) in c.execute("SELECT DISTINCT games_player FROM unlock_redemptions "
                                             "WHERE player = ? AND games_player != ''", (subject,))]
            for g in games:
                linked += c.execute("DELETE FROM unlock_redemptions WHERE games_player = ? AND player != ?",
                                    (g, subject)).rowcount
        for table, column in tables:
            if _has_table(c, table):
                deleted[table] = c.execute(f"DELETE FROM {table} WHERE {column} = ?", (subject,)).rowcount
        if linked:
            deleted["unlock_redemptions"] = deleted.get("unlock_redemptions", 0) + linked
        deleted["standings_names"] = _blank_names_in_standings(c, names)
    return {"subject": subject, "deleted": deleted}
