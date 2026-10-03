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
