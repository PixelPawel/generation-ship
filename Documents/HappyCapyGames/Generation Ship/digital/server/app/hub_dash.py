"""Everything the dashboards show, in one answer (GET /v1/hub/dash). Mirrors the HCG Hub sheet's Dashboard tab
(_Shared/Claude/hub/layouts.py) and adds the game's own numbers from this server.

Areas: overview (tiles + what needs attention), game, audience, outreach, marketing, events, sales, money,
production, playtests, community, collect (the collectors' last runs).
"""
import os
import sqlite3
from collections import Counter, defaultdict
from datetime import date, timedelta

from .hub import AUDIENCE, Context, _d, _f, derived_rows, hdb, kv_get, series, setting, today

CLOSED_STAGES = {"Declined", "No reply"}
OPEN_SUPPORT = {"New", "In progress"}


def _latest(points: list, before: date | None = None):
    """The newest [day, value] (on or before `before`)."""
    best = None
    for day, v in points:
        if before is None or date.fromisoformat(day) <= before:
            best = (day, v)
    return best


def _sum_days(points: list, start: date, end: date) -> float:
    return sum(v or 0 for day, v in points if start <= date.fromisoformat(day) <= end)


def _month(d: str) -> str:
    return (d or "")[:7]


def _game(c, ctx) -> dict:
    t = today()
    keys = ["game.games", "game.games.play", "game.games.scan", "game.games.fleet", "game.players",
            "game.unlocks", "game.crashes"]
    plat_keys = [r[0] for r in c.execute("SELECT DISTINCT key FROM metrics WHERE key LIKE 'game.platform.%'")]
    s = series(c, keys + plat_keys, 4000)
    last7, prev7 = (t - timedelta(days=6), t), (t - timedelta(days=13), t - timedelta(days=7))
    out = {
        "daily": {k: [p for p in s[k] if date.fromisoformat(p[0]) >= t - timedelta(days=89)] for k in keys},
        "games_7d": _sum_days(s["game.games"], *last7),
        "games_prev_7d": _sum_days(s["game.games"], *prev7),
        "players_7d_avg": round(_sum_days(s["game.players"], *last7) / 7, 1),
        "games_total": sum(v or 0 for _, v in s["game.games"]),
        "unlocks_30d": _sum_days(s["game.unlocks"], t - timedelta(days=29), t),
        "crashes_30d": _sum_days(s["game.crashes"], t - timedelta(days=29), t),
        "platforms_30d": {k.split(".")[-1]: _sum_days(s[k], t - timedelta(days=29), t) for k in plat_keys},
        "modes_30d": {m: _sum_days(s[f"game.games.{m}"], t - timedelta(days=29), t) for m in ("play", "scan", "fleet")},
    }
    # live from this server: open rooms, open translation comments, Uprising bug reports
    try:
        from .relay import rooms
        out["rooms_now"] = {"rooms": len(rooms), "players": sum(r.player_count() for r in rooms.values())}
    except Exception:  # noqa: BLE001
        out["rooms_now"] = None
    from .main import DB_PATH
    if os.path.exists(DB_PATH):
        src = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        try:
            tables = {r[0] for r in src.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
            if "comments" in tables:
                out["comments_open"] = dict(src.execute(
                    "SELECT lang, COUNT(*) FROM comments WHERE status = 'open' GROUP BY lang ORDER BY 2 DESC").fetchall())
            if "uprising_bugs" in tables:
                out["uprising_bugs"] = dict(src.execute(
                    "SELECT status, COUNT(*) FROM uprising_bugs GROUP BY status ORDER BY 2 DESC").fetchall())
        finally:
            src.close()
    # Steam, per app: the newest numbers
    names = kv_get(c, "steam_names", {}) or {}
    apps = []
    for app in [x for x in setting(c, "Steam app ids").replace(",", " ").split() if x]:
        ks = [f"steam.{app}.{k}" for k in ("reviews", "positive", "players", "followers")]
        ss = series(c, ks, 60)
        row = {"app": app, "name": names.get(app, f"App {app}")}
        for k in ks:
            last = _latest(ss[k])
            row[k.split(".")[-1]] = last[1] if last else None
        apps.append(row)
    out["steam"] = apps
    return out


def _audience(c) -> list[dict]:
    t = today()
    s = series(c, [k for k, _, _ in AUDIENCE], 400)
    out = []
    for key, label, how in AUDIENCE:
        pts = s[key]
        last = _latest(pts)
        w = _latest(pts, t - timedelta(days=7))
        m = _latest(pts, t - timedelta(days=28))
        out.append({"key": key, "label": label, "how": how, "value": last[1] if last else None,
                    "day": last[0] if last else None,
                    "change_7d": (last[1] - w[1]) if last and w else None,
                    "change_28d": (last[1] - m[1]) if last and m else None,
                    "series": [p for p in pts if date.fromisoformat(p[0]) >= t - timedelta(days=180)]})
    return out


def _bgg(c) -> list[dict]:
    """Every game in Settings > BGG ids: the newest numbers, and how owned / wishing moved in 28 days."""
    t = today()
    names = kv_get(c, "bgg_names", {}) or {}
    out = []
    for gid in [x for x in setting(c, "BGG ids").replace(",", " ").split() if x]:
        stats = ("owned", "wishing", "usersrated", "average")
        s = series(c, [f"bgg.{gid}.{k}" for k in stats], 400)
        row = {"id": gid, "name": names.get(gid, f"BGG {gid}")}
        for k in stats:
            last = _latest(s[f"bgg.{gid}.{k}"])
            row[k] = last[1] if last else None
            if k in ("owned", "wishing"):
                before = _latest(s[f"bgg.{gid}.{k}"], t - timedelta(days=28))
                row[k + "_28d"] = last[1] - before[1] if last and before else None
        row["series"] = s[f"bgg.{gid}.owned"][-180:]
        out.append(row)
    return out


def _outreach(ctx, lists) -> dict:
    t = today()
    contacts = derived_rows(ctx, "Contacts")
    log = derived_rows(ctx, "Outreach Log")
    stages = Counter(r.get("Stage") or "No stage" for r in contacts)
    due = [r for r in contacts if r.get("Follow-up due") == "Due" and r.get("Stage") not in CLOSED_STAGES]
    waiting = [r for r in contacts if _d(r.get("Last reply")) and (not _d(r.get("Last contact"))
                                                                  or _d(r.get("Last reply")) > _d(r.get("Last contact")))]
    pick = lambda rows: [{k: r.get(k) for k in ("_id", "ID", "Name", "Company / channel", "Stage", "Next follow-up",
                                                  "Owner", "Platform", "Priority")} for r in rows]
    return {
        "stages": [[s, stages.get(s, 0)] for s in lists.get("Stages", [])] + [[k, v] for k, v in stages.items()
                                                                             if k not in lists.get("Stages", [])],
        "contacts": len(contacts),
        "followups_due": pick(sorted(due, key=lambda r: r.get("Next follow-up") or ""))[:12],
        "followups_due_count": len(due),
        "replies_waiting": pick(waiting)[:12],
        "replies_waiting_count": len(waiting),
        "drafts_to_review": sum(1 for r in contacts if r.get("Draft status") == "Review"),
        "copies_sent": sum(int(_f(r.get("Copies")) or 1) for r in log if r.get("Kind") == "Copy sent"),
        "content_published": sum(1 for r in log if r.get("Kind") == "Content published"),
        "views": sum(_f(r.get("Views")) for r in log),
        "cost": sum(_f(r.get("Cost EUR")) for r in log),
        "recent": [{k: r.get(k) for k in ("Date", "Contact", "Kind", "Summary")}
                   for r in sorted(log, key=lambda r: r.get("Date") or "", reverse=True)[:8]],
    }


def _marketing(ctx, lists) -> dict:
    t = today()
    ads = [r for r in derived_rows(ctx, "Ads") if (_d(r.get("Date")) or date.min) >= t - timedelta(days=29)]
    by = defaultdict(lambda: defaultdict(float))
    for r in ads:
        ch = r.get("Channel") or "Other"
        for k in ("Spend EUR", "Impressions", "Clicks", "Signups", "Followers", "Revenue EUR"):
            by[ch][k] += _f(r.get(k))
    channels = []
    for ch in [*lists.get("AdChannels", []), *[k for k in by if k not in lists.get("AdChannels", [])]]:
        if ch in by:
            v = by[ch]
            channels.append({"channel": ch, **v,
                             "per_signup": v["Spend EUR"] / v["Signups"] if v["Signups"] else None,
                             "per_follower": v["Spend EUR"] / v["Followers"] if v["Followers"] else None})
    content = derived_rows(ctx, "Content")
    mentions = derived_rows(ctx, "Mentions")
    comps = derived_rows(ctx, "Comps")
    return {
        "ads": channels,
        "ads_total": {k: sum(c[k] for c in channels) for k in ("Spend EUR", "Clicks", "Signups", "Followers", "Revenue EUR")},
        "content_status": [[s, sum(1 for r in content if r.get("Status") == s)] for s in lists.get("ContentStatus", [])],
        "content_next": [{k: r.get(k) for k in ("_id", "Date", "Platform", "Format", "Topic", "Status", "Owner")}
                         for r in sorted((r for r in content if (_d(r.get("Date")) or date.max) >= t
                                          and r.get("Status") != "Posted"), key=lambda r: r.get("Date") or "")][:8],
        "mentions_recent": [{k: r.get(k) for k in ("_id", "Date", "Source", "Author", "Rating", "Title", "Flag", "URL")}
                            for r in sorted(mentions, key=lambda r: r.get("Date") or "", reverse=True)[:10]],
        "mentions_unhandled": sum(1 for r in mentions if r.get("Flag") and not r.get("Handled")),
        "comps": {"count": len(comps), "avg_funded": (sum(_f(r.get("Funded EUR")) for r in comps) / len(comps)) if comps else None,
                  "avg_backers": (sum(_f(r.get("Backers")) for r in comps) / len(comps)) if comps else None},
    }


def _events(ctx) -> dict:
    t = today()
    conv = derived_rows(ctx, "Conventions")
    rows = [{k: r.get(k) for k in ("_id", "Name", "City", "Country", "Start", "End", "Booth deadline", "Status",
                                    "Total cost EUR", "Leads", "Sales EUR", "Cost per lead EUR")} for r in conv]
    rows.sort(key=lambda r: r.get("Start") or "9999")
    return {"upcoming": [r for r in rows if (_d(r.get("End") or r.get("Start")) or date.max) >= t],
            "past": [r for r in rows if (_d(r.get("End") or r.get("Start")) or date.max) < t][::-1][:10],
            "deadlines": [r for r in rows if (d := _d(r.get("Booth deadline"))) and t <= d <= t + timedelta(days=30)]}


def _sales(ctx, lists) -> dict:
    t = today()
    sales = derived_rows(ctx, "Sales")
    by_channel, by_channel_90, by_month, by_product, names = Counter(), Counter(), Counter(), Counter(), {}
    for r in sales:
        net, d = _f(r.get("Net EUR")), _d(r.get("Date"))
        ch = r.get("Channel") or "Other"
        by_channel[ch] += net
        if d and d >= t - timedelta(days=89):
            by_channel_90[ch] += net
        if d:
            by_month[d.isoformat()[:7]] += net
        sku = r.get("SKU") or "Without SKU"       # store sales (Steam, Play) usually have none
        by_product[sku] += int(_f(r.get("Units")))
        names[sku] = r.get("Product") or (f"{ch} sales" if sku == "Without SKU" else "")
    months, m = [], date(t.year, t.month, 1)
    for _ in range(12):
        months.append(m.isoformat()[:7])
        m = (m - timedelta(days=1)).replace(day=1)
    stock = derived_rows(ctx, "Stock")
    this_month = t.isoformat()[:7]
    return {
        "net_total": sum(by_channel.values()),
        "net_this_month": by_month.get(this_month, 0),
        "by_channel": sorted(([k, v] for k, v in by_channel.items()), key=lambda x: -x[1]),
        "by_channel_90d": sorted(([k, v] for k, v in by_channel_90.items()), key=lambda x: -x[1]),
        "by_month": [[mm, by_month.get(mm, 0)] for mm in reversed(months)],
        "units_by_product": sorted(([k, v, names.get(k, "")] for k, v in by_product.items()), key=lambda x: -x[1])[:12],
        "recent": [{k: r.get(k) for k in ("_id", "Date", "Channel", "Event / customer", "Product", "Units", "Net EUR")}
                   for r in sorted(sales, key=lambda r: r.get("Date") or "", reverse=True)[:8]],
        "stock": [{k: r.get(k) for k in ("_id", "Location", "SKU", "Product", "On hand", "Reserved", "Available",
                                          "Reorder at", "Status", "Updated")} for r in stock],
        "stock_low": sum(1 for r in stock if r.get("Status") == "Low"),
    }


def _money(ctx) -> dict:
    t = today()
    money = derived_rows(ctx, "Money")
    balances = sorted((r for r in money if r.get("Kind") == "Cash balance" and r.get("Date")), key=lambda r: r["Date"])
    cash = _f(balances[-1].get("Amount EUR")) if balances else None
    open_ = [r for r in money if r.get("Kind") in ("Payment", "Income") and not r.get("Done")]
    due = lambda kind, days: sum(_f(r.get("Amount EUR")) for r in open_ if r.get("Kind") == kind
                                 and (d := _d(r.get("Date"))) and d <= t + timedelta(days=days))
    payments_90, income_90 = due("Payment", 90), due("Income", 90)
    overdue = sum(_f(r.get("Amount EUR")) for r in open_ if r.get("Kind") == "Payment"
                  and (d := _d(r.get("Date"))) and d < t)
    fixed = _f(setting(ctx.c, "Monthly fixed costs EUR")) or None
    runway = (cash - payments_90 + income_90) / fixed if cash is not None and fixed else None
    # paid per month and category, last 6 months
    months, m = [], date(t.year, t.month, 1)
    for _ in range(6):
        months.append(m.isoformat()[:7])
        m = (m - timedelta(days=1)).replace(day=1)
    months.reverse()
    paid, cats = defaultdict(Counter), Counter()
    for r in money:
        if r.get("Kind") == "Payment" and r.get("Done") and _month(r.get("Date")) in months:
            cat = r.get("Category") or "Other"
            paid[_month(r["Date"])][cat] += _f(r.get("Amount EUR"))
            cats[cat] += _f(r.get("Amount EUR"))
    income = Counter()
    for r in money:
        if r.get("Kind") == "Income" and r.get("Done") and _month(r.get("Date")) in months:
            income[_month(r["Date"])] += _f(r.get("Amount EUR"))
    return {
        "cash": cash, "cash_date": balances[-1]["Date"] if balances else None,
        "payments_90d": payments_90, "income_90d": income_90, "overdue": overdue,
        "fixed": fixed, "runway": runway,
        "months": months,
        "paid_by_month": [[mm, dict(paid[mm])] for mm in months],
        "income_by_month": [[mm, income.get(mm, 0)] for mm in months],
        "categories": [k for k, _ in cats.most_common()],
        "upcoming": [{k: r.get(k) for k in ("_id", "Date", "Kind", "Description", "Category", "Amount EUR")}
                     for r in sorted(open_, key=lambda r: r.get("Date") or "9999")[:10]],
    }


def _production(ctx) -> dict:
    ms = derived_rows(ctx, "Production")
    tasks = derived_rows(ctx, "Checklist")
    pick_m = lambda r: {k: r.get(k) for k in ("_id", "Project", "SKU", "Milestone", "Planned", "Actual", "Owner", "State")}
    pick_t = lambda r: {k: r.get(k) for k in ("_id", "Project", "Area", "Task", "Owner", "Due", "State")}
    projects = defaultdict(Counter)
    for r in tasks:
        projects[r.get("Project") or "-"]["done" if r.get("Done") else "open"] += 1
    return {
        "milestones": [[s, sum(1 for r in ms if r.get("State") == s)] for s in ("Late", "Due soon", "Planned", "No date", "Done")],
        "next_milestones": [pick_m(r) for r in sorted((r for r in ms if r.get("State") in ("Late", "Due soon", "Planned")),
                                                      key=lambda r: r.get("Planned") or "")][:10],
        "tasks": [[s, sum(1 for r in tasks if r.get("State") == s)] for s in ("Overdue", "This week", "Open", "Done")],
        "tasks_due": [pick_t(r) for r in sorted((r for r in tasks if r.get("State") in ("Overdue", "This week")),
                                                key=lambda r: r.get("Due") or "")][:12],
        "projects": [[p, v["open"], v["done"]] for p, v in sorted(projects.items())],
    }


def _playtests(ctx) -> dict:
    rows = derived_rows(ctx, "Playtests")
    sessions = defaultdict(list)
    for r in rows:
        sessions[r.get("Session") or r.get("Date") or "?"].append(r)
    fac = defaultdict(lambda: {"plays": 0, "wins": 0, "score": 0.0})
    for r in rows:
        f = r.get("Faction / strategy")
        if f:
            fac[f]["plays"] += 1
            fac[f]["wins"] += 1 if r.get("Won") else 0
            fac[f]["score"] += _f(r.get("Score"))
    funs = [_f(r.get("Fun")) for r in rows if r.get("Fun") not in (None, "")]
    minutes = [_f(s[0].get("Minutes")) for s in sessions.values() if s[0].get("Minutes") not in (None, "")]
    return {
        "sessions": len(sessions), "seats": len(rows),
        "avg_fun": sum(funs) / len(funs) if funs else None,
        "avg_minutes": sum(minutes) / len(minutes) if minutes else None,
        "would_buy": [[k, sum(1 for r in rows if r.get("Would buy") == k)] for k in ("Yes", "Maybe", "No")],
        "factions": sorted(([k, v["plays"], v["wins"] / v["plays"], v["score"] / v["plays"]] for k, v in fac.items()),
                           key=lambda x: -x[1])[:14],
    }


def _community(ctx) -> dict:
    leads = derived_rows(ctx, "Leads")
    support = derived_rows(ctx, "Support")
    return {
        "leads_by_status": Counter(r.get("Status") or "-" for r in leads).most_common(),
        "leads_by_source": Counter(r.get("Source") or "-" for r in leads).most_common(8),
        "support_by_status": Counter(r.get("Status") or "New" for r in support).most_common(),
        "support_open": [{k: r.get(k) for k in ("_id", "ID", "Received", "Kind", "Name", "Game", "Status", "Owner")}
                         for r in support if (r.get("Status") or "New") in OPEN_SUPPORT][:12],
    }


def build() -> dict:
    with hdb() as c:
        ctx = Context(c)
        lists = kv_get(c, "lists", {}) or {}
        game = _game(c, ctx)
        audience = _audience(c)
        out = {
            "today": today().isoformat(),
            "game": game, "audience": audience, "bgg": _bgg(c),
            "outreach": _outreach(ctx, lists), "marketing": _marketing(ctx, lists), "events": _events(ctx),
            "sales": _sales(ctx, lists), "money": _money(ctx), "production": _production(ctx),
            "playtests": _playtests(ctx), "community": _community(ctx),
        }
    from .hub_collect import status
    out["collect"] = status()["collectors"]
    aud = {a["key"]: a for a in audience}
    p, m, o = out["production"], out["money"], out["outreach"]
    count = lambda pairs, k: dict(pairs).get(k, 0)
    out["overview"] = {
        "tiles": {
            "games_7d": game["games_7d"], "games_prev_7d": game["games_prev_7d"], "players_7d_avg": game["players_7d_avg"],
            "gamefound": aud["gamefound.followers"]["value"], "gamefound_7d": aud["gamefound.followers"]["change_7d"],
            "newsletter": aud["newsletter.subscribers"]["value"],
            "cash": m["cash"], "runway": m["runway"],
            "sales_month": out["sales"]["net_this_month"],
            "followups_due": o["followups_due_count"], "replies_waiting": o["replies_waiting_count"],
            "overdue_tasks": count(p["tasks"], "Overdue"), "late_milestones": count(p["milestones"], "Late"),
            "support_open": sum(n for s, n in out["community"]["support_by_status"] if s in OPEN_SUPPORT),
            "bugs_new": (game.get("uprising_bugs") or {}).get("new", 0),
            "comments_open": sum((game.get("comments_open") or {}).values()),
            "stock_low": out["sales"]["stock_low"],
        },
        "attention": _attention(out),
    }
    return out


def _attention(out: dict) -> list[dict]:
    """What someone should look at today, most urgent first."""
    a = []
    for r in out["production"]["tasks_due"]:
        if r["State"] == "Overdue":
            a.append({"area": "production", "kind": "Overdue task", "text": r["Task"], "detail": f"due {r['Due']}", "who": r.get("Owner")})
    for r in out["production"]["next_milestones"]:
        if r["State"] == "Late":
            a.append({"area": "production", "kind": "Late milestone", "text": f"{r['Milestone']} ({r.get('SKU') or r.get('Project') or ''})",
                      "detail": f"planned {r['Planned']}", "who": r.get("Owner")})
    if out["money"]["overdue"]:
        a.append({"area": "money", "kind": "Overdue payments", "text": f"{out['money']['overdue']:,.0f} EUR", "detail": "not marked done"})
    for r in out["outreach"]["replies_waiting"][:5]:
        a.append({"area": "outreach", "kind": "Reply waiting", "text": r["Name"], "detail": r.get("Company / channel") or "", "who": r.get("Owner")})
    for r in out["outreach"]["followups_due"][:5]:
        a.append({"area": "outreach", "kind": "Follow-up due", "text": r["Name"], "detail": f"since {r['Next follow-up']}", "who": r.get("Owner")})
    for r in out["community"]["support_open"][:5]:
        a.append({"area": "community", "kind": "Support", "text": f"{r.get('Kind') or 'Request'} from {r.get('Name') or '?'}",
                  "detail": r.get("Status") or "New", "who": r.get("Owner")})
    for r in out["sales"]["stock"]:
        if r.get("Status") == "Low":
            a.append({"area": "sales", "kind": "Low stock", "text": r.get("Product") or r.get("SKU"), "detail": f"{r.get('Available'):.0f} left at {r.get('Location')}"})
    for r in out["events"]["deadlines"]:
        a.append({"area": "events", "kind": "Booth deadline", "text": r["Name"], "detail": r["Booth deadline"]})
    for r in out["collect"]:
        if r.get("ok") is False:
            a.append({"area": "settings", "kind": "Collector failed", "text": r["collector"], "detail": r.get("message", "")[:120]})
    return a[:20]
