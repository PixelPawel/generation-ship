"""Online rooms + WebSocket relay for Generation Ship multiplayer.

Every player (Steam or Android) connects to /v1/relay with a WebSocket; the
server forwards game packets between the host and the other players of a
room. The game keeps its host-authoritative star topology: the host is peer
1, everyone else talks only to the host (Godot's SceneMultiplayer relays any
client-to-client traffic through the host itself).

Handshake (first text message from the client):
    {"op": "host", "name": str, "password": str, "max_players": 2-4, "version": str}
    {"op": "join", "room": str, "name": str, "password": str, "version": str}
Server replies {"op": "welcome", "id": int, "room": str} or
{"op": "error", "reason": str} (then closes).

Afterwards:
  * binary frames carry game packets:
      client -> server: [target: int32 LE][mode: u8][channel: u8][payload]
      server -> client: [from:   int32 LE][mode: u8][channel: u8][payload]
    From the host, target 0 = every client, >1 = that client, <0 = every
    client except -target. From a client the target is ignored (always host).
  * text frames are control messages:
      host -> server:  {"op": "start"} (hide the room, stop joins),
                       {"op": "players", "count": n} (count incl. bots, for the list),
                       {"op": "kick", "id": n}
      server -> host:  {"op": "peer_joined", "id": n}, {"op": "peer_left", "id": n}
When the host disconnects the room closes and every client is disconnected.
"""
import asyncio
import hashlib
import hmac
import json
import secrets
import struct
import time
from dataclasses import dataclass, field

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

router = APIRouter()

CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I
CODE_LEN = 6
MAX_ROOMS = 5000
MAX_PACKET = 1 << 20          # 1 MiB per game packet
HANDSHAKE_TIMEOUT = 10.0
MAX_NAME = 24
HEADER = struct.Struct("<iBB")


@dataclass
class Room:
    code: str
    host_name: str
    password_hash: str          # "" = no password
    max_players: int
    version: str
    started: bool = False
    reported_players: int = 1   # host's own count incl. bots
    peers: dict[int, WebSocket] = field(default_factory=dict)
    next_id: int = 2
    created: float = field(default_factory=time.time)

    def player_count(self) -> int:
        return max(len(self.peers), self.reported_players)


rooms: dict[str, Room] = {}
_lock = asyncio.Lock()


def _hash_password(code: str, password: str) -> str:
    return hashlib.sha256(f"{code}:{password}".encode()).hexdigest() if password else ""


def _new_code() -> str:
    while True:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
        if code not in rooms:
            return code


def _clean_name(name: object) -> str:
    return str(name or "Player").strip()[:MAX_NAME] or "Player"


@router.get("/v1/rooms")
def list_rooms(version: str = "") -> dict:
    out = []
    for r in rooms.values():
        if r.started or (version and r.version != version):
            continue
        out.append({
            "code": r.code,
            "name": r.host_name,
            "players": r.player_count(),
            "max_players": r.max_players,
            "locked": bool(r.password_hash),
        })
    out.sort(key=lambda r: (r["players"] >= r["max_players"], r["name"].lower()))
    return {"rooms": out}


async def _send_json(ws: WebSocket, msg: dict) -> None:
    if ws.application_state == WebSocketState.CONNECTED:
        try:
            await ws.send_text(json.dumps(msg))
        except Exception:
            pass


async def _send_bytes(ws: WebSocket, data: bytes) -> None:
    if ws.application_state == WebSocketState.CONNECTED:
        try:
            await ws.send_bytes(data)
        except Exception:
            pass


async def _fail(ws: WebSocket, reason: str) -> None:
    await _send_json(ws, {"op": "error", "reason": reason})
    try:
        await ws.close(code=4000)
    except RuntimeError:
        pass  # client already closed the socket


@router.websocket("/v1/relay")
async def relay(ws: WebSocket) -> None:
    await ws.accept()
    try:
        hello = json.loads(await asyncio.wait_for(ws.receive_text(), HANDSHAKE_TIMEOUT))
    except Exception:
        await _fail(ws, "bad_handshake")
        return
    op = hello.get("op")
    version = str(hello.get("version", ""))[:32]
    name = _clean_name(hello.get("name"))

    async with _lock:
        if op == "host":
            if len(rooms) >= MAX_ROOMS:
                room = None
                reason = "server_full"
            else:
                code = _new_code()
                max_players = min(max(int(hello.get("max_players", 4) or 4), 2), 4)
                room = Room(code, name, _hash_password(code, str(hello.get("password", ""))), max_players, version)
                room.peers[1] = ws
                rooms[code] = room
                peer_id = 1
                reason = ""
        elif op == "join":
            room = rooms.get(str(hello.get("room", "")).strip().upper())
            reason = ""
            if room is None:
                reason = "not_found"
            elif room.version != version:
                reason = "version_mismatch"
            elif room.started:
                reason = "already_started"
            elif room.player_count() >= room.max_players:
                reason = "full"
            elif room.password_hash and not hmac.compare_digest(
                room.password_hash, _hash_password(room.code, str(hello.get("password", "")))
            ):
                reason = "wrong_password"
            if reason:
                room = None
            else:
                peer_id = room.next_id
                room.next_id += 1
                room.peers[peer_id] = ws
        else:
            room = None
            reason = "bad_handshake"

    if room is None:
        await _fail(ws, reason)
        return

    await _send_json(ws, {"op": "welcome", "id": peer_id, "room": room.code})
    host_ws = room.peers.get(1)
    if peer_id != 1 and host_ws:
        await _send_json(host_ws, {"op": "peer_joined", "id": peer_id, "name": name})

    try:
        while True:
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                break
            data = msg.get("bytes")
            if data is not None:
                if len(data) < HEADER.size or len(data) > MAX_PACKET + HEADER.size:
                    continue
                target, mode, channel = HEADER.unpack_from(data)
                payload = data[HEADER.size:]
                out = HEADER.pack(peer_id, mode, channel) + payload
                if peer_id != 1:
                    if host_ws := room.peers.get(1):
                        await _send_bytes(host_ws, out)
                elif target == 0:
                    for pid, pws in list(room.peers.items()):
                        if pid != 1:
                            await _send_bytes(pws, out)
                elif target > 1:
                    if pws := room.peers.get(target):
                        await _send_bytes(pws, out)
                elif target < 0:
                    for pid, pws in list(room.peers.items()):
                        if pid != 1 and pid != -target:
                            await _send_bytes(pws, out)
                continue
            text = msg.get("text")
            if text is None or peer_id != 1:
                continue
            try:
                ctl = json.loads(text)
            except ValueError:
                continue
            if ctl.get("op") == "start":
                room.started = True
            elif ctl.get("op") == "players":
                room.reported_players = min(max(int(ctl.get("count", 1) or 1), 1), room.max_players)
            elif ctl.get("op") == "kick":
                if kicked := room.peers.get(int(ctl.get("id", 0) or 0)):
                    await kicked.close(code=4001)
    except WebSocketDisconnect:
        pass
    finally:
        await _leave(room, peer_id)


async def _leave(room: Room, peer_id: int) -> None:
    async with _lock:
        room.peers.pop(peer_id, None)
        if peer_id == 1:
            rooms.pop(room.code, None)
            others = list(room.peers.values())
            room.peers.clear()
        else:
            others = []
    if peer_id == 1:
        for pws in others:
            try:
                await pws.close(code=4002)  # host left
            except Exception:
                pass
    elif host_ws := room.peers.get(1):
        await _send_json(host_ws, {"op": "peer_left", "id": peer_id})
