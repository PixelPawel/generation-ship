import os
import tempfile

os.environ.setdefault("DB_PATH", os.path.join(tempfile.mkdtemp(), "votes.db"))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)
P1 = "steam:76561198000000011"
P2 = "dev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


def post(player, name, score, details=None, source=None):
    body = {"player": player, "name": name, "score": score, "details": details or [], "platform": "test"}
    if source:
        body["source"] = source
    r = client.post("/v1/scores", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def test_best_score_kept_and_ranked():
    assert post(P1, "Ann", 40, [123, 456])["best"]
    assert post(P2, "Bob", 55)["rank"] == 1
    # lower score: not stored, but the name refreshes
    r = post(P1, "Annie", 30)
    assert not r["best"] and r["score"] == 40 and r["rank"] == 2
    top = client.get("/v1/scores/top", params={"player": P1}).json()
    names = [(e["name"], e["score"], e["me"]) for e in top["entries"] if e["name"] in ("Annie", "Bob")]
    assert names == [("Bob", 55, False), ("Annie", 40, True)]
    assert top["mine"]["score"] == 40
    assert [e["details"] for e in top["entries"] if e["name"] == "Annie"] == [[123, 456]]


def test_full_details_from_the_game():
    # the game sends all 64 breakdown slots, empty ones as 0: kept without the zeros
    details = [1003005, 2017002] + [0] * 62
    assert post("dev:cccccccccccccccccccccccccccccccc", "Cleo", 21, details)["best"]
    top = client.get("/v1/scores/top").json()
    assert [e["details"] for e in top["entries"] if e["name"] == "Cleo"] == [[1003005, 2017002]]


def test_rejects_bad_input():
    assert client.post("/v1/scores", json={"player": "nope", "name": "x", "score": 1}).status_code == 400
    assert client.post("/v1/scores", json={"player": P1, "name": "x", "score": 5000}).status_code == 422


def test_sources_kept_apart_and_filtered():
    P3 = "dev:cccccccccccccccccccccccccccccccc"
    P4 = "dev:dddddddddddddddddddddddddddddddd"
    assert post(P3, "Cara", 60)["best"]                      # no source = a played game
    r = post(P3, "Cara", 120, source="scan")                  # a scan doesn't touch the played best
    assert r["best"] and r["score"] == 120
    assert post(P4, "Dan", 70, source="play")["best"]
    play = client.get("/v1/scores/top", params={"player": P3, "source": "play"}).json()
    names = [(e["name"], e["source"]) for e in play["entries"] if e["name"] in ("Cara", "Dan")]
    assert names == [("Dan", "play"), ("Cara", "play")]
    assert play["mine"]["score"] == 60 and play["mine"]["source"] == "play"
    scan = client.get("/v1/scores/top", params={"player": P3, "source": "scan"}).json()
    assert [(e["name"], e["score"]) for e in scan["entries"]] == [("Cara", 120)]
    assert scan["mine"]["rank"] == 1
    every = client.get("/v1/scores/top", params={"player": P3}).json()
    cara = [(e["score"], e["source"]) for e in every["entries"] if e["name"] == "Cara"]
    assert cara == [(120, "scan"), (60, "play")]
    assert every["mine"]["score"] == 120
    assert client.post("/v1/scores", json={"player": P3, "name": "x", "score": 1, "source": "nope"}).status_code == 400


def test_migrates_old_board():
    from app import main, scores
    with main.db() as c:
        c.execute("DROP TABLE scores")
        c.execute("CREATE TABLE scores (player TEXT PRIMARY KEY, name TEXT NOT NULL, score INTEGER NOT NULL, "
                  "details TEXT NOT NULL, platform TEXT NOT NULL, updated_at INTEGER NOT NULL)")
        c.execute("INSERT INTO scores VALUES ('dev:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'Eve', 77, '[]', 'steam', 1)")
    scores.init_scores()
    top = client.get("/v1/scores/top", params={"source": "play"}).json()
    assert [(e["name"], e["score"], e["source"]) for e in top["entries"]] == [("Eve", 77, "play")]


def test_fleet_board_own_and_out_of_all():
    P5 = "dev:ffffffffffffffffffffffffffffffff"
    r = client.post("/v1/scores", json={"player": P5, "name": "Fay", "score": 44, "platform": "test",
                                        "source": "fleet", "destination": 13})
    assert r.status_code == 200 and r.json()["rank"] == 1
    fleet = client.get("/v1/scores/top", params={"player": P5, "source": "fleet"}).json()
    assert [(e["name"], e["score"], e["destination"]) for e in fleet["entries"]] == [("Fay", 44, 13)]
    assert fleet["mine"]["score"] == 44
    every = client.get("/v1/scores/top", params={"player": P5}).json()
    assert all(e["source"] != "fleet" for e in every["entries"])
    assert every["mine"] is None
    assert client.post("/v1/scores", json={"player": P5, "name": "x", "score": 1, "source": "fleet",
                                           "destination": 500}).status_code == 422


def test_adds_destination_column_to_sourced_board():
    from app import main, scores
    with main.db() as c:
        c.execute("DROP TABLE scores")
        c.execute("CREATE TABLE scores (player TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'play', "
                  "name TEXT NOT NULL, score INTEGER NOT NULL, details TEXT NOT NULL, platform TEXT NOT NULL, "
                  "updated_at INTEGER NOT NULL, PRIMARY KEY (player, source))")
        c.execute("INSERT INTO scores VALUES ('dev:abababababababababababababababab', 'play', 'Gus', 33, '[]', 'steam', 1)")
    scores.init_scores()
    top = client.get("/v1/scores/top", params={"source": "play"}).json()
    assert [(e["name"], e["destination"]) for e in top["entries"]] == [("Gus", 0)]


def test_daily_snapshot_for_the_contest():
    from app import main, scores
    os.environ["ADMIN_TOKEN"] = "test-admin-token"
    admin = {"X-Admin-Token": "test-admin-token"}
    with main.db() as c:
        c.execute("DELETE FROM scores")
        c.execute("DELETE FROM score_snapshots")
    assert client.get("/v1/scores/snapshot", params={"source": "play"}).status_code == 404
    assert "No standings yet" in client.get("/v1/scores/snapshot.csv").text
    post("dev:11111111111111111111111111111111", "Ann", 50)
    post("dev:22222222222222222222222222222222", "=HYPERLINK(1)", 70)
    post("dev:33333333333333333333333333333333", "Cara", 90, source="scan")      # not a played game
    client.post("/v1/scores", json={"player": "dev:44444444444444444444444444444444", "name": "Fay", "score": 99,
                                    "platform": "test", "source": "fleet", "destination": 3})
    assert client.post("/v1/scores/snapshot", params={"source": "play"}).status_code == 403
    r = client.post("/v1/scores/snapshot", params={"source": "play"}, headers=admin)
    assert r.status_code == 200 and r.json()["count"] == 2
    snap = client.get("/v1/scores/snapshot", params={"source": "play"}).json()
    assert [(e["rank"], e["name"], e["score"]) for e in snap["entries"]] == [(1, "=HYPERLINK(1)", 70), (2, "Ann", 50)]
    assert snap["day"] == snap["taken_at_berlin"][:10]
    # later scores don't change the stored standings
    post("dev:55555555555555555555555555555555", "Late", 95)
    again = client.get("/v1/scores/snapshot", params={"source": "play", "day": snap["day"]}).json()
    assert [e["name"] for e in again["entries"]] == ["=HYPERLINK(1)", "Ann"]
    lines = client.get("/v1/scores/snapshot.csv", params={"source": "play"}).text.strip().split("\n")
    assert lines[0].startswith("Standings at ") and lines[0].endswith("(Berlin)")
    assert lines[1] == "Rank,Player,Score,Platform,Best set (Berlin)"
    assert lines[2].startswith("1,'=HYPERLINK(1),70,test,")      # formula-safe
    assert len(lines) == 4
    # Berlin dates: 2026-10-20 21:59 UTC is 23:59 summer time
    assert scores._berlin(1792533540) == "2026-10-20 23:59"
