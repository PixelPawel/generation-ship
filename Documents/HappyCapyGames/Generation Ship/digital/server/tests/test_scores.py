import os
import tempfile

os.environ.setdefault("DB_PATH", os.path.join(tempfile.mkdtemp(), "votes.db"))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)
P1 = "steam:76561198000000011"
P2 = "dev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


def post(player, name, score, details=None):
    r = client.post("/v1/scores", json={"player": player, "name": name, "score": score,
                                        "details": details or [], "platform": "test"})
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
