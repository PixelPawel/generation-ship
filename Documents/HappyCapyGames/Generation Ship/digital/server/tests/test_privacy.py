"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile
import time
from collections import deque

os.environ.setdefault("DB_PATH", os.path.join(tempfile.mkdtemp(), "votes.db"))
os.environ["ADMIN_TOKEN"] = "test-admin-token"

from fastapi.testclient import TestClient  # noqa: E402

from app import main, privacy, scores  # noqa: E402
from app.main import app, db  # noqa: E402

client = TestClient(app)
ADMIN = {"X-Admin-Token": "test-admin-token"}
P1 = "steam:76561198000000555"
P2 = "dev:55555555555555555555555555555555"
INSTALL = "inst-0123456789abcdef"


def teardown_module():
    # the test modules share one database: leave nothing behind for the others
    for subject in (P1, P2, INSTALL):
        client.delete(f"/v1/admin/privacy/{subject}", headers=ADMIN)
    with db() as c:
        c.execute("DELETE FROM score_snapshots")
    main._writes.clear()


def score(player, name, value):
    r = client.post("/v1/scores", json={"player": player, "name": name, "score": value, "platform": "test"})
    assert r.status_code == 200, r.text


def test_admin_only():
    assert client.get("/v1/admin/privacy/find", params={"name": "x"}).status_code == 403
    assert client.get(f"/v1/admin/privacy/{P1}").status_code == 403
    assert client.delete(f"/v1/admin/privacy/{P1}").status_code == 403


def test_bad_subject():
    assert client.get("/v1/admin/privacy/not an id", headers=ADMIN).status_code == 400


def test_find_export_and_forget():
    score(P1, "Privacy Pat", 70)
    score(P2, "Someone Else", 60)
    main._writes.clear()
    assert client.post("/v1/votes", json={"key": "tv_DE_core_card_1", "voter": P1, "value": 1}).status_code == 200
    with db() as c:
        c.execute("INSERT INTO comments (key, lang, field, text, voter, version, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                  ("tv_DE_core_card_1", "DE", "name", "typo here", P1, "1.0", int(time.time())))
    scores.take_snapshot("play")

    found = client.get("/v1/admin/privacy/find", params={"name": "privacy pat"}, headers=ADMIN).json()["players"]
    assert [p["player"] for p in found] == [P1]

    data = client.get(f"/v1/admin/privacy/{P1}", headers=ADMIN).json()["data"]
    assert len(data["scores"]) == 1 and data["scores"][0]["name"] == "Privacy Pat"
    assert len(data["votes"]) == 1 and len(data["comments"]) == 1

    r = client.delete(f"/v1/admin/privacy/{P1}", headers=ADMIN).json()["deleted"]
    assert r["scores"] == 1 and r["votes"] == 1 and r["comments"] == 1 and r["standings_names"] >= 1
    data = client.get(f"/v1/admin/privacy/{P1}", headers=ADMIN).json()["data"]
    assert all(rows == [] for rows in data.values())
    names = [e["name"] for e in client.get("/v1/scores/snapshot", params={"source": "play"}).json()["entries"]]
    assert "Privacy Pat" not in names and privacy.REMOVED_NAME in names and "Someone Else" in names


def test_crash_reports_by_install_id():
    with db() as c:
        c.execute("INSERT INTO crashes (signature, summary, install, build, exit_code, phase, safe_mode, os, gpu, log, created_at) "
                  "VALUES ('s', 's', ?, '1', '1', 'start', 0, 'Windows 11', 'GPU', 'log', ?)", (INSTALL, int(time.time())))
    assert len(client.get(f"/v1/admin/privacy/{INSTALL}", headers=ADMIN).json()["data"]["crashes"]) == 1
    assert client.delete(f"/v1/admin/privacy/{INSTALL}", headers=ADMIN).json()["deleted"]["crashes"] == 1


def test_retention_purge():
    now = int(time.time())
    old = now - 800 * privacy.DAY
    with db() as c:
        c.execute("INSERT INTO votes (key, voter, value, updated_at) VALUES ('tv_PL_old_card', ?, 1, ?)", (P2, old))
        c.execute("INSERT INTO votes (key, voter, value, updated_at) VALUES ('tv_PL_new_card', ?, 1, ?)", (P2, now))
        c.execute("INSERT INTO crashes (signature, summary, install, build, exit_code, phase, safe_mode, os, gpu, log, created_at) "
                  "VALUES ('s', 's', ?, '1', '1', 'start', 0, 'w', 'g', 'l', ?)", (INSTALL, now - 400 * privacy.DAY))
        c.execute("INSERT INTO score_snapshots (source, day, taken_at, entries) VALUES ('play', '2020-01-01', ?, '[]')",
                  (now - 400 * privacy.DAY,))
    backup = privacy.DB_PATH + ".bak-test"
    open(backup, "w").close()
    os.utime(backup, (old, old))
    removed = privacy.purge_old(now)
    assert removed["votes"] == 1 and removed["crashes"] == 1 and removed["score_snapshots"] == 1
    assert removed["backups"] == 1 and not os.path.exists(backup)
    with db() as c:
        assert c.execute("SELECT COUNT(*) FROM votes WHERE key = 'tv_PL_new_card'").fetchone()[0] == 1


def test_ip_pruning():
    main._writes.clear()
    main._writes["1.2.3.4"] = deque([100.0])
    main._writes["5.6.7.8"] = deque([5000.0])
    main._writes["9.9.9.9"] = deque()
    assert privacy.prune_ips(now=5000.0 + 10) == 2
    assert list(main._writes) == ["5.6.7.8"]
