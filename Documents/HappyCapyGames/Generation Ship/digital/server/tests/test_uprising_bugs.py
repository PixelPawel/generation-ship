"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import json
import os
import tempfile

os.environ["DB_PATH"] = os.path.join(tempfile.mkdtemp(), "votes.db")
os.environ["ADMIN_TOKEN"] = "test-admin-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app import uprising_bugs  # noqa: E402  (after app.main: it imports from it)

client = TestClient(app)
ADMIN = {"X-Admin-Token": "test-admin-token"}


def body(**kw):
    b = {"card_sheet": "Items", "card_name": "Jitaka", "card_kind": "items", "category": "rules", "severity": "wrong",
         "summary": "Jitaka gives no Bolt", "actual": "I flipped Jitaka and no Bolt appeared.",
         "expected": "Flip this, to gain 1 BOLT.", "steps": "1. Test in game\n2. Flip Jitaka Before Damage",
         "reporter": "Pawel", "build": "dev a7d4978", "source": "test",
         "context": {"phase": "ACTIONS", "test": "Jitaka is in your hand."}, "log": "ERROR: something",
         "state": json.dumps({"chapter": 1, "players": [{"faction": "Druwhn"}]})}
    b.update(kw)
    return b


def setup_function(_fn):
    uprising_bugs._posts.clear()


def test_post_report_and_fetch():
    r = client.post("/v1/uprising/bugs", json=body())
    assert r.status_code == 200, r.text
    bug_id = r.json()["id"]
    rep = client.get("/v1/uprising/bugs/report", headers=ADMIN).json()
    row = next(x for x in rep["reports"] if x["id"] == bug_id)
    assert row["card_name"] == "Jitaka" and row["status"] == "new"
    assert row["has_state"] is True and row["has_log"] is True
    assert row["context"]["phase"] == "ACTIONS"
    assert "log" not in row and "state" not in row
    full = client.get(f"/v1/uprising/bugs/{bug_id}", headers=ADMIN).json()
    assert full["log"] == "ERROR: something"
    st = client.get(f"/v1/uprising/bugs/{bug_id}/state", headers=ADMIN)
    assert st.status_code == 200 and st.json()["chapter"] == 1


def test_admin_only():
    assert client.get("/v1/uprising/bugs/report").status_code == 403
    assert client.get("/v1/uprising/bugs/1", headers={"X-Admin-Token": "wrong"}).status_code == 403


def test_since_id_and_status():
    a = client.post("/v1/uprising/bugs", json=body(state="")).json()["id"]
    b = client.post("/v1/uprising/bugs", json=body(summary="Second one", state="")).json()["id"]
    rep = client.get(f"/v1/uprising/bugs/report?since_id={a}", headers=ADMIN).json()
    assert [x["id"] for x in rep["reports"]] == [b]
    r = client.post(f"/v1/uprising/bugs/{a}/status", headers=ADMIN, json={"status": "fixed", "fixed_in": "abc1234"})
    assert r.status_code == 200
    fixed = client.get("/v1/uprising/bugs/report?status=fixed", headers=ADMIN).json()["reports"]
    assert any(x["id"] == a and x["fixed_in"] == "abc1234" for x in fixed)
    assert client.get(f"/v1/uprising/bugs/{a}/state", headers=ADMIN).status_code == 404
    csv_text = client.get("/v1/uprising/bugs/report?format=csv", headers=ADMIN).text
    assert csv_text.splitlines()[0].startswith("id,status,card_sheet")


def test_validation_and_rate_limit():
    assert client.post("/v1/uprising/bugs", json=body(category="nope")).status_code == 422
    assert client.post("/v1/uprising/bugs", json=body(summary="")).status_code == 422
    assert client.post("/v1/uprising/bugs", json=body(state="{not json")).status_code == 400
    uprising_bugs._posts.clear()
    codes = [client.post("/v1/uprising/bugs", json=body(state="")).status_code for _ in range(6)]
    assert codes[:5] == [200] * 5 and codes[5] == 429


def test_delete_removes_snapshot():
    bug_id = client.post("/v1/uprising/bugs", json=body()).json()["id"]
    assert os.path.exists(uprising_bugs._state_path(bug_id))
    assert client.delete(f"/v1/uprising/bugs/{bug_id}", headers=ADMIN).status_code == 200
    assert not os.path.exists(uprising_bugs._state_path(bug_id))
    assert client.get(f"/v1/uprising/bugs/{bug_id}", headers=ADMIN).status_code == 404
