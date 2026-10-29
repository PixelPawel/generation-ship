"""Full-game codes for the Android app.

The Android app is free to download; Versus and Co-op unlock with a one-time
Google Play purchase (handled on the phone) or with one of our codes, checked
here. Codes are made in batches by an admin (tools/unlock_codes.py in the game
repo writes them to a CSV) and handed out to backers, contests, press...

A code unlocks up to `max_uses` players (default 3): a new phone or a
reinstall gets a new anonymous player id, so the same person needs a few. The
same player redeeming again is free. Failed attempts are limited per IP, so
codes can't be guessed (12 characters from a 32-letter alphabet).

Redeem: POST /v1/unlock/redeem  {code, player, platform}
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
        c.execute("CREATE INDEX IF NOT EXISTS unlock_codes_batch ON unlock_codes(batch)")


init_unlock()

_fails: dict[str, deque] = defaultdict(deque)


def _check_fails(request: Request) -> deque:
    now = time.monotonic()
    q = _fails[_client_ip(request)]
    while q and now - q[0] > 3600:
        q.popleft()
    if len(q) >= FAILS_PER_HOUR:
        raise HTTPException(429, "Too many wrong codes, try again later")
    return q


def normalize(code: str) -> str:
    """What players type: any case, with or without dashes and spaces."""
    return re.sub(r"[\s-]", "", code).upper()


def pretty(code: str) -> str:
    return "-".join(code[i:i + 4] for i in range(0, len(code), 4))


class RedeemIn(BaseModel):
    code: str = Field(min_length=1, max_length=40)
    player: str
    platform: str = Field(default="", max_length=16)


@router.post("/v1/unlock/redeem")
def redeem(body: RedeemIn, request: Request) -> dict:
    if not VOTER_RE.match(body.player):
        raise HTTPException(400, "Invalid player id")
    fails = _check_fails(request)
    code = normalize(body.code)
    with db() as c:
        row = c.execute("SELECT max_uses FROM unlock_codes WHERE code = ?", (code,)).fetchone()
        if row is None:
            fails.append(time.monotonic())
            raise HTTPException(404, "Unknown code")
        if c.execute("SELECT 1 FROM unlock_redemptions WHERE code = ? AND player = ?",
                     (code, body.player)).fetchone():
            return {"ok": True, "again": True}
        used = c.execute("SELECT COUNT(*) FROM unlock_redemptions WHERE code = ?", (code,)).fetchone()[0]
        if used >= row[0]:
            raise HTTPException(409, "Code already used up")
        c.execute("INSERT INTO unlock_redemptions (code, player, platform, redeemed_at) VALUES (?, ?, ?, ?)",
                  (code, body.player, body.platform[:16], int(time.time())))
    return {"ok": True, "again": False}


class CodesIn(BaseModel):
    count: int = Field(ge=1, le=MAX_BATCH)
    batch: str
    max_uses: int = Field(default=3, ge=1, le=100)
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
