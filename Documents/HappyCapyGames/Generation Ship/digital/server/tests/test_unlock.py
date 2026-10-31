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
    unlock._misses.clear()


def redeem_games(code, player, games):
    return client.post("/v1/unlock/redeem", json={"code": code, "player": player, "platform": "android",
                                                   "games_player": games})


def restore(player, games):
    return client.post("/v1/unlock/restore", json={"player": player, "games_player": games, "platform": "android"})


def test_one_use_is_one_play_games_account():
    code = make(1, "games", max_uses=1)[0]
    a1, a2, a3 = "dev:a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", "dev:a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2", "dev:a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"
    assert redeem_games(code, a1, "g_1001").json() == {"ok": True, "again": False}
    # a new phone signed in to the same account: the same code works again
    assert redeem_games(code, a2, "g_1001").json() == {"ok": True, "again": True}
    # anyone else is refused, signed in or not
    assert redeem(code, a3).status_code == 409
    assert redeem_games(code, a3, "g_2002").status_code == 409
    assert redeem_games(code, a3, "bad id!").status_code == 400


def test_restore_on_a_new_install():
    code = make(1, "restore", max_uses=1)[0]
    b1, b2, b3 = "dev:b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1", "dev:b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2", "dev:b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3"
    assert redeem_games(code, b1, "g_3003").status_code == 200
    assert restore(b2, "g_3003").json() == {"ok": True}       # reinstall / new phone, same account
    assert restore(b3, "g_9999").status_code == 404           # account that never redeemed a code
    with unlock.db() as c:
        assert c.execute("SELECT COUNT(*) FROM unlock_redemptions WHERE games_player = 'g_3003'").fetchone()[0] == 2


def test_restore_links_a_code_redeemed_before_signing_in():
    code = make(1, "link", max_uses=1)[0]
    c1, c2 = "dev:c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1", "dev:c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"
    assert redeem(code, c1).status_code == 200                # not signed in to Play Games yet
    assert restore(c1, "g_4004").status_code == 200           # signs in later: the code moves to the account
    assert restore(c2, "g_4004").status_code == 200           # so a new phone gets it back


def test_restore_misses_are_limited():
    d1 = "dev:d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"
    for _ in range(unlock.MISSES_PER_HOUR):
        assert restore(d1, "g_5005").status_code == 404
    assert restore(d1, "g_5005").status_code == 429


def test_erasure_removes_the_accounts_other_installs():
    code = make(1, "erase", max_uses=1)[0]
    e1, e2 = "dev:e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1", "dev:e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"
    assert redeem_games(code, e1, "g_6006").status_code == 200
    assert restore(e2, "g_6006").status_code == 200
    r = client.delete(f"/v1/admin/privacy/{e1}", headers=ADMIN).json()["deleted"]
    assert r["unlock_redemptions"] == 2
    assert restore(e2, "g_6006").status_code == 404


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
