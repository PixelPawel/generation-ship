"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile

os.environ["DB_PATH"] = os.path.join(tempfile.mkdtemp(), "votes.db")

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)
K1 = "tv_PL_Tech_GSTechs44x67mm12"
K2 = "tv_DE_Sector_GSSector167x44mm"
A = "steam:76561198000000001"
B = "dev:0f8fad5b-d9cb-469f-a165-70867728950e"


def votes(keys, voter=None):
    params = {"keys": ",".join(keys)}
    if voter:
        params["voter"] = voter
    r = client.get("/v1/votes", params=params)
    assert r.status_code == 200, r.text
    return r.json()["votes"]


def vote(key, voter, value):
    return client.post("/v1/votes", json={"key": key, "voter": voter, "value": value})


def test_empty_counts():
    assert votes([K1]) == {K1: {"up": 0, "down": 0, "mine": 0}}


def test_vote_change_and_retract():
    assert vote(K1, A, 1).json()["votes"][K1] == {"up": 1, "down": 0, "mine": 1}
    assert vote(K1, B, -1).json()["votes"][K1] == {"up": 1, "down": 1, "mine": -1}
    # A changes their mind: still one row per voter
    assert vote(K1, A, -1).json()["votes"][K1] == {"up": 0, "down": 2, "mine": -1}
    # A retracts: 0 isn't counted
    assert vote(K1, A, 0).json()["votes"][K1] == {"up": 0, "down": 1, "mine": 0}
    assert votes([K1, K2], B) == {K1: {"up": 0, "down": 1, "mine": -1}, K2: {"up": 0, "down": 0, "mine": 0}}


def test_validation():
    assert vote("tv_EN_Tech_x", A, 1).status_code == 400          # English isn't voted on
    assert vote("drop table votes", A, 1).status_code == 400
    assert vote(K1, "admin", 1).status_code == 400
    assert vote(K1, A, 5).status_code == 422
    assert client.get("/v1/votes", params={"keys": ""}).status_code in (400, 422)


def test_report_orders_by_downvotes():
    vote(K2, A, -1)
    vote(K2, B, -1)
    cards = client.get("/v1/votes/report", params={"lang": "DE"}).json()["cards"]
    assert cards[0] == {"key": K2, "up": 0, "down": 2}
    assert all(c["key"].startswith("tv_DE_") for c in cards)


def test_rate_limit():
    codes = [vote(K1, A, 1).status_code for _ in range(40)]
    assert 429 in codes
