"""HCG backend: the company's records (what was the HCG Hub sheet), the numbers collected every day, and the
dashboards built from both.

Only the team-only area of the print-files site on Hostinger talks to this; it adds HUB_TOKEN (header X-Hub-Token)
on the server side and passes the editor's name in X-Hub-User. The data has its own SQLite file (HUB_DB_PATH,
default hub.db next to votes.db): company records, not player data, backed up every day by the collector run.

Tables come from hub_schema.json (written from the Hub sheet's schema by _Shared/Claude/hub/export_backend_schema.py):
a row is a JSON object keyed by column name. The sheet's formula columns are computed on every read ("calc"), its
script columns are filled here ("auto").

    GET    /v1/hub/schema                      tables, columns, lists, metric catalogue
    GET    /v1/hub/settings | PUT {key: value}
    GET    /v1/hub/lists    | PUT {name: [values]}
    GET    /v1/hub/rows/{tab}                  every row, with the calculated columns
    POST   /v1/hub/rows/{tab}       {data}     add a row
    PUT    /v1/hub/rows/{tab}/{id}  {data, base}   change a row (base = its updated_at; 409 if someone was faster)
    DELETE /v1/hub/rows/{tab}/{id}
    POST   /v1/hub/import           {tab, rows, replace}   bulk load (the move from the sheet)
    GET    /v1/hub/metrics?keys=&days= | POST {day, values: {key: number}}   daily numbers
    GET    /v1/hub/dash                        everything the dashboards show (hub_dash.py)
    POST   /v1/hub/collect?only=  | GET        run the collectors (daily timer) / their last runs (hub_collect.py)
"""
import hmac
import json
import os
import re
import sqlite3
import threading
import time
import urllib.parse
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Header, HTTPException, Query

TZ = ZoneInfo("Europe/Berlin")
HUB_DB_PATH = os.environ.get("HUB_DB_PATH") or os.path.join(
    os.path.dirname(os.environ.get("DB_PATH", "data/votes.db")) or ".", "hub.db")
SCHEMA = json.loads(Path(__file__).with_name("hub_schema.json").read_text(encoding="utf-8"))
TABS = {t["slug"]: t for t in SCHEMA["tabs"]}
TAB_BY_NAME = {t["name"]: t for t in SCHEMA["tabs"]}
MAX_TEXT = 20000
NUM_TYPES = ("num", "eur", "usd", "gbp", "pct")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
METRIC_KEY_RE = re.compile(r"^[a-z0-9_.-]{1,80}$")

# The numbers on the Audience dashboard: key, label, how it gets here. "manual" ones are typed in once a week
# (no API, or the platform hides the count behind a login); the others come from hub_collect.py.
AUDIENCE = [
    ("gamefound.followers", "Gamefound followers", "manual"),
    ("discord.members", "Discord members", "Discord invite"),
    ("youtube.subscribers", "YouTube subscribers", "YouTube API"),
    ("instagram.followers", "Instagram followers", "manual"),
    ("tiktok.followers", "TikTok followers", "manual"),
    ("bgg.fans", "BGG fans", "manual"),
    ("steam.followers", "Steam followers", "Steam community"),
    ("steam.wishlists", "Steam wishlists", "manual"),
    ("play.installs", "Google Play installs", "manual"),
]
MANUAL_METRICS = {k for k, _, how in AUDIENCE if how == "manual"}
GAMEFOUND_KEY_RE = re.compile(r"^gamefound\.[a-z0-9-]{1,60}\.followers$")


def gamefound_campaigns(c) -> list[dict]:
    """Settings > Gamefound campaigns: one per line, "Name | link" (or just the link). Gamefound hides its counts
    behind a bot check, so each campaign's followers are typed in weekly, one row per campaign."""
    out = []
    for line in setting(c, "Gamefound campaigns").splitlines():
        line = line.strip()
        if not line:
            continue
        name, _, url = line.partition("|") if "|" in line else ("", "", line)
        name, url = name.strip(), url.strip()
        if not url.startswith("http"):
            name, url = name or url, ""
        tail = url.split("#")[0].split("?")[0].rstrip("/").split("/")[-1] if url else name
        slug = re.sub(r"[^a-z0-9]+", "-", tail.lower()).strip("-")[:60]
        if slug and slug not in {x["slug"] for x in out}:
            out.append({"slug": slug, "name": name or slug.replace("-", " ").title(), "url": url})
    return out


def audience(c) -> list[dict]:
    """The Audience channels: the fixed list, with the single Gamefound row replaced by one row per campaign
    once Settings > Gamefound campaigns has any."""
    out = []
    for key, label, how in AUDIENCE:
        camps = gamefound_campaigns(c) if key == "gamefound.followers" else []
        if camps:
            out += [{"key": f"gamefound.{g['slug']}.followers", "label": f"Gamefound: {g['name']}", "how": "manual",
                     "url": g["url"]} for g in camps]
        else:
            out.append({"key": key, "label": label, "how": how, "url": ""})
    return out

router = APIRouter(prefix="/v1/hub")
_lock = threading.Lock()


@contextmanager
def hdb():
    with _lock:
        conn = sqlite3.connect(HUB_DB_PATH)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()


def init_hub() -> None:
    os.makedirs(os.path.dirname(HUB_DB_PATH) or ".", exist_ok=True)
    with hdb() as c:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("""CREATE TABLE IF NOT EXISTS rows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tab TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            updated_by TEXT NOT NULL DEFAULT ''
        )""")
        c.execute("CREATE INDEX IF NOT EXISTS rows_tab ON rows(tab)")
        c.execute("""CREATE TABLE IF NOT EXISTS metrics (
            day TEXT NOT NULL,
            key TEXT NOT NULL,
            value REAL,
            source TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (day, key)
        )""")
        c.execute("CREATE INDEX IF NOT EXISTS metrics_key ON metrics(key, day)")
        c.execute("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        c.execute("""CREATE TABLE IF NOT EXISTS collect_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            collector TEXT NOT NULL,
            ok INTEGER NOT NULL,
            message TEXT NOT NULL
        )""")
        if c.execute("SELECT 1 FROM kv WHERE key = 'settings'").fetchone() is None:
            c.execute("INSERT INTO kv VALUES ('settings', ?)", (json.dumps(SCHEMA["settings"]),))
        if c.execute("SELECT 1 FROM kv WHERE key = 'lists'").fetchone() is None:
            c.execute("INSERT INTO kv VALUES ('lists', ?)", (json.dumps(SCHEMA["lists"]),))


init_hub()


def _auth(token: str | None) -> None:
    expected = os.environ.get("HUB_TOKEN", "")
    if not expected:
        raise HTTPException(503, "The hub is not set up on this server (HUB_TOKEN).")
    if not token or not hmac.compare_digest(token, expected):
        raise HTTPException(403, "Wrong hub token.")


def _user(header: str | None) -> str:
    """The editor's name from X-Hub-User (URL-encoded by the page: headers can't carry "ł")."""
    return urllib.parse.unquote(header or "").strip()[:40]


def today() -> date:
    return datetime.now(TZ).date()


def kv_get(c: sqlite3.Connection, key: str, default=None):
    r = c.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
    return json.loads(r["value"]) if r else default


def kv_put(c: sqlite3.Connection, key: str, value) -> None:
    c.execute("INSERT INTO kv VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
              (key, json.dumps(value, ensure_ascii=False)))


def setting(c: sqlite3.Connection, key: str) -> str:
    v = (kv_get(c, "settings", {}) or {}).get(key, "")
    return "" if v is None else str(v).strip()


# ---------------------------------------------------------------- values

def _num(v):
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace("€", "").replace("$", "").replace("£", "").replace("%", "").replace(" ", "")
    if "," in s and "." in s:
        s = s.replace(".", "").replace(",", ".") if s.rfind(",") > s.rfind(".") else s.replace(",", "")
    elif "," in s:
        s = s.replace(",", ".")
    elif re.fullmatch(r"-?\d{1,3}(\.\d{3})+", s):   # German thousands: 1.234 or 12.345.678 (but 12.50 stays 12.5)
        s = s.replace(".", "")
    try:
        return float(s)
    except ValueError:
        raise HTTPException(400, f"Not a number: {v}")


def _date(v):
    if v is None or v == "":
        return None
    s = str(v).strip()
    m = re.match(r"^(\d{1,2})\.(\d{1,2})\.(\d{4})$", s)   # 23.10.2026, as the sheet showed dates
    if m:
        s = f"{m.group(3)}-{int(m.group(2)):02d}-{int(m.group(1)):02d}"
    s = s[:10]
    try:
        return date.fromisoformat(s).isoformat()
    except ValueError:
        raise HTTPException(400, f"Not a date: {v}")


def clean_value(col: dict, v):
    t = col["type"]
    if t == "check":
        return v in (True, 1, "1", "true", "TRUE", "yes", "on")
    if t == "int":
        n = _num(v)
        return None if n is None else int(round(n))
    if t in NUM_TYPES:
        n = _num(v)
        if n is not None and t == "pct" and n > 1.5:   # "40" meant 40 %
            n = n / 100
        return n
    if t == "date":
        return _date(v)
    if t == "datetime":
        if v in (None, ""):
            return None
        s = str(v).strip()
        try:
            return datetime.fromisoformat(s.replace("Z", "+00:00")).isoformat(timespec="minutes")
        except ValueError:
            return _date(s)
    s = "" if v is None else str(v)
    s = s.replace("\r\n", "\n").strip()
    return s[:MAX_TEXT]


def clean_row(tab: dict, data: dict, allow_auto: bool = False) -> dict:
    out = {}
    for col in tab["columns"]:
        if col["name"] not in data or col.get("calc") or (col.get("auto") and not allow_auto):
            continue
        out[col["name"]] = clean_value(col, data[col["name"]])
    return out


def _tab(slug: str) -> dict:
    t = TABS.get(slug)
    if not t:
        raise HTTPException(404, f"No table {slug}")
    return t


# ---------------------------------------------------------------- calculated columns (the sheet's formulas)

def load_rows(c: sqlite3.Connection, tab_name: str) -> list[dict]:
    out = []
    for r in c.execute("SELECT id, data, created_at, updated_at, updated_by FROM rows WHERE tab = ? ORDER BY id",
                       (TAB_BY_NAME[tab_name]["slug"],)):
        d = json.loads(r["data"])
        d["_id"], d["_created"], d["_updated"], d["_by"] = r["id"], r["created_at"], r["updated_at"], r["updated_by"]
        out.append(d)
    return out


class Context:
    """Lookups the formulas need (products by SKU, contacts by ID...), loaded once per request."""

    def __init__(self, c: sqlite3.Connection):
        self.c = c
        self.today = today()
        self._cache = {}

    def rows(self, tab_name: str) -> list[dict]:
        if tab_name not in self._cache:
            self._cache[tab_name] = load_rows(self.c, tab_name)
        return self._cache[tab_name]

    def product(self, sku):
        if "_products" not in self._cache:
            self._cache["_products"] = {str(p.get("SKU", "")).strip(): p for p in self.rows("Products")}
        return self._cache["_products"].get(str(sku or "").strip())

    def low_stock(self) -> float:
        return _num(setting(self.c, "Low stock default")) or 0


def _d(v):
    try:
        return date.fromisoformat(v) if v else None
    except (TypeError, ValueError):
        return None


def _f(v) -> float:
    try:
        return float(v or 0)
    except (TypeError, ValueError):
        return 0.0


def derive(tab_name: str, rows: list[dict], ctx: Context) -> list[dict]:
    t = ctx.today
    if tab_name == "Checklist":
        for r in rows:
            due = _d(r.get("Due"))
            r["State"] = ("Done" if r.get("Done") else "Open" if not due else "Overdue" if due < t
                          else "This week" if due <= t + timedelta(days=7) else "Open") if r.get("Task") else ""
    elif tab_name == "Contacts":
        for r in rows:
            nf = _d(r.get("Next follow-up"))
            r["Follow-up due"] = "Due" if nf and nf <= t else ""
    elif tab_name == "Outreach Log":
        names = {str(x.get("ID", "")): x.get("Name", "") for x in ctx.rows("Contacts")}
        for r in rows:
            r["Contact"] = names.get(str(r.get("Contact ID", "")), "")
    elif tab_name == "Conventions":
        sales = ctx.rows("Sales")
        for r in rows:
            name = r.get("Name") or ""
            r["Total cost EUR"] = _f(r.get("Booth cost EUR")) + _f(r.get("Travel EUR")) + _f(r.get("Other cost EUR"))
            r["Sales EUR"] = sum(_f(x.get("Gross EUR")) - _f(x.get("Fees EUR")) for x in sales
                                 if name and x.get("Event / customer") == name)
    elif tab_name == "Comps":
        for r in rows:
            b = _f(r.get("Backers"))
            r["Avg pledge EUR"] = _f(r.get("Funded EUR")) / b if b > 0 else None
    elif tab_name == "Ads":
        for r in rows:
            spend, clicks = _f(r.get("Spend EUR")), _f(r.get("Clicks"))
            r["CTR"] = clicks / _f(r.get("Impressions")) if _f(r.get("Impressions")) > 0 else None
            r["CPC EUR"] = spend / clicks if clicks > 0 else None
            r["Per signup EUR"] = spend / _f(r.get("Signups")) if _f(r.get("Signups")) > 0 else None
            r["Per follower EUR"] = spend / _f(r.get("Followers")) if _f(r.get("Followers")) > 0 else None
            r["ROAS"] = _f(r.get("Revenue EUR")) / spend if spend > 0 else None
    elif tab_name == "Production":
        for r in rows:
            planned = _d(r.get("Planned"))
            r["State"] = ("Done" if r.get("Actual") else "No date" if not planned else "Late" if planned < t
                          else "Due soon" if planned <= t + timedelta(days=14) else "Planned") if r.get("Milestone") else ""
    elif tab_name == "Stock":
        low = ctx.low_stock()
        for r in rows:
            p = ctx.product(r.get("SKU"))
            r["Product"] = p.get("Product", "") if p else ""
            avail = _f(r.get("On hand")) - _f(r.get("Reserved"))
            r["Available"] = avail
            reorder = r.get("Reorder at")
            r["Status"] = "Low" if avail <= (low if reorder in (None, "") else _f(reorder)) else "OK"
    elif tab_name == "Sales":
        for r in rows:
            p = ctx.product(r.get("SKU"))
            r["Product"] = p.get("Product", "") if p else ""
            r["Net EUR"] = _f(r.get("Gross EUR")) - _f(r.get("Fees EUR"))
    return rows


def derived_rows(ctx: Context, tab_name: str) -> list[dict]:
    """A table's rows with its calculated columns (cached on the context, so dashboards can reuse them)."""
    key = "_derived_" + tab_name
    if key not in ctx._cache:
        ctx._cache[key] = derive(tab_name, [dict(r) for r in ctx.rows(tab_name)], ctx)
    return ctx._cache[key]


def _next_id(c: sqlite3.Connection, tab_slug: str, col: str, prefix: str) -> str:
    n = 0
    for (data,) in c.execute("SELECT data FROM rows WHERE tab = ?", (tab_slug,)):
        m = re.match(rf"^{prefix}(\d+)$", str(json.loads(data).get(col, "")))
        if m:
            n = max(n, int(m.group(1)))
    return f"{prefix}{n + 1:04d}"


def _fill_auto(c: sqlite3.Connection, tab: dict, data: dict, creating: bool) -> None:
    now = datetime.now(TZ).isoformat(timespec="minutes")
    name = tab["name"]
    if name == "Contacts" and not data.get("ID") and creating:
        data["ID"] = _next_id(c, tab["slug"], "ID", "C")
    elif name == "Support":
        if not data.get("ID") and creating:
            data["ID"] = _next_id(c, tab["slug"], "ID", "S")
        data["Updated"] = now
    elif name == "Playtests" and creating and not data.get("Received"):
        data["Received"] = now


def _changed() -> None:
    """A table changed: the Google calendar follows a few seconds later (if it is set up)."""
    from .hub_gcal import soon
    soon()


# ---------------------------------------------------------------- the outreach funnel
FUNNEL = ["Lead", "To contact", "Contacted", "Replied", "Negotiating", "Copy sent", "App key sent", "Content scheduled",
          "Published", "Partner"]                      # the board's columns, in order
FUNNEL_EXITS = ["Declined", "No reply"]
# the funnel chart's steps: a physical copy and an app key (Steam / Android) are the same step
FUNNEL_LEVELS = [("Lead", ["Lead"]), ("To contact", ["To contact"]), ("Contacted", ["Contacted"]), ("Replied", ["Replied"]),
                 ("Negotiating", ["Negotiating"]), ("Copy or app key sent", ["Copy sent", "App key sent"]),
                 ("Content scheduled", ["Content scheduled"]), ("Published", ["Published"]), ("Partner", ["Partner"])]
LEVEL_OF = {s: i for i, (_, stages) in enumerate(FUNNEL_LEVELS) for s in stages}
# the next follow-up when a contact arrives at a stage: days from today ("setting" = Settings > Follow-up days),
# None = clear it, absent = leave it as it is
FOLLOW_UP_RULE = {"Contacted": "setting", "Replied": 2, "Negotiating": 5, "Copy sent": 14, "App key sent": 7,
                  "Published": 7, "Partner": 90, "Declined": None, "No reply": None}
STAGE_LOG_KIND = {"Contacted": "Email", "Copy sent": "Copy sent", "App key sent": "App key sent", "Published": "Content published"}


def _stage_moved(c: sqlite3.Connection, data: dict, old_stage: str, given: dict, user: str, log: bool = True,
                 note: str = "") -> None:
    """A contact arrived at a new stage: follow-up date, last contact, furthest stage, a line in the Outreach Log
    (log=False: the caller writes its own line, as the Gmail sync does for the mail that moved the contact)."""
    new = data.get("Stage") or ""
    if not new or new == old_stage:
        return
    t = today()
    rule = FOLLOW_UP_RULE.get(new, "keep")
    if "Next follow-up" not in given and rule != "keep":
        days = (_num(setting(c, "Follow-up days")) or 7) if rule == "setting" else rule
        data["Next follow-up"] = None if days is None else (t + timedelta(days=int(days))).isoformat()
    if new == "Contacted":
        data["Last contact"] = t.isoformat()
    if new in LEVEL_OF:
        data["_furthest"] = max(int(data.get("_furthest") or 0), LEVEL_OF[new])
    if not log or (old_stage == "" and new in ("Lead", "To contact")):
        return                                     # a new contact that hasn't been written to: nothing to log yet
    log_tab = TAB_BY_NAME["Outreach Log"]
    entry = clean_row(log_tab, {"Date": t.isoformat(), "Contact ID": data.get("ID", ""), "Kind": STAGE_LOG_KIND.get(new, "Other"),
                                "Game": data.get("Game", ""), "Summary": f"Stage: {old_stage or 'new'} → {new}{note}", "Owner": user})
    now = int(time.time())
    c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
              (log_tab["slug"], json.dumps(entry, ensure_ascii=False), now, now, user))


def _out(tab: dict, rows: list[dict]) -> list[dict]:
    return [{k: v for k, v in r.items()} for r in rows]


# ---------------------------------------------------------------- endpoints

@router.get("/schema")
def get_schema(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        return {"tabs": SCHEMA["tabs"], "audience": audience(c)}


@router.get("/settings")
def get_settings(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        return {"settings": kv_get(c, "settings", {}), "lists": kv_get(c, "lists", {})}


@router.put("/settings")
def put_settings(values: dict = Body(...), x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        s = kv_get(c, "settings", {})
        for k, v in values.items():
            if not isinstance(k, str) or len(k) > 80:
                raise HTTPException(400, "Bad setting name")
            s[k] = "" if v is None else str(v)[:2000]
        kv_put(c, "settings", s)
        return {"settings": s}


@router.put("/lists")
def put_lists(values: dict = Body(...), x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        lists = kv_get(c, "lists", {})
        for k, v in values.items():
            if not isinstance(v, list):
                raise HTTPException(400, f"List {k}: give a list of values")
            lists[k] = [str(x).strip()[:120] for x in v if str(x).strip()]
        kv_put(c, "lists", lists)
        return {"lists": lists}


@router.get("/rows/{tab}")
def get_rows(tab: str, x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    t = _tab(tab)
    with hdb() as c:
        return {"rows": _out(t, derived_rows(Context(c), t["name"]))}


def _row_out(c: sqlite3.Connection, t: dict, row_id: int) -> dict:
    ctx = Context(c)
    return next(r for r in derived_rows(ctx, t["name"]) if r["_id"] == row_id)


@router.post("/rows/{tab}")
def add_row(tab: str, body: dict = Body(...), x_hub_token: str | None = Header(None),
            x_hub_user: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    t = _tab(tab)
    data = clean_row(t, body.get("data") or {})
    if not any(v not in (None, "", False) for v in data.values()):
        raise HTTPException(400, "The row is empty.")
    now = int(time.time())
    with hdb() as c:
        _fill_auto(c, t, data, creating=True)
        if t["name"] == "Contacts" and data.get("Stage"):
            _stage_moved(c, data, "", body.get("data") or {}, _user(x_hub_user))
        cur = c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
                        (t["slug"], json.dumps(data, ensure_ascii=False), now, now, _user(x_hub_user)))
        out = {"row": _row_out(c, t, cur.lastrowid)}
    _changed()
    return out


@router.put("/rows/{tab}/{row_id}")
def change_row(tab: str, row_id: int, body: dict = Body(...), x_hub_token: str | None = Header(None),
               x_hub_user: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    t = _tab(tab)
    with hdb() as c:
        r = c.execute("SELECT data, updated_at FROM rows WHERE id = ? AND tab = ?", (row_id, t["slug"])).fetchone()
        if not r:
            raise HTTPException(404, "That row is gone. Someone may have deleted it.")
        base = body.get("base")
        if base is not None and int(base) != r["updated_at"]:
            raise HTTPException(409, "Someone else changed this row in the meantime. Reload and try again.")
        data = json.loads(r["data"])
        old_stage = data.get("Stage") or ""
        old_status = data.get("Status") or ""
        data.update(clean_row(t, body.get("data") or {}))
        _fill_auto(c, t, data, creating=False)
        if t["name"] == "Contacts":
            _stage_moved(c, data, old_stage, body.get("data") or {}, _user(x_hub_user))
        elif t["name"] == "Orders":
            from .store import order_status_changed
            order_status_changed(c, data, old_status)
        c.execute("UPDATE rows SET data = ?, updated_at = ?, updated_by = ? WHERE id = ?",
                  (json.dumps(data, ensure_ascii=False), max(int(time.time()), r["updated_at"] + 1),
                   _user(x_hub_user), row_id))
        out = {"row": _row_out(c, t, row_id)}
    _changed()
    return out


@router.delete("/rows/{tab}/{row_id}")
def delete_row(tab: str, row_id: int, x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    t = _tab(tab)
    with hdb() as c:
        if c.execute("DELETE FROM rows WHERE id = ? AND tab = ?", (row_id, t["slug"])).rowcount == 0:
            raise HTTPException(404, "That row is gone already.")
        if t["name"] == "Contacts":     # its Gmail threads lose their stage labels with the next run
            c.execute("UPDATE mail_threads SET contact = 0 WHERE contact = ?", (row_id,))
    _changed()
    return {"ok": True}


@router.post("/import")
def import_rows(body: dict = Body(...), x_hub_token: str | None = Header(None)) -> dict:
    """Bulk load: {tab, rows: [{column: value}], replace: false}. Script columns are taken as given."""
    _auth(x_hub_token)
    t = _tab(str(body.get("tab", "")))
    rows = body.get("rows") or []
    now = int(time.time())
    with hdb() as c:
        if body.get("replace"):
            c.execute("DELETE FROM rows WHERE tab = ?", (t["slug"],))
        n = 0
        for raw in rows:
            data = clean_row(t, raw, allow_auto=True)
            if not any(v not in (None, "", False) for v in data.values()):
                continue
            _fill_auto(c, t, data, creating=True)
            c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, 'import')",
                      (t["slug"], json.dumps(data, ensure_ascii=False), now, now))
            n += 1
    _changed()
    return {"imported": n}


# ---------------------------------------------------------------- metrics

def put_metric(c: sqlite3.Connection, day: str, key: str, value, source: str) -> None:
    if value is None:
        c.execute("DELETE FROM metrics WHERE day = ? AND key = ?", (day, key))
        return
    c.execute("""INSERT INTO metrics (day, key, value, source, updated_at) VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT(day, key) DO UPDATE SET value = excluded.value, source = excluded.source,
                 updated_at = excluded.updated_at""", (day, key, float(value), source, int(time.time())))


def series(c: sqlite3.Connection, keys: list[str], days: int) -> dict:
    since = (today() - timedelta(days=days)).isoformat()
    out = {k: [] for k in keys}
    if not keys:
        return out
    marks = ",".join("?" * len(keys))
    for r in c.execute(f"SELECT day, key, value FROM metrics WHERE key IN ({marks}) AND day >= ? ORDER BY day",
                       [*keys, since]):
        out[r["key"]].append([r["day"], r["value"]])
    return out


@router.get("/metrics")
def get_metrics(keys: str = Query(""), days: int = Query(400, ge=1, le=4000),
                x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        return {"series": series(c, [k for k in keys.split(",") if k], days)}


@router.post("/metrics")
def post_metrics(body: dict = Body(...), x_hub_token: str | None = Header(None)) -> dict:
    """Numbers typed in: {day: "2026-11-02" (default today), values: {"instagram.followers": 812, ...}}."""
    _auth(x_hub_token)
    day = _date(body.get("day")) or today().isoformat()
    values = body.get("values") or {}
    with hdb() as c:
        for k, v in values.items():
            if not METRIC_KEY_RE.match(str(k)) or not (k in MANUAL_METRICS or GAMEFOUND_KEY_RE.match(str(k))
                                                       or str(k).startswith("custom.")):
                raise HTTPException(400, f"{k} is collected automatically or unknown.")
            put_metric(c, day, k, _num(v), "manual")
        return {"series": series(c, list(values), 400)}


# ---------------------------------------------------------------- dashboards and collectors

@router.get("/dash")
def get_dash(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    from .hub_dash import build
    return build()


@router.post("/collect")
def run_collect(only: str = Query(""), x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    from .hub_collect import collect_all
    return {"results": collect_all([x for x in only.split(",") if x])}


@router.get("/collect")
def collect_status(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    from .hub_collect import status
    return status()


from .hub_calendar import router as _calendar_router  # noqa: E402  (the company calendar and its .ics feeds)
from .hub_mail import router as _mail_router  # noqa: E402  (the team's Gmail drives the outreach funnel)
from .store import router as _store_router  # noqa: E402  (the store: Stripe Checkout, orders; public)

router.include_router(_calendar_router)
router.include_router(_mail_router)
router.include_router(_store_router)
