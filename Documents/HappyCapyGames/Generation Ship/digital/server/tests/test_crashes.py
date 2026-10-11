"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import tempfile

os.environ["DB_PATH"] = os.path.join(tempfile.mkdtemp(), "votes.db")
os.environ["ADMIN_TOKEN"] = "test-admin-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app.crashes import signature  # noqa: E402  (after app.main: it imports from it)

client = TestClient(app)
ADMIN = {"X-Admin-Token": "test-admin-token"}
LOG_A = """Godot Engine v4.7.stable.official - https://godotengine.org
Vulkan 1.3.280 - Forward+ - Using Device #0: Intel - Intel(R) UHD Graphics 620
ERROR: Condition "err != VK_SUCCESS" is true. Returning: FAILED
   at: C:\\godot\\drivers\\vulkan\\rendering_device_driver_vulkan.cpp:1234
CrashHandlerException: Program crashed
[1] RenderingDeviceDriverVulkan::command_queue_execute_and_present (C:\\godot\\drivers\\vulkan\\x.cpp:5678)
[2] <couldn't map PC to fn name>
"""


def post(install="0f8fad5b-d9cb-469f-a165-70867728950e", log=LOG_A, code="0xC0000005", phase="start", **kw):
    body = {"install": install, "build": "2026-10-11 abc1234", "exit_code": code, "phase": phase,
            "safe_mode": False, "os": "Windows 11 (26200)", "gpu": "Intel(R) UHD Graphics 620 (driver 27.20.100.8681)",
            "log": log, **kw}
    return client.post("/v1/crashes", json=body)


def test_signature_ignores_numbers_and_paths():
    s1, summary = signature("0xC0000005", LOG_A)
    s2, _ = signature("0xC0000005", LOG_A.replace("1234", "999").replace("C:\\godot", "D:\\build"))
    assert s1 == s2
    assert "CrashHandlerException" not in summary or "ERROR" in summary
    assert summary.startswith("0xC0000005 | ERROR")
    assert "command_queue_execute_and_present" in summary


def test_post_validation_and_report():
    assert post().status_code == 200
    assert post(install="1f8fad5b-d9cb-469f-a165-70867728950e").status_code == 200
    assert post(install="2f8fad5b-d9cb-469f-a165-70867728950e", log="nothing useful", code="0x1").status_code == 200
    assert post(install="short").status_code == 400
    assert post(code="C0000005").status_code == 400
    assert post(phase="later").status_code == 422
    assert post(log="x" * 64001).status_code == 422
    assert client.get("/v1/crashes/report").status_code == 403
    r = client.get("/v1/crashes/report", headers=ADMIN).json()
    assert r["total"] == 3
    top = r["groups"][0]
    assert top["players"] == 2 and top["count"] == 2
    assert top["gpus"] == {"Intel(R) UHD Graphics 620": 2}
    full = client.get(f"/v1/crashes/{top['latest_id']}", headers=ADMIN).json()
    assert "CrashHandlerException" in full["log"]
    assert client.get("/v1/crashes/report?format=csv", headers=ADMIN).text.startswith("signature,players")
