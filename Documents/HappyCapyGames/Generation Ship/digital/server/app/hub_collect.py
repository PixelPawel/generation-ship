"""The daily collector run (POST /v1/hub/collect, called by deploy/hub-collect.timer every morning).

Each collector writes daily numbers into the hub's metrics table and logs one line. A collector without its
setting (Discord invite, YouTube channel id + YOUTUBE_API_KEY, BGG ids) says what is missing instead of failing.

    game     this server's own data (votes.db): finished games per day by mode and platform, players, Android
             unlocks, crash reports; the last 7 days are recounted every run, all days on the first run
    steam    every app in Settings > Steam app ids: reviews (count, positive), players right now, followers
             (members of the game's Steam community group)
    discord  Settings > Discord invite: members and members online (Discord's public invite info)
    youtube  Settings > YouTube channel id + YOUTUBE_API_KEY in .env: subscribers, views, videos
    bgg      Settings > BGG ids: owned, wishlisted, ratings, average rating (BGG_TOKEN in .env if BGG asks for one)
    backup   a copy of hub.db in hub-backups/ next to it (30 days kept)
"""
import json
import os
import re
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta

from .hub import HUB_DB_PATH, TZ, hdb, kv_get, kv_put, put_metric, setting, today

UA = "HappyCapyGames-Hub/1.0 (+https://happycapygames.com)"
BACKUP_KEEP = 30


def _get(url: str, headers: dict | None = None, timeout: int = 20) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if r.geturl().rstrip("/") != url.rstrip("/") and urllib.parse.urlparse(r.geturl()).path in ("", "/"):
            raise RuntimeError(f"redirected to {r.geturl()}")
        return r.read()


def _json(url: str, headers: dict | None = None) -> dict:
    return json.loads(_get(url, headers))


def _ids(text: str) -> list[str]:
    return [x for x in re.split(r"[\s,;|]+", text or "") if x]


# ---------------------------------------------------------------- this server's own data

def _berlin_day(ts: int) -> str:
    return datetime.fromtimestamp(ts, TZ).date().isoformat()


def collect_game(c) -> str:
    from .main import DB_PATH
    if not os.path.exists(DB_PATH):
        return "no votes.db yet"
    first_run = c.execute("SELECT 1 FROM metrics WHERE key LIKE 'game.%' LIMIT 1").fetchone() is None
    since_day = date(2000, 1, 1) if first_run else today() - timedelta(days=7)
    since_ts = int(datetime(since_day.year, since_day.month, since_day.day, tzinfo=TZ).timestamp())
    src = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        days: dict[str, dict] = {}

        def bump(day, key, n=1):
            days.setdefault(day, {})
            days[day][key] = days[day].get(key, 0) + n

        players: dict[str, set] = {}
        tables = {r[0] for r in src.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if "scores" in tables:
            for player, source, platform, ts in src.execute(
                    "SELECT player, source, platform, updated_at FROM scores WHERE updated_at >= ?", (since_ts,)):
                d = _berlin_day(ts)
                bump(d, f"game.games.{source}")
                bump(d, f"game.platform.{(platform or 'other').lower()}")
                bump(d, "game.games")
                players.setdefault(d, set()).add(player)
        if "unlock_redemptions" in tables:
            for platform, ts in src.execute(
                    "SELECT platform, redeemed_at FROM unlock_redemptions WHERE redeemed_at >= ?", (since_ts,)):
                bump(_berlin_day(ts), "game.unlocks")
        if "crashes" in tables:
            for (ts,) in src.execute("SELECT created_at FROM crashes WHERE created_at >= ?", (since_ts,)):
                bump(_berlin_day(ts), "game.crashes")
    finally:
        src.close()
    for d, ps in players.items():
        days.setdefault(d, {})["game.players"] = len(ps)
    # a recounted day starts from zero, so a day that had games and now has fewer is right
    keys = {k for v in days.values() for k in v} | {"game.games", "game.players", "game.unlocks", "game.crashes"}
    d = since_day if not first_run else (min((date.fromisoformat(x) for x in days), default=today()))
    while d <= today():
        day = d.isoformat()
        for k in keys:
            put_metric(c, day, k, days.get(day, {}).get(k, 0), "game")
        d += timedelta(days=1)
    return f"{sum(v.get('game.games', 0) for v in days.values())} games in {len(days)} days" + (" (all history)" if first_run else "")


# ---------------------------------------------------------------- stores and platforms

REVIEW_TIP_RE = re.compile(r'data-tooltip-html="(\d+)% of the ([\d,.]+) user reviews(?! in the last 30 days)')


def store_reviews(html: str):
    """(reviews, positive) from a Steam store page: its review summary tooltip, the biggest count that isn't
    "last 30 days". The appreviews endpoint redirects to the store's front page from our server, so this is the
    fallback."""
    tips = [(int(p), int(re.sub(r"[,.]", "", n))) for p, n in REVIEW_TIP_RE.findall(html)]
    if tips:
        pct, total = max(tips, key=lambda x: x[1])
        return total, round(total * pct / 100)
    if "No user reviews" in html:
        return 0, 0
    return None


def collect_steam(c) -> str:
    apps = _ids(setting(c, "Steam app ids"))
    if not apps:
        return "skipped: no Settings > Steam app ids"
    day, notes, names = today().isoformat(), [], kv_get(c, "steam_names", {}) or {}
    for app in apps:
        got = []
        try:
            d = _json(f"https://store.steampowered.com/api/appdetails?appids={app}&filters=basic,recommendations")
            data = (d.get(app) or {}).get("data") or {}
            if data.get("name"):
                names[app] = data["name"]
        except Exception as e:  # noqa: BLE001  (one source failing must not stop the others)
            notes.append(f"{app} details: {e}")
        reviews = None
        try:
            q = _json(f"https://store.steampowered.com/appreviews/{app}?json=1&language=all&purchase_type=all"
                      f"&num_per_page=0&filter=recent").get("query_summary") or {}
            if "total_reviews" in q:
                reviews = (q["total_reviews"], q.get("total_positive", 0))
        except Exception:  # noqa: BLE001  (redirects to the store's front page from the server: use the store page)
            try:
                reviews = store_reviews(_get(f"https://store.steampowered.com/app/{app}/?l=english",
                                             {"Cookie": "birthtime=470703601; wants_mature_content=1"}).decode("utf-8", "replace"))
            except Exception as e:  # noqa: BLE001
                notes.append(f"{app} reviews: {e}")
        if reviews:
            put_metric(c, day, f"steam.{app}.reviews", reviews[0], "steam")
            put_metric(c, day, f"steam.{app}.positive", reviews[1], "steam")
            got.append(f"{reviews[0]} reviews")
        try:
            n = _json(f"https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid={app}")
            count = n["response"].get("player_count", 0) if (n.get("response") or {}).get("result") == 1 else 0
        except urllib.error.HTTPError as e:
            count = 0 if e.code == 404 else None   # 404 / result 42: nobody playing right now
            if count is None:
                notes.append(f"{app} players: {e}")
        except Exception as e:  # noqa: BLE001
            count = None
            notes.append(f"{app} players: {e}")
        if count is not None:
            put_metric(c, day, f"steam.{app}.players", count, "steam")
            got.append(f"{count} playing")
        try:
            xml = ET.fromstring(_get(f"https://steamcommunity.com/games/{app}/memberslistxml/?xml=1"))
            members = xml.findtext("groupDetails/memberCount") or xml.findtext("memberCount")
            if members is not None:
                put_metric(c, day, f"steam.{app}.followers", int(members), "steam")
                got.append(f"{members} followers")
        except ET.ParseError:
            pass   # no community group (a demo or DLC): Steam answers with an HTML error page
        except Exception as e:  # noqa: BLE001
            notes.append(f"{app} followers: {e}")
        notes.insert(0, f"{names.get(app, app)}: {', '.join(got) or 'nothing'}")
    kv_put(c, "steam_names", names)
    # the Audience total: followers of all apps together
    total = c.execute("SELECT SUM(value) FROM metrics WHERE day = ? AND key LIKE 'steam.%.followers'", (day,)).fetchone()[0]
    if total is not None:
        put_metric(c, day, "steam.followers", total, "steam")
    return "; ".join(notes)


def collect_discord(c) -> str:
    invite = setting(c, "Discord invite")
    if not invite:
        return "skipped: no Settings > Discord invite"
    code = invite.rstrip("/").split("/")[-1]
    d = _json(f"https://discord.com/api/v10/invites/{urllib.parse.quote(code)}?with_counts=true")
    day = today().isoformat()
    put_metric(c, day, "discord.members", d.get("approximate_member_count"), "discord")
    put_metric(c, day, "discord.online", d.get("approximate_presence_count"), "discord")
    return f"{d.get('approximate_member_count')} members, {d.get('approximate_presence_count')} online"


def collect_youtube(c) -> str:
    channel, key = setting(c, "YouTube channel id"), os.environ.get("YOUTUBE_API_KEY", "")
    if not channel or not key:
        return "skipped: " + " and ".join(x for x, ok in (("Settings > YouTube channel id", channel),
                                                          ("YOUTUBE_API_KEY on the server", key)) if not ok)
    d = _json("https://www.googleapis.com/youtube/v3/channels?part=statistics&id="
              f"{urllib.parse.quote(channel)}&key={urllib.parse.quote(key)}")
    items = d.get("items") or []
    if not items:
        raise RuntimeError(f"no channel {channel}")
    s = items[0]["statistics"]
    day = today().isoformat()
    put_metric(c, day, "youtube.subscribers", int(s.get("subscriberCount", 0)), "youtube")
    put_metric(c, day, "youtube.views", int(s.get("viewCount", 0)), "youtube")
    put_metric(c, day, "youtube.videos", int(s.get("videoCount", 0)), "youtube")
    return f"{s.get('subscriberCount')} subscribers, {s.get('viewCount')} views"


def collect_bgg(c) -> str:
    ids = _ids(setting(c, "BGG ids"))
    if not ids:
        return "skipped: no Settings > BGG ids"
    token = os.environ.get("BGG_TOKEN", "")
    if not token:   # since 2025-07 BGG answers 401 without one
        return "skipped: BGG_TOKEN on the server (register an app at boardgamegeek.com/applications, then make a token)"
    try:
        xml = ET.fromstring(_get("https://boardgamegeek.com/xmlapi2/thing?stats=1&id=" + ",".join(ids),
                                 {"Authorization": f"Bearer {token}"}))
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise RuntimeError("BGG refused the token (401): check BGG_TOKEN on the server") from None
        raise
    day, out = today().isoformat(), []
    for item in xml.findall("item"):
        gid = item.get("id")
        r = item.find("statistics/ratings")
        if r is None:
            continue
        vals = {k: r.find(k).get("value") for k in ("usersrated", "average", "owned", "wishing") if r.find(k) is not None}
        for k, v in vals.items():
            put_metric(c, day, f"bgg.{gid}.{k}", float(v), "bgg")
        out.append(f"{gid}: {vals.get('owned')} owned, {vals.get('wishing')} wishing")
    return "; ".join(out) or "no items"


def backup(c) -> str:
    folder = os.path.join(os.path.dirname(HUB_DB_PATH) or ".", "hub-backups")
    os.makedirs(folder, exist_ok=True)
    dest = os.path.join(folder, f"hub-{today().isoformat()}.db")
    out = sqlite3.connect(dest)
    try:
        c.backup(out)
    finally:
        out.close()
    cutoff = time.time() - BACKUP_KEEP * 86400
    for n in os.listdir(folder):
        p = os.path.join(folder, n)
        if n.startswith("hub-") and n.endswith(".db") and os.path.getmtime(p) < cutoff:
            os.remove(p)
    return f"{os.path.basename(dest)} ({os.path.getsize(dest) // 1024} KB)"


COLLECTORS = [("game", collect_game), ("steam", collect_steam), ("discord", collect_discord),
              ("youtube", collect_youtube), ("bgg", collect_bgg), ("backup", backup)]


def collect_all(only: list[str] | None = None) -> list[dict]:
    results = []
    for name, fn in COLLECTORS:
        if only and name not in only:
            continue
        with hdb() as c:
            try:
                msg, ok = fn(c), True
            except Exception as e:  # noqa: BLE001
                msg, ok = f"{type(e).__name__}: {e}", False
            msg = str(msg)[:500]
            c.execute("INSERT INTO collect_log (at, collector, ok, message) VALUES (?, ?, ?, ?)",
                      (int(time.time()), name, int(ok), msg))
            c.execute("DELETE FROM collect_log WHERE at < ?", (int(time.time()) - 90 * 86400,))
        results.append({"collector": name, "ok": ok, "message": msg})
    return results


def status() -> dict:
    with hdb() as c:
        last = {}
        for r in c.execute("SELECT collector, at, ok, message FROM collect_log ORDER BY id"):
            last[r["collector"]] = {"at": r["at"], "ok": bool(r["ok"]), "message": r["message"]}
    return {"collectors": [{"collector": n, **last.get(n, {"at": None, "ok": None, "message": "never ran"})}
                           for n, _ in COLLECTORS]}
