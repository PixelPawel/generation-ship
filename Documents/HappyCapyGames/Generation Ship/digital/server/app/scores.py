"""Global leaderboard — Steam and Android share one board.

One row per player and source (same ids as votes: "steam:<id>" or "dev:<device
id>"), keeping their best total; a lower score only refreshes the display name.
Source "play" is a game played to the end in the app, "scan" a tableau read
from a photo (Scan Tableau) - anyone can photograph any ship, so the board can
show either or both, and a scan never replaces a played best.
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
SOURCES = ("play", "scan")


_TABLE = """CREATE TABLE IF NOT EXISTS {name} (
    player TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'play',
    name TEXT NOT NULL,
    score INTEGER NOT NULL,
    details TEXT NOT NULL,
    platform TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (player, source)
)"""


def init_scores() -> None:
    with db() as c:
        cols = [r[1] for r in c.execute("PRAGMA table_info(scores)").fetchall()]
        if cols and "source" not in cols:
            # boards from before sources were all played games: one row per player -> (player, "play")
            c.execute(_TABLE.format(name="scores_new"))
            c.execute("INSERT INTO scores_new (player, source, name, score, details, platform, updated_at) "
                      "SELECT player, 'play', name, score, details, platform, updated_at FROM scores")
            c.execute("DROP INDEX IF EXISTS scores_score")
            c.execute("DROP TABLE scores")
            c.execute("ALTER TABLE scores_new RENAME TO scores")
        c.execute(_TABLE.format(name="scores"))
        c.execute("CREATE INDEX IF NOT EXISTS scores_score ON scores(score DESC, updated_at ASC)")


init_scores()


class ScoreIn(BaseModel):
    player: str
    name: str = Field(min_length=1, max_length=64)
    score: int = Field(ge=0, le=MAX_SCORE)
    details: list[int] = Field(default_factory=list, max_length=MAX_DETAILS)
    platform: str = Field(default="", max_length=16)
    source: str = "play"     # older clients only ever sent played games


def _clean_name(name: str) -> str:
    name = "".join(ch for ch in name if ch.isprintable()).strip()[:24]
    return name or "Player"


def _where(source: str) -> tuple[str, tuple]:
    """SQL filter for a board: one source, or "all" of them."""
    return ("source = ? AND ", (source,)) if source in SOURCES else ("", ())


def _rank(c, score: int, updated_at: int, source: str = "all") -> int:
    w, args = _where(source)
    better = c.execute(
        f"SELECT COUNT(*) FROM scores WHERE {w}(score > ? OR (score = ? AND updated_at < ?))",
        args + (score, score, updated_at),
    ).fetchone()[0]
    return better + 1


@router.post("/v1/scores")
def post_score(entry: ScoreIn, request: Request) -> dict:
    if not VOTER_RE.match(entry.player):
        raise HTTPException(400, "Invalid player id")
    if entry.source not in SOURCES:
        raise HTTPException(400, "Invalid source")
    key = (entry.player, entry.source)
    _rate_limit(request)
    name = _clean_name(entry.name)
    now = int(time.time())
    details = json.dumps([int(d) for d in entry.details if -(2**31) <= int(d) < 2**32])
    with db() as c:
        row = c.execute("SELECT score FROM scores WHERE player = ? AND source = ?", key).fetchone()
        if row is None or entry.score > row[0]:
            c.execute(
                """INSERT INTO scores (player, source, name, score, details, platform, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(player, source) DO UPDATE SET name = excluded.name, score = excluded.score,
                   details = excluded.details, platform = excluded.platform, updated_at = excluded.updated_at""",
                (entry.player, entry.source, name, entry.score, details, entry.platform[:16], now),
            )
            best = True
        else:
            best = False
        c.execute("UPDATE scores SET name = ? WHERE player = ?", (name, entry.player))
        score, updated = c.execute("SELECT score, updated_at FROM scores WHERE player = ? AND source = ?", key).fetchone()
        return {"best": best, "score": score, "rank": _rank(c, score, updated, entry.source)}


@router.get("/v1/scores/top")
def top_scores(player: str | None = None, limit: int = Query(TOP_LIMIT, ge=1, le=TOP_LIMIT),
               source: str = "all") -> dict:
    """The board for one source ("play", "scan") or "all" (a player can be on it once per source)."""
    w, args = _where(source)
    with db() as c:
        rows = c.execute(
            f"SELECT player, source, name, score, details, platform, updated_at FROM scores "
            f"WHERE {w}1 ORDER BY score DESC, updated_at ASC LIMIT ?",
            args + (limit,),
        ).fetchall()
        entries = [
            {"rank": i + 1, "name": n, "score": s, "details": json.loads(d), "platform": p, "source": src,
             "me": bool(player) and pl == player}
            for i, (pl, src, n, s, d, p, _u) in enumerate(rows)
        ]
        mine = None
        if player and VOTER_RE.match(player):
            r = c.execute(
                f"SELECT score, updated_at, source FROM scores WHERE {w}player = ? "
                f"ORDER BY score DESC, updated_at ASC LIMIT 1",
                args + (player,),
            ).fetchone()
            if r:
                mine = {"score": r[0], "rank": _rank(c, r[0], r[1], source), "source": r[2]}
    return {"entries": entries, "mine": mine}
