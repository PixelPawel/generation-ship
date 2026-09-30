import json
import os
import struct
import tempfile

os.environ.setdefault("DB_PATH", os.path.join(tempfile.mkdtemp(), "votes.db"))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from starlette.websockets import WebSocketDisconnect  # noqa: E402

from app import relay  # noqa: E402
from app.main import app  # noqa: E402

client = TestClient(app)
H = struct.Struct("<iBB")


@pytest.fixture(autouse=True)
def _clear_rooms():
    relay.rooms.clear()
    yield
    relay.rooms.clear()


def host(ws, password="", version="1.0", max_players=4):
    ws.send_text(json.dumps({"op": "host", "name": "Pawel", "password": password,
                             "max_players": max_players, "version": version}))
    msg = json.loads(ws.receive_text())
    assert msg["op"] == "welcome" and msg["id"] == 1
    return msg["room"]


def join(ws, room, password="", version="1.0", name="Anna"):
    ws.send_text(json.dumps({"op": "join", "room": room, "name": name, "password": password, "version": version}))
    return json.loads(ws.receive_text())


def pkt(target, payload, mode=2, channel=0):
    return H.pack(target, mode, channel) + payload


def unpack(data):
    frm, mode, channel = H.unpack_from(data)
    return frm, mode, channel, data[H.size:]


def test_host_join_and_routing():
    with client.websocket_connect("/v1/relay") as h:
        code = host(h)
        assert client.get("/v1/rooms", params={"version": "1.0"}).json()["rooms"][0]["code"] == code
        with client.websocket_connect("/v1/relay") as a, client.websocket_connect("/v1/relay") as b:
            assert join(a, code)["id"] == 2
            assert json.loads(h.receive_text()) == {"op": "peer_joined", "id": 2, "name": "Anna"}
            assert join(b, code.lower(), name="Ben")["id"] == 3   # codes are case-insensitive
            assert json.loads(h.receive_text())["id"] == 3

            # client -> host (target ignored), tagged with the sender id
            a.send_bytes(pkt(3, b"hello host"))
            assert unpack(h.receive_bytes()) == (2, 2, 0, b"hello host")
            # host -> one client
            h.send_bytes(pkt(3, b"just ben", mode=0, channel=1))
            assert unpack(b.receive_bytes()) == (1, 0, 1, b"just ben")
            # host -> everyone except 3
            h.send_bytes(pkt(-3, b"not ben"))
            assert unpack(a.receive_bytes())[3] == b"not ben"
            # host -> broadcast
            h.send_bytes(pkt(0, b"all"))
            assert unpack(a.receive_bytes())[3] == b"all"
            assert unpack(b.receive_bytes())[3] == b"all"

        # both clients left -> host told
        left = {json.loads(h.receive_text())["id"] for _ in range(2)}
        assert left == {2, 3}


def test_join_errors():
    with client.websocket_connect("/v1/relay") as h:
        code = host(h, password="secret", max_players=2)
        room = client.get("/v1/rooms", params={"version": "1.0"}).json()["rooms"][0]
        assert room["locked"] is True
        with client.websocket_connect("/v1/relay") as a:
            assert join(a, code, password="nope") == {"op": "error", "reason": "wrong_password"}
        with client.websocket_connect("/v1/relay") as a:
            assert join(a, code, password="secret", version="0.9") == {"op": "error", "reason": "version_mismatch"}
        with client.websocket_connect("/v1/relay") as a:
            assert join(a, "ZZZZZZ") == {"op": "error", "reason": "not_found"}
        with client.websocket_connect("/v1/relay") as a:
            assert join(a, code, password="secret")["op"] == "welcome"
            h.receive_text()
            with client.websocket_connect("/v1/relay") as b:
                assert join(b, code, password="secret") == {"op": "error", "reason": "full"}


def test_started_rooms_hidden_and_closed_to_joins():
    with client.websocket_connect("/v1/relay") as h:
        code = host(h)
        h.send_text(json.dumps({"op": "players", "count": 3}))   # host + 2 bots
        h.send_text(json.dumps({"op": "start"}))
        with client.websocket_connect("/v1/relay") as a:
            assert join(a, code) == {"op": "error", "reason": "already_started"}
        assert client.get("/v1/rooms").json()["rooms"] == []


def test_host_leaving_closes_room():
    with client.websocket_connect("/v1/relay") as a:
        with client.websocket_connect("/v1/relay") as h:
            code = host(h)
            assert join(a, code)["op"] == "welcome"
        with pytest.raises(WebSocketDisconnect):
            a.receive_bytes()
    assert relay.rooms == {}


def test_version_filter_in_list():
    with client.websocket_connect("/v1/relay") as h:
        host(h, version="2.0")
        assert client.get("/v1/rooms", params={"version": "1.0"}).json()["rooms"] == []
        assert len(client.get("/v1/rooms", params={"version": "2.0"}).json()["rooms"]) == 1
