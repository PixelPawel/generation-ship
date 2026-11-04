"""The company calendar: every date in the hub's tables as calendar entries, for the dashboards and as .ics feeds
that Google Calendar, Outlook, Apple Calendar or Thunderbird subscribe to (they refresh on their own schedule).

    GET  /v1/hub/events?start=&end=          the entries between two dates (hub token), for the Calendar page
    GET  /v1/hub/calendar                    the feed links (hub token)
    POST /v1/hub/calendar/rotate             new feed links; the old ones stop working (hub token)
    GET  /v1/hub/calendar/{secret}/{feed}.ics   a feed; the secret in the link is its only protection

What becomes an entry: the Calendar table (the team's own dates), conventions (their days and booth deadlines),
open production milestones, open checklist tasks, open payments and income, planned posts, follow-ups.
"""
import secrets
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import Response

from .hub import TZ, Context, _auth, _d, _f, derived_rows, hdb, kv_get, kv_put, setting, today

router = APIRouter()   # mounted into the hub router (/v1/hub) at the end of hub.py

FEEDS = {   # feed -> (name in the calendar app, categories in it)
    "all": ("Happy Capy Games", None),
    "team": ("HCG: team dates", {"team"}),
    "conventions": ("HCG: conventions", {"conventions"}),
    "production": ("HCG: milestones and tasks", {"milestones", "tasks"}),
    "money": ("HCG: payments", {"money"}),
    "content": ("HCG: posts", {"content"}),
    "outreach": ("HCG: follow-ups", {"outreach"}),
}


def _eur(v) -> str:
    return f"{_f(v):,.2f} €".replace(",", "X").replace(".", ",").replace("X", ".")


def _time(text: str):
    """'14:00' or '14:00-15:30' -> (start, end) as (h, m) pairs; None when empty or unreadable."""
    try:
        parts = [p.strip() for p in str(text or "").replace("–", "-").split("-") if p.strip()]
        if not parts:
            return None
        hm = [tuple(int(x) for x in p.split(":")[:2]) if ":" in p else (int(p), 0) for p in parts]
        start = hm[0]
        end = hm[1] if len(hm) > 1 else ((start[0] + 1) % 24, start[1])
        return start, end
    except (ValueError, IndexError):
        return None


def entries(c) -> list[dict]:
    """Every calendar entry: {uid, cat, title, start, end (inclusive), time, detail, area, tab, id}."""
    ctx = Context(c)
    out = []

    def add(cat, uid, title, start, end=None, time=None, detail="", area="", tab="", row=None):
        if not start:
            return
        out.append({"uid": uid, "cat": cat, "title": title, "start": start, "end": end if end and end >= start else start,
                    "time": time, "detail": detail, "area": area, "tab": tab, "id": row["_id"] if row else None})

    for r in derived_rows(ctx, "Calendar"):
        add("team", f"cal-{r['_id']}", r.get("Title") or r.get("Kind") or "Date", r.get("Date"), r.get("End"),
            r.get("Time") or None, " · ".join(x for x in (r.get("Kind"), r.get("Where"), r.get("Owner"), r.get("Notes")) if x),
            "calendar", "calendar", r)
    for r in derived_rows(ctx, "Conventions"):
        where = ", ".join(x for x in (r.get("City"), r.get("Country")) if x)
        add("conventions", f"conv-{r['_id']}", f"{r.get('Name') or 'Convention'}" + (f" ({where})" if where else ""),
            r.get("Start"), r.get("End"), None, " · ".join(x for x in (r.get("Status"), r.get("URL")) if x), "events", "conventions", r)
        add("conventions", f"conv-{r['_id']}-deadline", f"Booth deadline: {r.get('Name') or 'convention'}",
            r.get("Booth deadline"), None, None, r.get("Status") or "", "events", "conventions", r)
    for r in derived_rows(ctx, "Production"):
        if r.get("State") in ("Late", "Due soon", "Planned"):
            what = " / ".join(x for x in (r.get("SKU"), r.get("Project")) if x)
            add("milestones", f"ms-{r['_id']}", f"{r.get('Milestone')}" + (f" ({what})" if what else ""), r.get("Planned"),
                None, None, " · ".join(x for x in (r.get("State"), r.get("Owner")) if x), "production", "production", r)
    for r in derived_rows(ctx, "Checklist"):
        if r.get("Task") and not r.get("Done"):
            add("tasks", f"task-{r['_id']}", r["Task"], r.get("Due"), None, None,
                " · ".join(x for x in (r.get("Project"), r.get("Owner"), r.get("Notes")) if x), "production", "checklist", r)
    for r in derived_rows(ctx, "Money"):
        if r.get("Kind") in ("Payment", "Income") and not r.get("Done"):
            label = "To pay" if r["Kind"] == "Payment" else "To receive"
            add("money", f"money-{r['_id']}", f"{label}: {r.get('Description') or r.get('Category') or ''} ({_eur(r.get('Amount EUR'))})",
                r.get("Date"), None, None, " · ".join(x for x in (r.get("Category"), r.get("Project")) if x), "money", "money", r)
    for r in derived_rows(ctx, "Content"):
        if r.get("Status") != "Posted":
            add("content", f"post-{r['_id']}", f"Post: {' · '.join(x for x in (r.get('Platform'), r.get('Topic')) if x) or 'post'}",
                r.get("Date"), None, None, " · ".join(x for x in (r.get("Format"), r.get("Status"), r.get("Owner")) if x),
                "marketing", "content", r)
    for r in derived_rows(ctx, "Contacts"):
        if r.get("Next follow-up") and r.get("Stage") not in ("Declined", "No reply"):
            add("outreach", f"follow-{r['_id']}", f"Follow up: {r.get('Name') or 'contact'}", r.get("Next follow-up"), None,
                None, " · ".join(x for x in (r.get("Company / channel"), r.get("Stage"), r.get("Owner")) if x),
                "outreach", "contacts", r)
    out.sort(key=lambda e: (e["start"], e["time"] or "", e["title"]))
    return out


def _secret(c) -> str:
    s = kv_get(c, "calendar_secret")
    if not s:
        s = secrets.token_urlsafe(24)
        kv_put(c, "calendar_secret", s)
    return s


def _feeds(c) -> list[dict]:
    s = _secret(c)
    return [{"feed": k, "name": name, "url": f"https://api.happycapygames.com/v1/hub/calendar/{s}/{k}.ics"}
            for k, (name, _) in FEEDS.items()]


@router.get("/events")
def get_events(start: str = "", end: str = "", x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    t = today()
    lo = _d(start) or (t - timedelta(days=45))
    hi = _d(end) or (t + timedelta(days=180))
    with hdb() as c:
        evs = [e for e in entries(c) if _d(e["end"]) >= lo and _d(e["start"]) <= hi]
    return {"events": evs, "today": t.isoformat()}


@router.get("/calendar")
def calendar_links(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        return {"feeds": _feeds(c)}


@router.post("/calendar/rotate")
def calendar_rotate(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        kv_put(c, "calendar_secret", secrets.token_urlsafe(24))
        return {"feeds": _feeds(c)}


# ---------------------------------------------------------------- iCalendar (RFC 5545)

def _esc(s: str) -> str:
    return str(s).replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r\n", "\n").replace("\n", "\\n")


def _fold(line: str) -> str:
    """Lines longer than 75 octets continue on the next line after a space."""
    raw = line.encode("utf-8")
    if len(raw) <= 75:
        return line
    parts, cur = [], b""
    for ch in line:
        b = ch.encode("utf-8")
        if len(cur) + len(b) > (75 if not parts else 74):
            parts.append(cur.decode("utf-8"))
            cur = b""
        cur += b
    parts.append(cur.decode("utf-8"))
    return "\r\n ".join(parts)


def ics(evs: list[dict], name: str, dash_url: str) -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Happy Capy Games//HCG dashboards//EN", "CALSCALE:GREGORIAN",
             "METHOD:PUBLISH", f"X-WR-CALNAME:{_esc(name)}", "X-WR-TIMEZONE:Europe/Berlin",
             "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H"]
    for e in evs:
        lines += ["BEGIN:VEVENT", f"UID:{e['uid']}@happycapygames.com", f"DTSTAMP:{stamp}"]
        tm = _time(e["time"]) if e["time"] else None
        if tm:
            d0 = date.fromisoformat(e["start"])
            (h0, m0), (h1, m1) = tm
            a = datetime(d0.year, d0.month, d0.day, h0, m0, tzinfo=TZ)
            b = datetime(d0.year, d0.month, d0.day, h1, m1, tzinfo=TZ)
            if b <= a:
                b += timedelta(days=1)
            lines += [f"DTSTART:{a.astimezone(timezone.utc):%Y%m%dT%H%M%SZ}", f"DTEND:{b.astimezone(timezone.utc):%Y%m%dT%H%M%SZ}"]
        else:   # all day; DTEND is the day after the last one
            lines += [f"DTSTART;VALUE=DATE:{e['start'].replace('-', '')}",
                      f"DTEND;VALUE=DATE:{(date.fromisoformat(e['end']) + timedelta(days=1)):%Y%m%d}"]
        lines += [f"SUMMARY:{_esc(e['title'])}", f"CATEGORIES:{_esc(e['cat'])}"]
        if e["detail"]:
            lines.append(f"DESCRIPTION:{_esc(e['detail'])}")
        if dash_url and e["area"]:
            lines.append(f"URL:{dash_url.split('#')[0]}#{e['area']}/{e['tab']}/{e['id']}")
        lines += ["TRANSP:TRANSPARENT", "END:VEVENT"]
    lines.append("END:VCALENDAR")
    return "\r\n".join(_fold(x) for x in lines) + "\r\n"


@router.get("/calendar/{secret}/{feed}.ics")
def calendar_feed(secret: str, feed: str) -> Response:
    if feed not in FEEDS:
        raise HTTPException(404, "No such feed.")
    with hdb() as c:
        expected = kv_get(c, "calendar_secret")
        if not expected or not secrets.compare_digest(secret, expected):
            raise HTTPException(404, "No such feed.")
        name, cats = FEEDS[feed]
        t = today()
        evs = [e for e in entries(c) if (cats is None or e["cat"] in cats)
               and _d(e["end"]) >= t - timedelta(days=90)]     # what's past three months is history
        body = ics(evs, name, setting(c, "Dashboards URL"))
    return Response(body, media_type="text/calendar; charset=utf-8",
                    headers={"Cache-Control": "no-cache", "Content-Disposition": f'inline; filename="{feed}.ics"'})
