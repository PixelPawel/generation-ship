"""Full-game codes for the Android app.

The Android app is free to download; Versus and Co-op unlock with a one-time
Google Play purchase (handled on the phone) or with one of our codes, checked
here. Codes are made in batches by an admin (tools/unlock_codes.py in the game
repo writes them to a CSV) and handed out to backers, contests, press...

A code unlocks up to `max_uses` players (default 1, the user's rule: one code,
one player). A player is the Google Play Games account when the app is signed in
to it (`games_player`), else the install's anonymous player id. So a new phone
or a reinstall signed in to the same Play Games account gets the unlock back
(restore), and can enter the same code again; without Play Games it is locked
again. The same player redeeming again is free. Failed attempts are limited per
IP, so codes can't be guessed (12 characters from a 32-letter alphabet).

Redeem:  POST /v1/unlock/redeem   {code, player, platform, games_player?}
Restore: POST /v1/unlock/restore  {player, games_player, platform}: unlocks a new
         install of a Play Games account that redeemed a code before (and links an
         install's earlier code to its Play Games account)
Make:   POST /v1/unlock/codes   {count, batch, max_uses, note}   (header X-Admin-Token)
Report: GET  /v1/unlock/report  (admin; per batch: codes, used codes, redemptions)
"""
import re
import secrets
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field

from .comments import _require_admin
from .main import VOTER_RE, _client_ip, db

router = APIRouter()
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no I, O, 0, 1
CODE_LEN = 12
MAX_BATCH = 5000
FAILS_PER_HOUR = 10                             # wrong codes per client IP
MISSES_PER_HOUR = 30                            # restores that found nothing, per client IP
# Google Play Games player ids (digits, or a letter prefix and digits): kept loose
GAMES_RE = re.compile(r"^[A-Za-z0-9_-]{4,64}$")
BATCH_RE = re.compile(r"^[A-Za-z0-9_-]{1,40}$")


def init_unlock() -> None:
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS unlock_codes (
                code TEXT PRIMARY KEY,
                batch TEXT NOT NULL,
                max_uses INTEGER NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL
            )"""
        )
        c.execute(
            """CREATE TABLE IF NOT EXISTS unlock_redemptions (
                code TEXT NOT NULL,
                player TEXT NOT NULL,
                platform TEXT NOT NULL,
                redeemed_at INTEGER NOT NULL,
                PRIMARY KEY (code, player)
            )"""
        )
        cols = [r[1] for r in c.execute("PRAGMA table_info(unlock_redemptions)").fetchall()]
        if "games_player" not in cols:
            c.execute("ALTER TABLE unlock_redemptions ADD COLUMN games_player TEXT NOT NULL DEFAULT ''")
        c.execute("CREATE INDEX IF NOT EXISTS unlock_redemptions_games ON unlock_redemptions(games_player)")
        c.execute("CREATE INDEX IF NOT EXISTS unlock_codes_batch ON unlock_codes(batch)")


init_unlock()

_fails: dict[str, deque] = defaultdict(deque)
_misses: dict[str, deque] = defaultdict(deque)


def _check_fails(request: Request, store: dict | None = None, limit: int = FAILS_PER_HOUR) -> deque:
    now = time.monotonic()
    q = (_fails if store is None else store)[_client_ip(request)]
    while q and now - q[0] > 3600:
        q.popleft()
    if len(q) >= limit:
        raise HTTPException(429, "Too many wrong codes, try again later")
    return q


def _games_id(value: str) -> str:
    value = value.strip()
    if value and not GAMES_RE.match(value):
        raise HTTPException(400, "Invalid Play Games player id")
    return value


def normalize(code: str) -> str:
    """What players type: any case, with or without dashes and spaces."""
    return re.sub(r"[\s-]", "", code).upper()


def pretty(code: str) -> str:
    return "-".join(code[i:i + 4] for i in range(0, len(code), 4))


class RedeemIn(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    player: str
    platform: str = Field(default="", max_length=16)
    games_player: str = Field(default="", max_length=64)


def _link(c, code: str, player: str, games: str, platform: str) -> None:
    """Make sure this install has a row for the code, carrying its Play Games id."""
    if c.execute("SELECT 1 FROM unlock_redemptions WHERE code = ? AND player = ?", (code, player)).fetchone():
        if games:
            c.execute("UPDATE unlock_redemptions SET games_player = ? WHERE code = ? AND player = ? AND games_player = ''",
                      (games, code, player))
    else:
        c.execute("INSERT INTO unlock_redemptions (code, player, platform, redeemed_at, games_player) VALUES (?, ?, ?, ?, ?)",
                  (code, player, platform[:16], int(time.time()), games))


@router.post("/v1/unlock/redeem")
def redeem(body: RedeemIn, request: Request) -> dict:
    if not VOTER_RE.match(body.player):
        raise HTTPException(400, "Invalid player id")
    games = _games_id(body.games_player)
    fails = _check_fails(request)
    code = normalize(body.code)
    with db() as c:
        row = c.execute("SELECT max_uses FROM unlock_codes WHERE code = ?", (code,)).fetchone()
        if row is None:
            fails.append(time.monotonic())
            raise HTTPException(404, "Unknown code")
        rows = c.execute("SELECT player, games_player FROM unlock_redemptions WHERE code = ?", (code,)).fetchall()
        if any(p == body.player or (games and g == games) for p, g in rows):
            _link(c, code, body.player, games, body.platform)
            return {"ok": True, "again": True}
        # one use = one player: a Play Games account (all its installs) or a single install
        holders = {("g", g) if g else ("p", p) for p, g in rows}
        if len(holders) >= row[0]:
            raise HTTPException(409, "Code already used up")
        _link(c, code, body.player, games, body.platform)
    return {"ok": True, "again": False}


class RestoreIn(BaseModel):
    player: str
    games_player: str = Field(min_length=1, max_length=64)
    platform: str = Field(default="", max_length=16)


@router.post("/v1/unlock/restore")
def restore(body: RestoreIn, request: Request) -> dict:
    if not VOTER_RE.match(body.player):
        raise HTTPException(400, "Invalid player id")
    games = _games_id(body.games_player)
    misses = _check_fails(request, _misses, MISSES_PER_HOUR)
    with db() as c:
        found = c.execute("SELECT code FROM unlock_redemptions WHERE games_player = ? LIMIT 1", (games,)).fetchone()
        if found is None:
            # an install that redeemed before signing in: link its code to the account
            found = c.execute("SELECT code FROM unlock_redemptions WHERE player = ? LIMIT 1", (body.player,)).fetchone()
        if found is None:
            misses.append(time.monotonic())
            raise HTTPException(404, "Nothing to restore")
        _link(c, found[0], body.player, games, body.platform)
    return {"ok": True}


class CodesIn(BaseModel):
    count: int = Field(ge=1, le=MAX_BATCH)
    batch: str
    max_uses: int = Field(default=1, ge=1, le=100)
    note: str = Field(default="", max_length=200)


@router.post("/v1/unlock/codes")
def make_codes(body: CodesIn, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    if not BATCH_RE.match(body.batch):
        raise HTTPException(400, "Batch name: letters, digits, - and _ only")
    now = int(time.time())
    codes: list[str] = []
    with db() as c:
        while len(codes) < body.count:
            code = "".join(secrets.choice(ALPHABET) for _ in range(CODE_LEN))
            cur = c.execute("INSERT OR IGNORE INTO unlock_codes (code, batch, max_uses, note, created_at) "
                            "VALUES (?, ?, ?, ?, ?)", (code, body.batch, body.max_uses, body.note, now))
            if cur.rowcount:
                codes.append(code)
    return {"batch": body.batch, "max_uses": body.max_uses, "codes": [pretty(k) for k in codes]}


@router.get("/v1/unlock/report")
def report(x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    with db() as c:
        rows = c.execute(
            """SELECT k.batch, COUNT(DISTINCT k.code), COUNT(DISTINCT r.code), COUNT(r.player), MIN(k.created_at)
               FROM unlock_codes k LEFT JOIN unlock_redemptions r ON r.code = k.code
               GROUP BY k.batch ORDER BY MIN(k.created_at)"""
        ).fetchall()
    return {"batches": [{"batch": b, "codes": n, "used_codes": u, "redemptions": r, "created_at": t}
                        for b, n, u, r, t in rows]}
