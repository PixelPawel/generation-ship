"""Writes the company calendar's entries (hub_calendar.entries) straight into a Google Calendar: the shared company
calendar (Settings > Google calendar id, e.g. kate@happycapygames.com). A Google service account does the writing;
the calendar's owner shares the calendar with it ("Make changes to events"). Its key file: GOOGLE_CALENDAR_KEY in
.env (default /data/google-calendar.json).

Only entries this sync made are ever changed or deleted: each carries extendedProperties.private.hcg_uid, and the
event ids are kept in hub.db (kv gcal_state). Everyone's own appointments stay untouched.

Runs a few seconds after every change to the hub's tables, in the daily collector run, and from "Sync now".
"""
import hashlib
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta

from .hub import hdb, kv_get, kv_put, setting, today

API = "https://www.googleapis.com/calendar/v3/calendars/{cal}/events"
SCOPES = ["https://www.googleapis.com/auth/calendar.events"]
COLORS = {"team": "3", "conventions": "5", "milestones": "9", "tasks": "10", "money": "6", "content": "4", "outreach": "11"}
DEFAULT_CATS = "team, conventions, milestones, tasks, money, content"   # follow-ups only on request (Settings)
WINDOW_BACK, WINDOW_AHEAD = 30, 400


def key_file() -> str:
    return os.environ.get("GOOGLE_CALENDAR_KEY", "/data/google-calendar.json")


def _token() -> str:
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account
    creds = service_account.Credentials.from_service_account_file(key_file(), scopes=SCOPES)
    creds.refresh(Request())
    return creds.token


def _call(method: str, url: str, token: str, body=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def event_body(e: dict, dash_url: str) -> dict:
    from .hub_calendar import _time
    body = {"summary": e["title"], "colorId": COLORS.get(e["cat"], "8"),
            "description": "\n".join(x for x in (e["detail"], f"{dash_url.split('#')[0]}#{e['area']}/{e['tab']}/{e['id']}"
                                                if dash_url and e["area"] else "", "Added by the HCG dashboards.") if x),
            "extendedProperties": {"private": {"hcg_uid": e["uid"]}}, "transparency": "transparent"}
    tm = _time(e["time"]) if e["time"] else None
    if tm:
        (h0, m0), (h1, m1) = tm
        d0 = date.fromisoformat(e["start"])
        a = datetime(d0.year, d0.month, d0.day, h0, m0)
        b = datetime(d0.year, d0.month, d0.day, h1, m1)
        if b <= a:
            b += timedelta(days=1)
        body["start"] = {"dateTime": a.isoformat(), "timeZone": "Europe/Berlin"}
        body["end"] = {"dateTime": b.isoformat(), "timeZone": "Europe/Berlin"}
    else:   # all day; Google's end date is the day after the last one
        body["start"] = {"date": e["start"]}
        body["end"] = {"date": (date.fromisoformat(e["end"]) + timedelta(days=1)).isoformat()}
    return body


def sync(c) -> str:
    from .hub_calendar import entries
    cal = setting(c, "Google calendar id")
    if not cal:
        return "skipped: no Settings > Google calendar id"
    if not os.path.exists(key_file()):
        return "skipped: no service-account key on the server (GOOGLE_CALENDAR_KEY)"
    cats = {x.strip() for x in (setting(c, "Google calendar categories") or DEFAULT_CATS).replace(";", ",").split(",") if x.strip()}
    t = today()
    lo, hi = t - timedelta(days=WINDOW_BACK), t + timedelta(days=WINDOW_AHEAD)
    dash_url = setting(c, "Dashboards URL")
    want = {e["uid"]: e for e in entries(c) if e["cat"] in cats and e["end"] >= lo.isoformat() and e["start"] <= hi.isoformat()}
    state = kv_get(c, "gcal_state", {}) or {}
    if state.get("_cal") != cal:          # another calendar: start over (the old one keeps what was written)
        state = {"_cal": cal}
    token = _token()
    base = API.format(cal=urllib.parse.quote(cal, safe=""))
    added = changed = removed = 0
    for uid, e in want.items():
        body = event_body(e, dash_url)
        h = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        have = state.get(uid)
        if have and have["h"] == h:
            continue
        if have:
            try:
                _call("PUT", f"{base}/{have['id']}", token, body)
                state[uid] = {"id": have["id"], "h": h}
                changed += 1
                continue
            except urllib.error.HTTPError as err:
                if err.code not in (404, 410):     # deleted in the calendar by hand: write it again
                    raise
        made = _call("POST", base, token, body)
        state[uid] = {"id": made["id"], "h": h}
        added += 1
    for uid in [u for u in state if u != "_cal" and u not in want]:
        try:
            _call("DELETE", f"{base}/{state[uid]['id']}", token)
        except urllib.error.HTTPError as err:
            if err.code not in (404, 410):
                raise
        del state[uid]
        removed += 1
    kv_put(c, "gcal_state", state)
    return f"{cal}: {added} added, {changed} changed, {removed} removed ({len(want)} entries)"


# ---------------------------------------------------------------- after a change: sync a few seconds later
_timer = None
_timer_lock = threading.Lock()


def soon(delay: float = 8.0) -> None:
    """Called after every change to the hub's tables; many changes in a row make one sync."""
    global _timer
    if not os.path.exists(key_file()) or os.environ.get("HUB_GCAL_OFF"):
        return
    with _timer_lock:
        if _timer:
            _timer.cancel()
        _timer = threading.Timer(delay, _run)
        _timer.daemon = True
        _timer.start()


def _run() -> None:
    from .hub_collect import collect_all
    try:
        collect_all(["calendar"])
    except Exception:  # noqa: BLE001  (logged by collect_all; never take the API down)
        pass
