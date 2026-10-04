"""Translation comments — free-text feedback on one part of one translated card.

Players pick which part of the card they mean (name, flavor or effect text) and
write a comment; they may send as many as they like. Comments sit next to the
up/down votes (same card keys, same player ids) and are read back only through
the admin report, which needs the ADMIN_TOKEN (comments are free text from
players, so unlike the vote counts they aren't public).

Report: GET /v1/comments/report  (header X-Admin-Token)
  ?lang=PL&field=effect&status=open&format=json|csv
Triage: POST /v1/comments/{id}/status {"status": "open"|"done"|"ignored"}
"""
import csv
import hashlib
import hmac
import io
import os
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from .main import KEY_RE, LANGS, VOTER_RE, _client_ip, db

router = APIRouter()
FIELDS = ("name", "flavor", "effect")
STATUSES = ("open", "done", "ignored")
MAX_TEXT = 500
MAX_VERSION = 16
COMMENTS_PER_MINUTE = 10   # per client IP: plenty for real feedback, stops floods


def init_comments() -> None:
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS comments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT NOT NULL,
                lang TEXT NOT NULL,
                field TEXT NOT NULL CHECK (field IN ('name', 'flavor', 'effect')),
                text TEXT NOT NULL,
                voter TEXT NOT NULL,
                version TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'done', 'ignored')),
                created_at INTEGER NOT NULL
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS comments_key ON comments(key, field)")
        c.execute("CREATE INDEX IF NOT EXISTS comments_lang ON comments(lang, status)")


init_comments()

_posts: dict[str, deque] = defaultdict(deque)


def _comment_rate_limit(request: Request) -> None:
    now = time.monotonic()
    q = _posts[_client_ip(request)]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= COMMENTS_PER_MINUTE:
        raise HTTPException(429, "Too many comments, slow down")
    q.append(now)


def _require_admin(token: str | None) -> None:
    expected = os.environ.get("ADMIN_TOKEN", "")
    if not expected or not token or not hmac.compare_digest(token, expected):
        raise HTTPException(403, "Admin token required")


def _player_tag(voter: str) -> str:
    """Short stable tag so a report can tell 'same player' apart without showing ids."""
    return hashlib.sha256(voter.encode()).hexdigest()[:8]


class CommentIn(BaseModel):
    key: str
    voter: str
    field: str
    text: str
    version: str = ""


@router.post("/v1/comments")
def post_comment(comment: CommentIn, request: Request) -> dict:
    if not KEY_RE.match(comment.key):
        raise HTTPException(400, "Invalid key")
    if not VOTER_RE.match(comment.voter):
        raise HTTPException(400, "Invalid voter id")
    if comment.field not in FIELDS:
        raise HTTPException(400, "Field must be name, flavor or effect")
    text = comment.text.strip()
    if not text:
        raise HTTPException(400, "Empty comment")
    if len(text) > MAX_TEXT:
        raise HTTPException(400, f"Comment longer than {MAX_TEXT} characters")
    _comment_rate_limit(request)
    with db() as c:
        cur = c.execute(
            "INSERT INTO comments (key, lang, field, text, voter, version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (comment.key, comment.key[3:5], comment.field, text, comment.voter,
             comment.version.strip()[:MAX_VERSION], int(time.time())),
        )
        mine = c.execute("SELECT COUNT(*) FROM comments WHERE key = ? AND voter = ?",
                         (comment.key, comment.voter)).fetchone()[0]
    return {"ok": True, "id": cur.lastrowid, "mine": mine}


def _query(lang: str | None, field: str | None, status: str | None) -> list[tuple]:
    where, args = [], []
    if lang:
        if lang.upper() not in LANGS:
            raise HTTPException(400, "Unknown language")
        where.append("c.lang = ?")
        args.append(lang.upper())
    if field:
        if field not in FIELDS:
            raise HTTPException(400, "Unknown field")
        where.append("c.field = ?")
        args.append(field)
    if status:
        if status not in STATUSES:
            raise HTTPException(400, "Unknown status")
        where.append("c.status = ?")
        args.append(status)
    sql = f"""SELECT c.id, c.key, c.lang, c.field, c.text, c.voter, c.version, c.status, c.created_at,
                     (SELECT SUM(value = 1) FROM votes v WHERE v.key = c.key),
                     (SELECT SUM(value = -1) FROM votes v WHERE v.key = c.key)
              FROM comments c {'WHERE ' + ' AND '.join(where) if where else ''}
              ORDER BY c.key, c.field, c.created_at"""
    with db() as c:
        return c.execute(sql, args).fetchall()


@router.get("/v1/comments/report")
def report(lang: str | None = None, field: str | None = None, status: str | None = "open",
           format: str = Query("json", pattern="^(json|csv)$"),
           x_admin_token: str | None = Header(None)):
    """Comments grouped per card and field (busiest first), with the card's votes."""
    _require_admin(x_admin_token)
    rows = _query(lang, field, status or None)
    if format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["id", "key", "lang", "field", "comment", "player", "version", "status", "created_utc", "votes_up", "votes_down"])
        for (cid, key, lg, fld, text, voter, ver, st, created, up, down) in rows:
            w.writerow([cid, key, lg, fld, text, _player_tag(voter), ver, st,
                        time.strftime("%Y-%m-%d %H:%M", time.gmtime(created)), up or 0, down or 0])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv; charset=utf-8")
    groups: dict[tuple, dict] = {}
    for (cid, key, lg, fld, text, voter, ver, st, created, up, down) in rows:
        g = groups.setdefault((key, fld), {"key": key, "lang": lg, "field": fld, "votes_up": up or 0,
                                           "votes_down": down or 0, "players": set(), "comments": []})
        g["players"].add(voter)
        g["comments"].append({"id": cid, "text": text, "player": _player_tag(voter), "version": ver,
                              "status": st, "created_at": created})
    out = []
    for g in groups.values():
        g["count"] = len(g["comments"])
        g["players"] = len(g["players"])
        out.append(g)
    out.sort(key=lambda g: (-g["players"], -g["count"], g["key"], g["field"]))
    return {"total": len(rows), "groups": out}


class StatusIn(BaseModel):
    status: str


@router.post("/v1/comments/{comment_id}/status")
def set_status(comment_id: int, body: StatusIn, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    if body.status not in STATUSES:
        raise HTTPException(400, "Unknown status")
    with db() as c:
        n = c.execute("UPDATE comments SET status = ? WHERE id = ?", (body.status, comment_id)).rowcount
    if not n:
        raise HTTPException(404, "No such comment")
    return {"ok": True}
