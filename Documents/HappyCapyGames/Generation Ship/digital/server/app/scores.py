"""Global leaderboard — Steam and Android share one board.

One row per player and source (same ids as votes: "steam:<id>" or "dev:<device
id>"), keeping their best total; a lower score only refreshes the display name.
Source "play" is a game played to the end in the app, "scan" a tableau read
from a photo (Scan Tableau) - anyone can photograph any ship, so the board can
show either or both, and a scan never replaces a played best. "fleet" is a won
Generation Fleet (co-op) game, ranked by stars, with the Destination's No.; it
has its own board and is left out of "all" (co-op stars don't compare).
`details` is the game's packed per-line score breakdown (ScoringSnapshotCodec),
stored as-is so the leaderboard can show how a score was made.
Same trust model as the old Steam board: clients report their own score.
"""
import csv
import hmac
import io
import json
import os
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from .main import VOTER_RE, _rate_limit, db

router = APIRouter()
MAX_SCORE = 999
MAX_DETAILS = 64     # the game always sends all 64 slots (ScoringSnapshotCodec), 0 = empty
TOP_LIMIT = 100
SOURCES = ("play", "scan", "fleet")
OWN_BOARD_SOURCES = ("fleet",)    # not part of the "all" board


_TABLE = """CREATE TABLE IF NOT EXISTS {name} (
    player TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'play',
    name TEXT NOT NULL,
    score INTEGER NOT NULL,
    details TEXT NOT NULL,
    platform TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    destination INTEGER NOT NULL DEFAULT 0,
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
        cols = [r[1] for r in c.execute("PRAGMA table_info(scores)").fetchall()]
        if "destination" not in cols:
            c.execute("ALTER TABLE scores ADD COLUMN destination INTEGER NOT NULL DEFAULT 0")
        c.execute("CREATE INDEX IF NOT EXISTS scores_score ON scores(score DESC, updated_at ASC)")


init_scores()


class ScoreIn(BaseModel):
    player: str
    name: str = Field(min_length=1, max_length=64)
    score: int = Field(ge=0, le=MAX_SCORE)
    details: list[int] = Field(default_factory=list, max_length=MAX_DETAILS)
    platform: str = Field(default="", max_length=16)
    source: str = "play"     # older clients only ever sent played games
    destination: int = Field(default=0, ge=0, le=99)   # fleet: the Destination card's No.


def _clean_name(name: str) -> str:
    name = "".join(ch for ch in name if ch.isprintable()).strip()[:24]
    return name or "Player"


def _where(source: str) -> tuple[str, tuple]:
    """SQL filter for a board: one source, or "all" of them (except the own-board ones)."""
    if source in SOURCES:
        return "source = ? AND ", (source,)
    marks = ", ".join("?" * len(OWN_BOARD_SOURCES))
    return f"source NOT IN ({marks}) AND ", OWN_BOARD_SOURCES


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
    details = json.dumps([int(d) for d in entry.details if d != 0 and -(2**31) <= int(d) < 2**32])
    with db() as c:
        row = c.execute("SELECT score FROM scores WHERE player = ? AND source = ?", key).fetchone()
        if row is None or entry.score > row[0]:
            c.execute(
                """INSERT INTO scores (player, source, name, score, details, platform, updated_at, destination)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(player, source) DO UPDATE SET name = excluded.name, score = excluded.score,
                   details = excluded.details, platform = excluded.platform, updated_at = excluded.updated_at,
                   destination = excluded.destination""",
                (entry.player, entry.source, name, entry.score, details, entry.platform[:16], now, entry.destination),
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
    """The board for one source ("play", "scan", "fleet") or "all" (a player can be on it once per source)."""
    w, args = _where(source)
    with db() as c:
        rows = c.execute(
            f"SELECT player, source, name, score, details, platform, updated_at, destination FROM scores "
            f"WHERE {w}1 ORDER BY score DESC, updated_at ASC LIMIT ?",
            args + (limit,),
        ).fetchall()
        entries = [
            {"rank": i + 1, "name": n, "score": s, "details": json.loads(d), "platform": p, "source": src,
             "destination": dest, "me": bool(player) and pl == player}
            for i, (pl, src, n, s, d, p, _u, dest) in enumerate(rows)
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


# ── Daily snapshots (contest standings) ──────────────────────────────────────
# A systemd timer on the VPS POSTs /v1/scores/snapshot at 23:59 Europe/Berlin
# (deploy/score-snapshot.*); the top 100 of the board are stored as they stood
# then. GET serves the latest (or a given day's) snapshot as JSON or as CSV —
# the contest's Google Sheet pulls the CSV with IMPORTDATA, so it always shows
# the 23:59 standings however late Google refreshes.

BERLIN = ZoneInfo("Europe/Berlin")
SNAPSHOT_LIMIT = 100

_SNAP_TABLE = """CREATE TABLE IF NOT EXISTS score_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    day TEXT NOT NULL,
    taken_at INTEGER NOT NULL,
    entries TEXT NOT NULL
)"""


def init_snapshots() -> None:
    with db() as c:
        c.execute(_SNAP_TABLE)
        c.execute("CREATE INDEX IF NOT EXISTS score_snapshots_day ON score_snapshots(source, day, taken_at)")


init_snapshots()


def _berlin(ts: int) -> str:
    return datetime.fromtimestamp(ts, BERLIN).strftime("%Y-%m-%d %H:%M")


def _require_admin(token: str | None) -> None:
    expected = os.environ.get("ADMIN_TOKEN", "")
    if not expected or not token or not hmac.compare_digest(token, expected):
        raise HTTPException(403, "Admin token required")


def take_snapshot(source: str, now: int | None = None) -> dict:
    now = int(time.time()) if now is None else now
    board = top_scores(player=None, limit=SNAPSHOT_LIMIT, source=source)["entries"]
    entries = [{"rank": e["rank"], "name": e["name"], "score": e["score"], "platform": e["platform"]}
               for e in board]
    # when each best was set, from the board itself (top_scores doesn't return it)
    w, args = _where(source)
    with db() as c:
        rows = c.execute(f"SELECT updated_at FROM scores WHERE {w}1 ORDER BY score DESC, updated_at ASC LIMIT ?",
                         args + (SNAPSHOT_LIMIT,)).fetchall()
        for e, (u,) in zip(entries, rows):
            e["since"] = _berlin(u)
        day = datetime.fromtimestamp(now, BERLIN).strftime("%Y-%m-%d")
        c.execute("INSERT INTO score_snapshots (source, day, taken_at, entries) VALUES (?, ?, ?, ?)",
                  (source, day, now, json.dumps(entries)))
    return {"source": source, "day": day, "taken_at": now, "taken_at_berlin": _berlin(now), "entries": entries}


@router.post("/v1/scores/snapshot")
def post_snapshot(source: str = "play", x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    if source not in SOURCES + ("all",):
        raise HTTPException(400, "Invalid source")
    snap = take_snapshot(source)
    return {"source": snap["source"], "day": snap["day"], "taken_at_berlin": snap["taken_at_berlin"],
            "count": len(snap["entries"])}


def _load_snapshot(source: str, day: str | None) -> dict | None:
    with db() as c:
        if day:
            r = c.execute("SELECT day, taken_at, entries FROM score_snapshots WHERE source = ? AND day = ? "
                          "ORDER BY taken_at DESC LIMIT 1", (source, day)).fetchone()
        else:
            r = c.execute("SELECT day, taken_at, entries FROM score_snapshots WHERE source = ? "
                          "ORDER BY taken_at DESC LIMIT 1", (source,)).fetchone()
    if not r:
        return None
    return {"source": source, "day": r[0], "taken_at": r[1], "taken_at_berlin": _berlin(r[1]),
            "entries": json.loads(r[2])}


@router.get("/v1/scores/snapshot")
def get_snapshot(source: str = "play", day: str | None = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$")) -> dict:
    snap = _load_snapshot(source, day)
    if snap is None:
        raise HTTPException(404, "No snapshot yet")
    return snap


def _csv_safe(s: str) -> str:
    # a name like "=HYPERLINK(...)" must stay text in the spreadsheet
    return "'" + s if s[:1] in ("=", "+", "-", "@") else s


@router.get("/v1/scores/snapshot.csv", response_class=PlainTextResponse)
def get_snapshot_csv(source: str = "play", day: str | None = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$")) -> str:
    snap = _load_snapshot(source, day)
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    if snap is None:
        w.writerow(["No standings yet - the first snapshot is taken at 23:59 (Berlin)."])
        return out.getvalue()
    w.writerow(["Standings at %s (Berlin)" % snap["taken_at_berlin"]])
    w.writerow(["Rank", "Player", "Score", "Platform", "Best set (Berlin)"])
    for e in snap["entries"]:
        w.writerow([e["rank"], _csv_safe(e["name"]), e["score"], e["platform"], e.get("since", "")])
    return out.getvalue()
