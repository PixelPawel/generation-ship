"""Happy Capy Games backend — Generation Ship.

For now: community translation votes (one vote per card image per language
per voter). Meant to grow into the multiplayer service later.

Storage is a single SQLite file (DB_PATH). A vote is +1 (good), -1 (needs
work) or 0 (retracted, not counted); re-voting overwrites the voter's row.
"""
import os
import re
import sqlite3
import threading
import time
from collections import defaultdict, deque
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, Field

DB_PATH = os.environ.get("DB_PATH", "data/votes.db")
LANGS = ("DE", "ES", "FR", "IT", "PL")
# tv_<LANG>_<deck>_<file>, see TranslationVotes.board_name() in the game.
KEY_RE = re.compile(r"^tv_(DE|ES|FR|IT|PL)_[A-Za-z0-9_]{1,120}$")
# "steam:<64-bit id>" or "dev:<uuid-ish>" (anonymous device id).
VOTER_RE = re.compile(r"^(steam:\d{5,20}|dev:[A-Za-z0-9-]{16,64})$")
MAX_KEYS_PER_QUERY = 50
WRITES_PER_MINUTE = 30  # per client IP

app = FastAPI(title="Happy Capy Games API", version="1.1")
_db_lock = threading.Lock()

from .relay import router as relay_router  # noqa: E402  (online rooms + WebSocket relay)

app.include_router(relay_router)


@contextmanager
def db():
    with _db_lock:
        conn = sqlite3.connect(DB_PATH)
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()


def init_db() -> None:
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    with db() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute(
            """CREATE TABLE IF NOT EXISTS votes (
                key TEXT NOT NULL,
                voter TEXT NOT NULL,
                value INTEGER NOT NULL CHECK (value IN (-1, 0, 1)),
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (key, voter)
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS votes_key ON votes(key)")


init_db()

# Simple sliding-window write limit per client IP (in memory; resets on restart).
_writes: dict[str, deque] = defaultdict(deque)


def _client_ip(request: Request) -> str:
    # Behind Caddy the real client is in X-Forwarded-For.
    fwd = request.headers.get("x-forwarded-for", "")
    return fwd.split(",")[0].strip() if fwd else (request.client.host if request.client else "?")


def _rate_limit(request: Request) -> None:
    now = time.monotonic()
    q = _writes[_client_ip(request)]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= WRITES_PER_MINUTE:
        raise HTTPException(429, "Too many votes, slow down")
    q.append(now)


def _counts(c: sqlite3.Connection, keys: list[str], voter: str | None) -> dict:
    out = {k: {"up": 0, "down": 0, "mine": 0} for k in keys}
    marks = ",".join("?" * len(keys))
    for key, up, down in c.execute(
        f"SELECT key, SUM(value = 1), SUM(value = -1) FROM votes WHERE key IN ({marks}) GROUP BY key", keys
    ):
        out[key]["up"] = up or 0
        out[key]["down"] = down or 0
    if voter:
        for key, value in c.execute(
            f"SELECT key, value FROM votes WHERE voter = ? AND key IN ({marks})", [voter, *keys]
        ):
            out[key]["mine"] = value
    return out


def _check_key(key: str) -> None:
    if not KEY_RE.match(key):
        raise HTTPException(400, f"Invalid key: {key}")


def _check_voter(voter: str) -> None:
    if not VOTER_RE.match(voter):
        raise HTTPException(400, "Invalid voter id")


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/v1/votes")
def get_votes(keys: str = Query(..., description="Comma-separated card keys"), voter: str | None = None) -> dict:
    key_list = [k for k in keys.split(",") if k]
    if not key_list or len(key_list) > MAX_KEYS_PER_QUERY:
        raise HTTPException(400, f"Give 1-{MAX_KEYS_PER_QUERY} keys")
    for k in key_list:
        _check_key(k)
    if voter:
        _check_voter(voter)
    with db() as c:
        return {"votes": _counts(c, key_list, voter)}


class VoteIn(BaseModel):
    key: str
    voter: str
    value: int = Field(ge=-1, le=1)


@app.post("/v1/votes")
def post_vote(vote: VoteIn, request: Request) -> dict:
    _check_key(vote.key)
    _check_voter(vote.voter)
    _rate_limit(request)
    with db() as c:
        c.execute(
            """INSERT INTO votes (key, voter, value, updated_at) VALUES (?, ?, ?, ?)
               ON CONFLICT(key, voter) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at""",
            (vote.key, vote.voter, vote.value, int(time.time())),
        )
        return {"votes": _counts(c, [vote.key], vote.voter)}


@app.get("/v1/votes/report")
def report(lang: str | None = None, min_votes: int = 1, limit: int = Query(200, le=2000)) -> dict:
    """Cards with the most 'needs work' votes first (optionally one language)."""
    if lang and lang.upper() not in LANGS:
        raise HTTPException(400, "Unknown language")
    where = "WHERE key LIKE ?" if lang else ""
    args: list = [f"tv_{lang.upper()}_%"] if lang else []
    with db() as c:
        rows = c.execute(
            f"""SELECT key, SUM(value = 1) AS up, SUM(value = -1) AS down FROM votes {where}
                GROUP BY key HAVING up + down >= ? ORDER BY down DESC, up ASC LIMIT ?""",
            [*args, min_votes, limit],
        ).fetchall()
    return {"cards": [{"key": k, "up": u, "down": d} for k, u, d in rows]}
