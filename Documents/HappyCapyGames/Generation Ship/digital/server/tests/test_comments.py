"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile

os.environ["DB_PATH"] = os.path.join(tempfile.mkdtemp(), "votes.db")
os.environ["ADMIN_TOKEN"] = "test-admin-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)
K1 = "tv_PL_Tech_GSTechs44x67mm88"
K2 = "tv_DE_Expedition_GSExpeditions44x67mm3"
A = "steam:76561198000000001"
B = "dev:0f8fad5b-d9cb-469f-a165-70867728950e"
ADMIN = {"X-Admin-Token": "test-admin-token"}


def post(key, voter, field, text, version="1.0"):
    return client.post("/v1/comments", json={"key": key, "voter": voter, "field": field, "text": text, "version": version})


def test_post_and_multiple_per_player():
    r = post(K1, A, "effect", "  'zamiast tego' brakuje  ")
    assert r.status_code == 200, r.text
    assert r.json()["mine"] == 1
    assert post(K1, A, "name", "Nazwa za długa").json()["mine"] == 2   # more than one comment is fine
    assert post(K1, B, "effect", "Też uważam").status_code == 200


def test_validation():
    assert post("tv_EN_Tech_x", A, "effect", "hi").status_code == 400      # English isn't commented on
    assert post(K1, "admin", "effect", "hi").status_code == 400
    assert post(K1, A, "art", "hi").status_code == 400                     # only name/flavor/effect
    assert post(K1, A, "effect", "   ").status_code == 400
    assert post(K1, A, "effect", "x" * 501).status_code == 400


def test_report_needs_admin():
    assert client.get("/v1/comments/report").status_code == 403
    assert client.get("/v1/comments/report", headers={"X-Admin-Token": "wrong"}).status_code == 403


def test_report_groups_and_votes():
    client.post("/v1/votes", json={"key": K1, "voter": B, "value": -1})
    post(K2, A, "flavor", "Witz geht verloren")
    rep = client.get("/v1/comments/report", headers=ADMIN, params={"lang": "PL"}).json()
    assert rep["total"] == 3 and all(g["lang"] == "PL" for g in rep["groups"])
    top = rep["groups"][0]
    assert (top["key"], top["field"], top["players"], top["count"]) == (K1, "effect", 2, 2)
    assert top["votes_down"] == 1
    assert top["comments"][0]["text"] == "'zamiast tego' brakuje"          # trimmed
    assert len(top["comments"][0]["player"]) == 8                          # hashed tag, not the id
    csv_text = client.get("/v1/comments/report", headers=ADMIN, params={"format": "csv"}).text
    assert csv_text.splitlines()[0].startswith("id,key,lang,field,comment")
    assert "Witz geht verloren" in csv_text and A not in csv_text


def test_status_triage():
    rep = client.get("/v1/comments/report", headers=ADMIN, params={"lang": "DE"}).json()
    cid = rep["groups"][0]["comments"][0]["id"]
    assert client.post(f"/v1/comments/{cid}/status", json={"status": "done"}).status_code == 403
    assert client.post(f"/v1/comments/{cid}/status", headers=ADMIN, json={"status": "done"}).status_code == 200
    assert client.get("/v1/comments/report", headers=ADMIN, params={"lang": "DE"}).json()["total"] == 0   # default: open only
    assert client.get("/v1/comments/report", headers=ADMIN, params={"lang": "DE", "status": "done"}).json()["total"] == 1
    assert client.post("/v1/comments/999999/status", headers=ADMIN, json={"status": "done"}).status_code == 404
