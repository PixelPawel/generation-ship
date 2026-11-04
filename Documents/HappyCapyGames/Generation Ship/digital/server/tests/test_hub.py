"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile
import time
from datetime import date, timedelta

_tmp = tempfile.mkdtemp()
os.environ.setdefault("DB_PATH", os.path.join(_tmp, "votes.db"))
os.environ["HUB_DB_PATH"] = os.path.join(_tmp, "hub.db")
os.environ["HUB_TOKEN"] = "test-hub-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app, db  # noqa: E402
from app import hub  # noqa: E402

client = TestClient(app)
H = {"X-Hub-Token": "test-hub-token", "X-Hub-User": "Pawel"}
TODAY = hub.today()


def add(tab, **data):
    r = client.post(f"/v1/hub/rows/{tab}", json={"data": data}, headers=H)
    assert r.status_code == 200, r.text
    return r.json()["row"]


def setup_function():
    with hub.hdb() as c:
        c.execute("DELETE FROM rows")
        c.execute("DELETE FROM metrics")
        c.execute("DELETE FROM collect_log")


def test_needs_the_token():
    assert client.get("/v1/hub/schema").status_code == 403
    assert client.get("/v1/hub/schema", headers={"X-Hub-Token": "nope"}).status_code == 403
    r = client.get("/v1/hub/schema", headers=H)
    assert r.status_code == 200
    assert {t["slug"] for t in r.json()["tabs"]} >= {"sales", "money", "contacts", "checklist", "products"}


def test_rows_values_and_calculated_columns():
    add("products", SKU="GS-EN", Product="Generation Ship (EN)")
    row = add("sales", Date="02.11.2026", Channel="Convention", SKU="GS-EN", Units="3", **{"Gross EUR": "135,00", "Fees EUR": 5})
    assert row["Date"] == "2026-11-02"
    assert row["Units"] == 3 and row["Gross EUR"] == 135.0
    assert row["Product"] == "Generation Ship (EN)" and row["Net EUR"] == 130.0
    assert row["_by"] == "Pawel"
    # calculated columns can't be written
    r = client.put(f"/v1/hub/rows/sales/{row['_id']}", json={"data": {"Net EUR": 1, "Units": 4}}, headers=H)
    assert r.json()["row"]["Net EUR"] == 130.0 and r.json()["row"]["Units"] == 4


def test_change_conflict_and_delete():
    row = add("checklist", Task="Book the booth", Due=(TODAY - timedelta(days=1)).isoformat())
    assert row["State"] == "Overdue"
    r = client.put(f"/v1/hub/rows/checklist/{row['_id']}", json={"data": {"Done": True}, "base": row["_updated"]}, headers=H)
    assert r.json()["row"]["State"] == "Done"
    stale = client.put(f"/v1/hub/rows/checklist/{row['_id']}", json={"data": {"Done": False}, "base": row["_updated"]}, headers=H)
    assert stale.status_code == 409
    assert client.delete(f"/v1/hub/rows/checklist/{row['_id']}", headers=H).status_code == 200
    assert client.delete(f"/v1/hub/rows/checklist/{row['_id']}", headers=H).status_code == 404


def test_auto_ids_and_lookups():
    a = add("contacts", Name="Board Game Bob", Stage="Contacted", **{"Next follow-up": TODAY.isoformat()})
    b = add("contacts", Name="Meeple Mia")
    assert a["ID"] == "C0001" and b["ID"] == "C0002"
    assert a["Follow-up due"] == "Due"
    log = add("outreach-log", Date=TODAY.isoformat(), **{"Contact ID": "C0002", "Kind": "Email"})
    assert log["Contact"] == "Meeple Mia"
    s = add("support", Name="Kim", Kind="Missing part")
    assert s["ID"] == "S0001" and s["Updated"]


def test_stock_and_convention_formulas():
    add("products", SKU="GS-DE", Product="Generation Ship (DE)")
    low = add("stock", Location="Office", SKU="GS-DE", **{"On hand": 25, "Reserved": 10})   # default low = 20
    assert low["Available"] == 15 and low["Status"] == "Low" and low["Product"] == "Generation Ship (DE)"
    add("conventions", Name="SPIEL 26", **{"Booth cost EUR": 800, "Travel EUR": 200})
    add("sales", Date=TODAY.isoformat(), **{"Event / customer": "SPIEL 26", "Gross EUR": 90, "Fees EUR": 0})
    conv = client.get("/v1/hub/rows/conventions", headers=H).json()["rows"][0]
    assert conv["Total cost EUR"] == 1000 and conv["Sales EUR"] == 90 and "Leads" not in conv


def test_import_keeps_script_columns():
    r = client.post("/v1/hub/import", json={"tab": "contacts", "rows": [{"ID": "C0042", "Name": "Old"}, {}]}, headers=H)
    assert r.json()["imported"] == 1
    assert client.get("/v1/hub/rows/contacts", headers=H).json()["rows"][0]["ID"] == "C0042"
    assert add("contacts", Name="New")["ID"] == "C0043"


def test_manual_metrics_only_for_typed_numbers():
    r = client.post("/v1/hub/metrics", json={"values": {"instagram.followers": "1.234"}}, headers=H)
    assert r.status_code == 200
    assert r.json()["series"]["instagram.followers"][-1][1] == 1234
    assert client.post("/v1/hub/metrics", json={"values": {"discord.members": 5}}, headers=H).status_code == 400


def test_game_collector_counts_finished_games():
    now = int(time.time())
    with db() as c:
        c.execute("DELETE FROM scores")
        for player, source, platform, ago in (("dev:a", "play", "android", 0), ("dev:a", "play", "android", 0),
                                              ("steam:1", "fleet", "steam", 0), ("steam:1", "play", "steam", 2 * 86400)):
            c.execute("INSERT INTO scores (player, source, name, score, details, platform, updated_at) "
                      "VALUES (?, ?, 'x', 10, '', ?, ?)", (player, source, platform, now - ago))
    res = client.post("/v1/hub/collect?only=game", headers=H).json()["results"]
    assert res[0]["ok"], res
    s = client.get("/v1/hub/metrics?keys=game.games,game.games.play,game.players,game.platform.android&days=10", headers=H).json()["series"]
    day = dict(s["game.games"])
    assert day[TODAY.isoformat()] == 3
    assert dict(s["game.players"])[TODAY.isoformat()] == 2
    assert dict(s["game.platform.android"])[TODAY.isoformat()] == 2
    assert sum(v for _, v in s["game.games"]) == 4
    with db() as c:   # the leaderboard tests share this database and expect real score details
        c.execute("DELETE FROM scores")


def test_collectors_without_settings_say_what_is_missing():
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["Steam app ids"] = ""
        hub.kv_put(c, "settings", s)
    res = {r["collector"]: r for r in client.post("/v1/hub/collect?only=steam,discord,youtube,bgg", headers=H).json()["results"]}
    assert all(r["ok"] for r in res.values())
    assert res["discord"]["message"].startswith("skipped")
    assert "YOUTUBE_API_KEY" in res["youtube"]["message"]
    status = client.get("/v1/hub/collect", headers=H).json()["collectors"]
    assert {r["collector"] for r in status} >= {"game", "steam", "backup"}


def test_backup_writes_a_copy():
    res = client.post("/v1/hub/collect?only=backup", headers=H).json()["results"][0]
    assert res["ok"], res
    assert os.path.exists(os.path.join(os.path.dirname(hub.HUB_DB_PATH), "hub-backups", f"hub-{TODAY.isoformat()}.db"))


def test_dashboard_money_and_attention():
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["Monthly fixed costs EUR"] = "2000"
        hub.kv_put(c, "settings", s)
    add("money", Date=(TODAY - timedelta(days=3)).isoformat(), Kind="Cash balance", **{"Amount EUR": 10000})
    add("money", Date=(TODAY + timedelta(days=20)).isoformat(), Kind="Payment", Category="Manufacturing", **{"Amount EUR": 4000})
    add("money", Date=(TODAY - timedelta(days=1)).isoformat(), Kind="Payment", Category="Art", **{"Amount EUR": 500})
    add("money", Date=(TODAY + timedelta(days=40)).isoformat(), Kind="Income", **{"Amount EUR": 1000})
    add("checklist", Task="File the taxes", Due=(TODAY - timedelta(days=2)).isoformat(), Owner="Pawel")
    add("production", Milestone="Files to printer", Planned=(TODAY - timedelta(days=5)).isoformat())
    d = client.get("/v1/hub/dash", headers=H).json()
    m = d["money"]
    assert m["cash"] == 10000 and m["payments_90d"] == 4500 and m["income_90d"] == 1000 and m["overdue"] == 500
    assert m["runway"] == (10000 - 4500 + 1000) / 2000
    kinds = [x["kind"] for x in d["overview"]["attention"]]
    assert "Overdue task" in kinds and "Late milestone" in kinds and "Overdue payments" in kinds
    assert d["overview"]["tiles"]["overdue_tasks"] == 1
    assert {a["key"] for a in d["audience"]} >= {"gamefound.followers", "steam.followers"}


def test_steam_store_page_reviews():
    from app.hub_collect import store_reviews
    assert store_reviews('<span data-tooltip-html="No user reviews">No user reviews</span>') == (0, 0)
    page = ('data-tooltip-html="66% of the 5,600 user reviews in the last 30 days are positive." '
            'data-tooltip-html="76% of the 453,261 user reviews in your language are positive"')
    assert store_reviews(page) == (453261, round(453261 * 0.76))
    assert store_reviews("<html>nothing</html>") is None


def test_bgg_collector_and_dashboard(monkeypatch):
    from app import hub_collect
    xml = b"""<items><item type="boardgame" id="451162"><name type="primary" value="Generation Ship"/>
      <statistics><ratings><usersrated value="12"/><average value="7.4"/><owned value="80"/><wishing value="25"/></ratings></statistics>
    </item></items>"""
    seen = {}
    monkeypatch.setattr(hub_collect, "_get", lambda url, headers=None, timeout=20: seen.update(url=url, headers=headers) or xml)
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["BGG ids"] = "451162"
        hub.kv_put(c, "settings", s)
    monkeypatch.delenv("BGG_TOKEN", raising=False)
    assert "BGG_TOKEN" in client.post("/v1/hub/collect?only=bgg", headers=H).json()["results"][0]["message"]
    monkeypatch.setenv("BGG_TOKEN", "t0k")
    res = client.post("/v1/hub/collect?only=bgg", headers=H).json()["results"][0]
    assert res["ok"] and "Generation Ship: 80 owned, 25 wishing" in res["message"]
    assert seen["headers"] == {"Authorization": "Bearer t0k"} and "boardgamegeek.com/xmlapi2" in seen["url"]
    row = client.get("/v1/hub/dash", headers=H).json()["bgg"][0]
    assert row["name"] == "Generation Ship" and row["owned"] == 80 and row["average"] == 7.4 and row["usersrated"] == 12


def test_gamefound_campaigns_one_row_each():
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["Gamefound campaigns"] = ("Generation Ship | https://gamefound.com/en/projects/happy-capy-games/generation-ship#/section/x\n"
                                    "https://gamefound.com/en/projects/happy-capy-games/rink-rumble\n\nSuccession")
        hub.kv_put(c, "settings", s)
    keys = [a["key"] for a in client.get("/v1/hub/schema", headers=H).json()["audience"]]
    assert keys[:3] == ["gamefound.generation-ship.followers", "gamefound.rink-rumble.followers", "gamefound.succession.followers"]
    assert "gamefound.followers" not in keys
    r = client.post("/v1/hub/metrics", json={"values": {"gamefound.generation-ship.followers": 1200, "gamefound.rink-rumble.followers": 300}}, headers=H)
    assert r.status_code == 200, r.text
    assert client.post("/v1/hub/metrics", json={"values": {"gamefound.x.y": 1}}, headers=H).status_code == 400
    d = client.get("/v1/hub/dash", headers=H).json()
    rows = {a["key"]: a for a in d["audience"]}
    assert rows["gamefound.generation-ship.followers"]["label"] == "Gamefound: Generation Ship"
    assert rows["gamefound.rink-rumble.followers"]["label"] == "Gamefound: Rink Rumble"
    assert d["overview"]["tiles"]["gamefound"] == 1500 and d["overview"]["tiles"]["gamefound_campaigns"] == 3


def test_calendar_entries_and_ics_feed():
    d = lambda n: (TODAY + timedelta(days=n)).isoformat()
    add("calendar", Date=d(3), Time="14:00-15:30", Title="Team meeting, monthly", Kind="Meeting")
    essen = add("conventions", Name="Essen", City="Essen", Start=d(10), End=d(13), **{"Booth deadline": d(2)})
    client.post("/v1/hub/calendar/show", json={"key": f"conv-{essen['_id']}", "show": True}, headers=H)
    add("production", Milestone="Files to printer", SKU="GS-PL", Planned=d(5))
    add("production", Milestone="Art final", Planned=d(-9), Actual=d(-9))          # done: no entry
    add("checklist", Task="Book the hotel", Due=d(1), Owner="Pawel")
    add("money", Date=d(20), Kind="Payment", Description="Print deposit", **{"Amount EUR": 9600})
    add("content", Date=d(4), Platform="Instagram", Topic="Unboxing", Status="Drafted")
    ev = client.get("/v1/hub/events", headers=H).json()["events"]
    cats = {e["cat"] for e in ev}
    assert {"team", "conventions", "milestones", "tasks", "money", "content"} <= cats
    assert not any("Art final" in e["title"] for e in ev)
    conv = next(e for e in ev if e["title"].startswith("Essen"))
    assert conv["start"] == d(10) and conv["end"] == d(13)
    assert any(e["title"] == "To pay: Print deposit (9.600,00 €)" for e in ev)

    feeds = {f["feed"]: f["url"] for f in client.get("/v1/hub/calendar", headers=H).json()["feeds"]}
    path = feeds["all"].replace("https://api.happycapygames.com", "")
    r = client.get(path)   # no hub token: the secret in the link is enough
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/calendar")
    body = r.text
    assert body.startswith("BEGIN:VCALENDAR\r\n") and body.rstrip().endswith("END:VCALENDAR")
    assert "SUMMARY:Team meeting\, monthly" in body
    assert "DTSTART;VALUE=DATE:" + d(10).replace("-", "") in body
    assert "DTEND;VALUE=DATE:" + (TODAY + timedelta(days=14)).strftime("%Y%m%d") in body   # the day after the last
    assert all(len(line.encode()) <= 75 for line in body.split("\r\n"))
    only_money = client.get(feeds["money"].replace("https://api.happycapygames.com", "")).text
    assert "Print deposit" in only_money and "Team meeting" not in only_money
    assert client.get(path.replace("/all.ics", "/nope.ics")).status_code == 404
    assert client.get(path.replace(path.split("/")[-2], "wrong-secret")).status_code == 404
    new = {f["feed"]: f["url"] for f in client.post("/v1/hub/calendar/rotate", headers=H).json()["feeds"]}
    assert new["all"] != feeds["all"] and client.get(path).status_code == 404


def test_google_calendar_sync(monkeypatch, tmp_path):
    from app import hub_gcal
    key = tmp_path / "key.json"
    key.write_text("{}")
    monkeypatch.setenv("GOOGLE_CALENDAR_KEY", str(key))
    monkeypatch.setenv("HUB_GCAL_OFF", "1")          # no background sync during the test
    calls, n = [], [0]

    def fake_call(method, url, token, body=None):
        calls.append((method, url, body))
        if method == "POST":
            n[0] += 1
            return {"id": f"ev{n[0]}"}
        return {}
    monkeypatch.setattr(hub_gcal, "_token", lambda: "tok")
    monkeypatch.setattr(hub_gcal, "_call", fake_call)
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["Google calendar id"] = "kate@happycapygames.com"
        hub.kv_put(c, "settings", s)
    d = lambda k: (TODAY + timedelta(days=k)).isoformat()
    meet = add("calendar", Date=d(2), Time="14:00-15:30", Title="Team call")
    pay = add("money", Date=d(9), Kind="Payment", Description="Deposit", **{"Amount EUR": 100})
    add("contacts", Name="Bob", **{"Next follow-up": d(1)})     # follow-ups stay out unless Settings asks for them
    sync = lambda: client.post("/v1/hub/collect?only=calendar", headers=H).json()["results"][0]
    r = sync()
    assert r["ok"] and "2 added, 0 changed, 0 removed" in r["message"], r
    posted = [b for m, u, b in calls if m == "POST"]
    assert all("kate%40happycapygames.com" in u for m, u, b in calls)
    timed = next(b for b in posted if b["summary"] == "Team call")
    assert timed["start"] == {"dateTime": d(2) + "T14:00:00", "timeZone": "Europe/Berlin"} and timed["end"]["dateTime"].endswith("T15:30:00")
    allday = next(b for b in posted if b["summary"].startswith("To pay: Deposit"))
    assert allday["start"] == {"date": d(9)} and allday["end"] == {"date": d(10)}
    assert allday["extendedProperties"]["private"]["hcg_uid"] == f"money-{pay['_id']}"
    calls.clear()
    assert "0 added, 0 changed, 0 removed" in sync()["message"] and not calls
    client.put(f"/v1/hub/rows/calendar/{meet['_id']}", json={"data": {"Title": "Team call (moved)"}}, headers=H)
    assert "0 added, 1 changed" in sync()["message"]
    assert calls[-1][0] == "PUT" and calls[-1][1].endswith("/ev1") or calls[-1][1].endswith("/ev2")
    client.delete(f"/v1/hub/rows/money/{pay['_id']}", headers=H)
    r = sync()
    assert "1 removed" in r["message"] and calls[-1][0] == "DELETE"


def test_calendar_conventions_only_when_added_tasks_by_themselves():
    d = lambda n: (TODAY + timedelta(days=n)).isoformat()
    conv = add("conventions", Name="Fair", Start=d(30), End=d(32), **{"Booth deadline": d(5)})
    task = add("checklist", Task="Print banner", Due=d(3))
    uids = lambda: {e["uid"] for e in client.get("/v1/hub/events", headers=H).json()["events"]}
    key = f"conv-{conv['_id']}"
    assert not {key, key + "-deadline"} & uids() and f"task-{task['_id']}" in uids()
    show = lambda k, v: client.post("/v1/hub/calendar/show", json={"key": k, "show": v}, headers=H)
    assert show(key, True).json()["choice"][key] is True
    assert {key, key + "-deadline"} <= uids()
    assert client.get("/v1/hub/calendar", headers=H).json()["choice"][key] is True
    show(key, False)
    assert not {key, key + "-deadline"} & uids()
    show(f"task-{task['_id']}", False)                      # automatic ones can be taken out too
    assert f"task-{task['_id']}" not in uids()
    assert show("../etc", True).status_code == 400


def test_calendar_shows_the_google_calendars_own_appointments(monkeypatch, tmp_path):
    from app import hub_gcal
    key = tmp_path / "key.json"
    key.write_text("{}")
    monkeypatch.setenv("GOOGLE_CALENDAR_KEY", str(key))
    monkeypatch.setenv("HUB_GCAL_OFF", "1")
    hub_gcal._read_cache.clear()
    with hub.hdb() as c:
        s = hub.kv_get(c, "settings")
        s["Google calendar id"] = "kate@happycapygames.com"
        hub.kv_put(c, "settings", s)
    d = lambda n: (TODAY + timedelta(days=n)).isoformat()
    items = [
        {"id": "a1", "summary": "Dentist", "start": {"dateTime": d(2) + "T09:00:00+01:00"}, "end": {"dateTime": d(2) + "T10:00:00+01:00"}, "htmlLink": "https://calendar.google.com/x"},
        {"id": "a2", "summary": "Holiday", "start": {"date": d(5)}, "end": {"date": d(8)}},
        {"id": "a3", "summary": "Ours", "start": {"date": d(3)}, "end": {"date": d(4)}, "extendedProperties": {"private": {"hcg_uid": "cal-1"}}},
        {"id": "a4", "summary": "Gone", "status": "cancelled", "start": {"date": d(3)}, "end": {"date": d(4)}},
    ]
    monkeypatch.setattr(hub_gcal, "_token", lambda: "tok")
    monkeypatch.setattr(hub_gcal, "_call", lambda method, url, token, body=None: {"items": items} if method == "GET" else {})
    ev = [e for e in client.get("/v1/hub/events", headers=H).json()["events"] if e["cat"] == "google"]
    assert [e["title"] for e in ev] == ["Dentist", "Holiday"]          # not ours, not cancelled
    dentist, holiday = ev
    assert dentist["time"] == "09:00-10:00" and dentist["url"] == "https://calendar.google.com/x"
    assert holiday["start"] == d(5) and holiday["end"] == d(7)        # Google's end date is the day after
    monkeypatch.setattr(hub_gcal, "_call", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down")))
    hub_gcal._read_cache.clear()
    r = client.get("/v1/hub/events", headers=H).json()
    assert r["google_error"] and not [e for e in r["events"] if e["cat"] == "google"]
