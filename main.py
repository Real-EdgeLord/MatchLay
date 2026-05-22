import asyncio
import uuid
import time
import logging
import os
from collections import defaultdict
from typing import Dict, Tuple

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

# ---------- Configuration from environment ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")
RELAY_UDP_PORT = int(os.getenv("RELAY_UDP_PORT", "5555"))
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
RELAY_HOST = "0.0.0.0"

# ---------- Application state ----------
rooms: Dict[str, dict] = {}
client_to_room: Dict[Tuple[str, int], str] = {}
room_clients: Dict[str, set] = defaultdict(set)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- Pydantic models ----------
class HostRequest(BaseModel):
    public_data: dict
    private_data: dict | None = None

class JoinRequest(BaseModel):
    private_data: dict | None = None

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- UDP Relay ----------
class SinglePortUDPRelay:
    def __init__(self):
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        logger.info(f"UDP relay listening on {RELAY_HOST}:{RELAY_UDP_PORT}")

    def datagram_received(self, data: bytes, addr: Tuple[str, int]):
        if addr not in client_to_room:
            null_pos = data.find(b'\x00')
            if null_pos == -1:
                logger.warning(f"Handshake from {addr} missing null terminator")
                return
            room_id = data[:null_pos].decode('utf-8')
            if room_id not in rooms:
                logger.warning(f"Handshake for unknown room {room_id} from {addr}")
                return
            client_to_room[addr] = room_id
            room_clients[room_id].add(addr)
            rooms[room_id]["clients"].add(addr)
            logger.info(f"Auto-registered {addr} to room {room_id}")
            data = data[null_pos+1:]
            if not data:
                return
        room_id = client_to_room[addr]
        for other_addr in room_clients[room_id]:
            if other_addr != addr:
                self.transport.sendto(data, other_addr)

    def error_received(self, exc):
        logger.error(f"UDP relay error: {exc}")

    def connection_lost(self, exc):
        logger.info("UDP relay closed")

# ---------- FastAPI ----------
app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

async def verify_auth(x_api_key: str = Header(...)):
    if x_api_key != SECRET_KEY:
        raise HTTPException(401, detail="Invalid API key")

# ---------- Static dashboard ----------
static_dir = "static"
if not os.path.exists(static_dir):
    os.makedirs(static_dir)
app.mount("/dashboard", StaticFiles(directory=static_dir, html=True), name="static")

@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <html><head><meta http-equiv="refresh" content="0; url=/dashboard/dashboard.html"></head>
    <body>Redirecting to <a href="/dashboard/dashboard.html">dashboard</a>...</body></html>
    """

# ---------- API endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    rooms[room_id] = {
        "room_id": room_id,
        "public_data": req.public_data,
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "clients": set(),
    }
    logger.info(f"Room {room_id} created")
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": RELAY_UDP_PORT
    }

@app.get("/rooms")
async def list_rooms():
    now = time.time()
    result = []
    for rid, room in rooms.items():
        if now - room["last_heartbeat"] < MATCH_TIMEOUT_SECONDS:
            result.append({
                "room_id": rid,
                "public_data": room["public_data"],
                "player_count": len(room["clients"]),
                "created_seconds_ago": int(now - room["created_at"])
            })
    return {"rooms": result}

@app.post("/join/{room_id}")
async def join_room(room_id: str, req: JoinRequest, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    room = rooms[room_id]
    if time.time() - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
        del rooms[room_id]
        raise HTTPException(status_code=410, detail="Room expired")
    if room["private_data"] and req.private_data != room["private_data"]:
        raise HTTPException(status_code=403, detail="Private data mismatch")
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": RELAY_UDP_PORT
    }

@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest, auth=Depends(verify_auth)):
    if req.room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    rooms[req.room_id]["last_heartbeat"] = time.time()
    return {"status": "ok"}

@app.delete("/room/{room_id}")
async def delete_room(room_id: str, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    for addr in rooms[room_id]["clients"]:
        client_to_room.pop(addr, None)
        room_clients[room_id].discard(addr)
    del rooms[room_id]
    logger.info(f"Room {room_id} deleted")
    return {"status": "deleted"}

# ---------- Background cleanup ----------
async def cleanup_expired_rooms():
    while True:
        await asyncio.sleep(10)
        now = time.time()
        expired = []
        for rid, room in rooms.items():
            if now - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
                expired.append(rid)
        for rid in expired:
            for addr in rooms[rid]["clients"]:
                client_to_room.pop(addr, None)
                room_clients[rid].discard(addr)
            del rooms[rid]
            logger.info(f"Room {rid} expired")

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(cleanup_expired_rooms())
    loop = asyncio.get_running_loop()
    transport, protocol = await loop.create_datagram_endpoint(
        lambda: SinglePortUDPRelay(),
        local_addr=(RELAY_HOST, RELAY_UDP_PORT)
    )
    app.state.udp_relay = protocol

@app.on_event("shutdown")
async def shutdown_event():
    if hasattr(app.state, "udp_relay") and app.state.udp_relay.transport:
        app.state.udp_relay.transport.close()
        logger.info("UDP relay closed")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)
