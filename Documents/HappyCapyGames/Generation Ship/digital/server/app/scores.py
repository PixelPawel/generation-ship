"""Global leaderboard — Steam and Android share one board.

One row per player (same ids as votes: "steam:<id>" or "dev:<device id>"),
keeping their best total; a lower score only refreshes the display name.
`details` is the game's packed per-line score breakdown (ScoringSnapshotCodec),
stored as-is so the leaderboard can show how a score was made.
Same trust model as the old Steam board: clients report their own score.
"""
import json
import time

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

from .main import VOTER_RE, _rate_limit, db

router = APIRouter()
MAX_SCORE = 999
MAX_DETAILS = 32
TOP_LIMIT = 100


def init_scores() -> None:
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS scores (
                player TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                score INTEGER NOT NULL,
                details TEXT NOT NULL,
                platform TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS scores_score ON scores(score DESC, updated_at ASC)")


init_scores()


class ScoreIn(BaseModel):
    player: str
    name: str = Field(min_length=1, max_length=64)
    score: int = Field(ge=0, le=MAX_SCORE)
    details: list[int] = Field(default_factory=list, max_length=MAX_DETAILS)
    platform: str = Field(default="", max_length=16)


def _clean_name(name: str) -> str:
    name = "".join(ch for ch in name if ch.isprintable()).strip()[:24]
    return name or "Player"


def _rank(c, score: int, updated_at: int) -> int:
    better = c.execute(
        "SELECT COUNT(*) FROM scores WHERE score > ? OR (score = ? AND updated_at < ?)",
        (score, score, updated_at),
    ).fetchone()[0]
    return better + 1


@router.post("/v1/scores")
def post_score(entry: ScoreIn, request: Request) -> dict:
    if not VOTER_RE.match(entry.player):
        raise HTTPException(400, "Invalid player id")
    _rate_limit(request)
    name = _clean_name(entry.name)
    now = int(time.time())
    details = json.dumps([int(d) for d in entry.details if -(2**31) <= int(d) < 2**32])
    with db() as c:
        row = c.execute("SELECT score FROM scores WHERE player = ?", (entry.player,)).fetchone()
        if row is None or entry.score > row[0]:
            c.execute(
                """INSERT INTO scores (player, name, score, details, platform, updated_at) VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(player) DO UPDATE SET name = excluded.name, score = excluded.score,
                   details = excluded.details, platform = excluded.platform, updated_at = excluded.updated_at""",
                (entry.player, name, entry.score, details, entry.platform[:16], now),
            )
            best = True
        else:
            c.execute("UPDATE scores SET name = ? WHERE player = ?", (name, entry.player))
            best = False
        score, updated = c.execute("SELECT score, updated_at FROM scores WHERE player = ?", (entry.player,)).fetchone()
        return {"best": best, "score": score, "rank": _rank(c, score, updated)}


@router.get("/v1/scores/top")
def top_scores(player: str | None = None, limit: int = Query(TOP_LIMIT, ge=1, le=TOP_LIMIT)) -> dict:
    with db() as c:
        rows = c.execute(
            "SELECT player, name, score, details, platform, updated_at FROM scores "
            "ORDER BY score DESC, updated_at ASC LIMIT ?",
            (limit,),
        ).fetchall()
        entries = [
            {"rank": i + 1, "name": n, "score": s, "details": json.loads(d), "platform": p, "me": bool(player) and pl == player}
            for i, (pl, n, s, d, p, _u) in enumerate(rows)
        ]
        mine = None
        if player and VOTER_RE.match(player):
            r = c.execute("SELECT score, updated_at FROM scores WHERE player = ?", (player,)).fetchone()
            if r:
                mine = {"score": r[0], "rank": _rank(c, r[0], r[1])}
    return {"entries": entries, "mine": mine}
