"""Uprising bug reports — sent from Uprising Digital's Collection, card tests and Escape menu.

A report says which card it is about (if any), what kind of problem it is and how bad, a one-line
summary, what happened, what should have happened, the steps to get there, who sent it and from
which build. Reports sent from inside a game carry a snapshot of the game state (stored gzipped
beside the database, data/uprising_bugs/<id>.json.gz) and the end of the game's log, so the bug can
be replayed exactly. Context (the card's printed text, how the game implements it, the test that
was running, phase / chapter) comes along as a small JSON object.

The "Uprising Bug Reports" Google Sheet pulls new reports through its Apps Script
(uprising/tools/sheets/uprising_bugs.gs) and keeps the triage; tools/bug_reports.py in the
Uprising repo fetches the full report and the state snapshot.

Send:   POST /v1/uprising/bugs                                  (open, 5 a minute per IP)
Report: GET  /v1/uprising/bugs/report?since_id=0&status=&format=json|csv   (header X-Admin-Token)
One:    GET  /v1/uprising/bugs/{id}           (admin; with the log)
State:  GET  /v1/uprising/bugs/{id}/state     (admin; the game state snapshot as JSON)
Triage: POST /v1/uprising/bugs/{id}/status    (admin; {"status", "fixed_in", "note"})
Delete: DELETE /v1/uprising/bugs/{id}         (admin)
"""
import csv
import gzip
import io
import json
import os
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse, Response
from pydantic import BaseModel, Field

from .comments import _require_admin
from .main import DB_PATH, _client_ip, db

router = APIRouter()
REPORTS_PER_MINUTE = 5            # per client IP
STATUSES = ("new", "fixing", "fixed", "cant_reproduce", "not_a_bug", "needs_info")
MAX_CONTEXT = 20000               # characters of JSON
STATE_DIR = os.path.join(os.path.dirname(DB_PATH) or ".", "uprising_bugs")
LIST_KEYS = ("id", "status", "card_sheet", "card_name", "card_kind", "category", "severity", "summary",
             "actual", "expected", "steps", "reporter", "build", "source", "context", "has_log", "has_state",
             "fixed_in", "note", "created_at", "updated_at")


def init_uprising_bugs() -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS uprising_bugs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                status TEXT NOT NULL DEFAULT 'new',
                card_sheet TEXT NOT NULL,
                card_name TEXT NOT NULL,
                card_kind TEXT NOT NULL,
                category TEXT NOT NULL,
                severity TEXT NOT NULL,
                summary TEXT NOT NULL,
                actual TEXT NOT NULL,
                expected TEXT NOT NULL,
                steps TEXT NOT NULL,
                reporter TEXT NOT NULL,
                build TEXT NOT NULL,
                source TEXT NOT NULL,
                context TEXT NOT NULL,
                log TEXT NOT NULL,
                has_state INTEGER NOT NULL,
                fixed_in TEXT NOT NULL DEFAULT '',
                note TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS uprising_bugs_status ON uprising_bugs(status, id)")


init_uprising_bugs()

_posts: dict[str, deque] = defaultdict(deque)


def _bug_rate_limit(request: Request) -> None:
    now = time.monotonic()
    q = _posts[_client_ip(request)]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= REPORTS_PER_MINUTE:
        raise HTTPException(429, "Too many reports")
    q.append(now)


class BugIn(BaseModel):
    card_sheet: str = Field("", max_length=40)
    card_name: str = Field("", max_length=120)
    card_kind: str = Field("", max_length=40)
    category: str = Field(..., pattern="^(rules|stuck|display|other)$")
    severity: str = Field(..., pattern="^(blocker|wrong|minor)$")
    summary: str = Field(..., min_length=3, max_length=160)
    actual: str = Field(..., min_length=3, max_length=4000)
    expected: str = Field(..., min_length=1, max_length=4000)
    steps: str = Field("", max_length=4000)
    reporter: str = Field("", max_length=60)
    build: str = Field("", max_length=64)
    source: str = Field("", pattern="^(collection|test|game|)$")
    context: dict = Field(default_factory=dict)
    log: str = Field("", max_length=64000)
    state: str = Field("", max_length=4_000_000)   # the game state, as JSON text


class StatusIn(BaseModel):
    status: str = Field(..., pattern="^(" + "|".join(STATUSES) + ")$")
    fixed_in: str | None = Field(None, max_length=80)
    note: str | None = Field(None, max_length=2000)


def _state_path(bug_id: int) -> str:
    return os.path.join(STATE_DIR, f"{bug_id}.json.gz")


@router.post("/v1/uprising/bugs")
def post_bug(bug: BugIn, request: Request) -> dict:
    context = json.dumps(bug.context, ensure_ascii=False)
    if len(context) > MAX_CONTEXT:
        raise HTTPException(413, "Context too large")
    state = bug.state.strip()
    if state:
        try:
            json.loads(state)
        except ValueError:
            raise HTTPException(400, "State is not JSON")
    _bug_rate_limit(request)
    now = int(time.time())
    with db() as c:
        cur = c.execute(
            """INSERT INTO uprising_bugs (card_sheet, card_name, card_kind, category, severity, summary, actual,
               expected, steps, reporter, build, source, context, log, has_state, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (bug.card_sheet.strip(), bug.card_name.strip(), bug.card_kind.strip(), bug.category, bug.severity,
             bug.summary.strip(), bug.actual.strip(), bug.expected.strip(), bug.steps.strip(), bug.reporter.strip(),
             bug.build.strip(), bug.source, context, bug.log, int(bool(state)), now, now),
        )
        bug_id = cur.lastrowid
    if state:
        os.makedirs(STATE_DIR, exist_ok=True)
        with gzip.open(_state_path(bug_id), "wt", encoding="utf-8") as fh:
            fh.write(state)
    return {"ok": True, "id": bug_id}


def _row_dict(row: tuple, keys: tuple) -> dict:
    d = dict(zip(keys, row))
    if "context" in d:
        try:
            d["context"] = json.loads(d["context"] or "{}")
        except ValueError:
            d["context"] = {}
    if "has_state" in d:
        d["has_state"] = bool(d["has_state"])
    if "has_log" in d:
        d["has_log"] = bool(d["has_log"])
    return d


@router.get("/v1/uprising/bugs/report")
def report(since_id: int = Query(0, ge=0), status: str = Query("", pattern="^(|" + "|".join(STATUSES) + ")$"),
           format: str = Query("json", pattern="^(json|csv)$"), x_admin_token: str | None = Header(None)):
    """Reports after `since_id` (oldest first), without logs and snapshots."""
    _require_admin(x_admin_token)
    sql = """SELECT id, status, card_sheet, card_name, card_kind, category, severity, summary, actual, expected,
             steps, reporter, build, source, context, log != '', has_state, fixed_in, note, created_at, updated_at
             FROM uprising_bugs WHERE id > ?"""
    args: list = [since_id]
    if status:
        sql += " AND status = ?"
        args.append(status)
    with db() as c:
        rows = c.execute(sql + " ORDER BY id", args).fetchall()
    out = [_row_dict(r, LIST_KEYS) for r in rows]
    if format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow([k for k in LIST_KEYS if k != "context"])
        for d in out:
            w.writerow([d[k] for k in LIST_KEYS if k != "context"])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv; charset=utf-8")
    return {"total": len(out), "reports": out}


@router.get("/v1/uprising/bugs/{bug_id}")
def one(bug_id: int, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    keys = LIST_KEYS[:15] + ("log",) + LIST_KEYS[16:]
    with db() as c:
        row = c.execute(
            """SELECT id, status, card_sheet, card_name, card_kind, category, severity, summary, actual, expected,
               steps, reporter, build, source, context, log, has_state, fixed_in, note, created_at, updated_at
               FROM uprising_bugs WHERE id = ?""", (bug_id,)).fetchone()
    if not row:
        raise HTTPException(404, "No such report")
    return _row_dict(row, keys)


@router.get("/v1/uprising/bugs/{bug_id}/state")
def state(bug_id: int, x_admin_token: str | None = Header(None)) -> Response:
    _require_admin(x_admin_token)
    path = _state_path(bug_id)
    if not os.path.exists(path):
        raise HTTPException(404, "No state snapshot for this report")
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        return Response(fh.read(), media_type="application/json")


@router.post("/v1/uprising/bugs/{bug_id}/status")
def set_status(bug_id: int, body: StatusIn, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    sets, args = ["status = ?", "updated_at = ?"], [body.status, int(time.time())]
    if body.fixed_in is not None:
        sets.append("fixed_in = ?")
        args.append(body.fixed_in.strip())
    if body.note is not None:
        sets.append("note = ?")
        args.append(body.note.strip())
    with db() as c:
        cur = c.execute(f"UPDATE uprising_bugs SET {', '.join(sets)} WHERE id = ?", (*args, bug_id))
    if cur.rowcount == 0:
        raise HTTPException(404, "No such report")
    return {"ok": True}


@router.delete("/v1/uprising/bugs/{bug_id}")
def delete(bug_id: int, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    with db() as c:
        cur = c.execute("DELETE FROM uprising_bugs WHERE id = ?", (bug_id,))
    if cur.rowcount == 0:
        raise HTTPException(404, "No such report")
    if os.path.exists(_state_path(bug_id)):
        os.remove(_state_path(bug_id))
    return {"ok": True}
