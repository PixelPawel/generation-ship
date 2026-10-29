"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile

os.environ.setdefault("DB_PATH", os.path.join(tempfile.mkdtemp(), "votes.db"))
os.environ["ADMIN_TOKEN"] = "test-admin-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app import unlock  # noqa: E402  (after app.main: it imports from it)

client = TestClient(app)
ADMIN = {"X-Admin-Token": "test-admin-token"}
P1 = "dev:11111111111111111111111111111111"
P2 = "steam:76561198000000099"
P3 = "dev:33333333333333333333333333333333"
P4 = "dev:44444444444444444444444444444444"


def make(count=2, batch="test", max_uses=3):
    r = client.post("/v1/unlock/codes", json={"count": count, "batch": batch, "max_uses": max_uses}, headers=ADMIN)
    assert r.status_code == 200, r.text
    return r.json()["codes"]


def redeem(code, player=P1):
    return client.post("/v1/unlock/redeem", json={"code": code, "player": player, "platform": "android"})


def setup_function():
    unlock._fails.clear()


def test_codes_need_admin():
    assert client.post("/v1/unlock/codes", json={"count": 1, "batch": "x"}).status_code == 403
    assert client.get("/v1/unlock/report").status_code == 403


def test_code_format_and_typing():
    code = make(1, "fmt")[0]
    assert len(code) == 14 and code[4] == "-" and code[9] == "-"
    assert not set(code.replace("-", "")) & set("IO01")
    # players may type it in lower case, without dashes, with spaces
    assert redeem(code.replace("-", " ").lower()).json() == {"ok": True, "again": False}


def test_uses_and_same_player_again():
    code = make(1, "uses", max_uses=2)[0]
    assert redeem(code, P1).json()["again"] is False
    assert redeem(code, P1).json()["again"] is True       # reinstall on the same id: free
    assert redeem(code, P2).status_code == 200
    assert redeem(code, P3).status_code == 409             # 2 players already
    rep = {b["batch"]: b for b in client.get("/v1/unlock/report", headers=ADMIN).json()["batches"]}
    assert rep["uses"]["codes"] == 1 and rep["uses"]["used_codes"] == 1 and rep["uses"]["redemptions"] == 2


def test_wrong_codes_are_limited():
    for _ in range(unlock.FAILS_PER_HOUR):
        assert redeem("AAAA-BBBB-CCCC", P4).status_code == 404
    assert redeem("AAAA-BBBB-CCCC", P4).status_code == 429
    # a real code is refused too while the IP is locked out
    assert redeem(make(1, "late")[0], P4).status_code == 429


def test_bad_input():
    assert redeem(make(1, "bad")[0], "nope").status_code == 400
    assert client.post("/v1/unlock/codes", json={"count": 1, "batch": "no spaces"}, headers=ADMIN).status_code == 400
    assert client.post("/v1/unlock/codes", json={"count": 0, "batch": "x"}, headers=ADMIN).status_code == 422
