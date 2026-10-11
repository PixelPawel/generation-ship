"""Crash reports — sent by the Windows launcher (GS.exe) when the game ends with an error,
only after the player ticked "send an error report" in its crash window.

A report holds the end of godot.log (the launcher removes the Windows user name), the exit
code, whether it died while starting or later, safe graphics mode, graphics card + driver,
Windows version, the game build and an anonymous install id (counts players, nothing more).
Reports with the same cause share a signature (exit code + first error line + first crash
frame, numbers and paths stripped), so the report shows the most common problems first.

Report: GET /v1/crashes/report?days=30&format=json|csv  (header X-Admin-Token)
One:    GET /v1/crashes/{id}  (admin; the full log)
"""
import csv
import hashlib
import io
import re
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from .comments import _require_admin
from .main import _client_ip, db

router = APIRouter()
REPORTS_PER_MINUTE = 5            # per client IP
INSTALL_RE = re.compile(r"^[A-Za-z0-9-]{16,64}$")


def init_crashes() -> None:
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS crashes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                signature TEXT NOT NULL,
                summary TEXT NOT NULL,
                install TEXT NOT NULL,
                build TEXT NOT NULL,
                exit_code TEXT NOT NULL,
                phase TEXT NOT NULL,
                safe_mode INTEGER NOT NULL,
                os TEXT NOT NULL,
                gpu TEXT NOT NULL,
                log TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS crashes_sig ON crashes(signature, created_at)")


init_crashes()

_posts: dict[str, deque] = defaultdict(deque)


def _crash_rate_limit(request: Request) -> None:
    now = time.monotonic()
    q = _posts[_client_ip(request)]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= REPORTS_PER_MINUTE:
        raise HTTPException(429, "Too many reports")
    q.append(now)


_ERROR_RE = re.compile(r"^\s*(ERROR|SCRIPT ERROR|USER ERROR|CrashHandlerException):?\s*(.*)$")
_FRAME_RE = re.compile(r"^\s*\[\d+\]\s*(.+)$")


def _normalize(line: str) -> str:
    line = re.sub(r"[A-Za-z]:[\\/][^\s:]*", "<path>", line)    # file paths
    line = re.sub(r"0x[0-9A-Fa-f]+|\d+", "#", line)              # addresses, numbers, ids
    return line.strip()[:200]


def signature(exit_code: str, log: str) -> tuple[str, str]:
    """(hash, readable summary) of a crash: exit code, first error line, first crash frame."""
    error, frame = "", ""
    for line in log.splitlines():
        if not error:
            m = _ERROR_RE.match(line)
            if m:
                error = _normalize(m.group(0))
        if not frame:
            m = _FRAME_RE.match(line)
            if m:
                frame = _normalize(m.group(1))
        if error and frame:
            break
    summary = " | ".join(p for p in (exit_code, error, frame) if p)
    return hashlib.sha256(summary.encode()).hexdigest()[:12], summary


class CrashIn(BaseModel):
    install: str
    build: str = Field("", max_length=64)
    exit_code: str = Field(..., max_length=16)
    phase: str = Field(..., pattern="^(start|play)$")
    safe_mode: bool = False
    os: str = Field("", max_length=200)
    gpu: str = Field("", max_length=400)
    log: str = Field("", max_length=64000)


@router.post("/v1/crashes")
def post_crash(crash: CrashIn, request: Request) -> dict:
    if not INSTALL_RE.match(crash.install):
        raise HTTPException(400, "Invalid install id")
    if not re.match(r"^0x[0-9A-Fa-f]{1,8}$", crash.exit_code):
        raise HTTPException(400, "Invalid exit code")
    _crash_rate_limit(request)
    exit_code = crash.exit_code.upper().replace("0X", "0x")
    sig, summary = signature(exit_code, crash.log)
    with db() as c:
        cur = c.execute(
            """INSERT INTO crashes (signature, summary, install, build, exit_code, phase, safe_mode, os, gpu, log, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (sig, summary, crash.install, crash.build.strip(), exit_code, crash.phase, int(crash.safe_mode),
             crash.os.strip(), crash.gpu.strip(), crash.log, int(time.time())),
        )
    return {"ok": True, "id": cur.lastrowid}


@router.get("/v1/crashes/report")
def report(days: int = Query(30, ge=1, le=3650), format: str = Query("json", pattern="^(json|csv)$"),
           x_admin_token: str | None = Header(None)):
    """Crash groups, most players first: count, players, builds, GPUs, phases, latest example id."""
    _require_admin(x_admin_token)
    since = int(time.time()) - days * 86400
    with db() as c:
        rows = c.execute(
            """SELECT id, signature, summary, install, build, phase, safe_mode, gpu, created_at
               FROM crashes WHERE created_at >= ? ORDER BY created_at""", (since,)).fetchall()
    groups: dict[str, dict] = {}
    for (cid, sig, summary, install, build, phase, safe, gpu, created) in rows:
        g = groups.setdefault(sig, {"signature": sig, "summary": summary, "count": 0, "players": set(),
                                    "builds": set(), "gpus": defaultdict(int), "phases": defaultdict(int),
                                    "safe_mode": 0, "first_at": created, "last_at": created, "latest_id": cid})
        g["count"] += 1
        g["players"].add(install)
        if build:
            g["builds"].add(build)
        g["gpus"][gpu.split(" (driver")[0] or "?"] += 1
        g["phases"][phase] += 1
        g["safe_mode"] += safe
        g["last_at"] = created
        g["latest_id"] = cid
    out = []
    for g in groups.values():
        g["players"] = len(g["players"])
        g["builds"] = sorted(g["builds"])
        g["gpus"] = dict(sorted(g["gpus"].items(), key=lambda kv: -kv[1]))
        g["phases"] = dict(g["phases"])
        out.append(g)
    out.sort(key=lambda g: (-g["players"], -g["count"]))
    if format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["signature", "players", "count", "summary", "phases", "safe_mode", "gpus", "builds", "last_utc", "latest_id"])
        for g in out:
            w.writerow([g["signature"], g["players"], g["count"], g["summary"],
                        " ".join(f"{k}:{v}" for k, v in g["phases"].items()), g["safe_mode"],
                        "; ".join(f"{k} x{v}" for k, v in g["gpus"].items()), " ".join(g["builds"]),
                        time.strftime("%Y-%m-%d %H:%M", time.gmtime(g["last_at"])), g["latest_id"]])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv; charset=utf-8")
    return {"days": days, "total": len(rows), "groups": out}


@router.get("/v1/crashes/{crash_id}")
def one(crash_id: int, x_admin_token: str | None = Header(None)) -> dict:
    _require_admin(x_admin_token)
    with db() as c:
        row = c.execute(
            """SELECT id, signature, summary, install, build, exit_code, phase, safe_mode, os, gpu, log, created_at
               FROM crashes WHERE id = ?""", (crash_id,)).fetchone()
    if not row:
        raise HTTPException(404, "No such report")
    keys = ("id", "signature", "summary", "install", "build", "exit_code", "phase", "safe_mode", "os", "gpu", "log", "created_at")
    return dict(zip(keys, row))
