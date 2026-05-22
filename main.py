import asyncio
import uuid
import time
import logging
from collections import defaultdict
from typing import Dict, Tuple
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
import os

# ---------- Configuration from Environment ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me")
RELAY_UDP_PORT = int(os.getenv("RELAY_UDP_PORT", "5555"))
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
RELAY_HOST = "0.0.0.0"
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")

# ---------- State ----------
rooms: Dict[str, dict] = {}
# client address (ip, port) -> room_id
client_to_room: Dict[Tuple[str, int], str] = {}
# room_id -> set of client addresses
room_clients: Dict[str, set] = defaultdict(set)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- Pydantic Models ----------
class HostRequest(BaseModel):
    public_data: dict
    private_data: dict | None = None

class JoinRequest(BaseModel):
    private_data: dict | None = None

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- UDP Relay (single port) ----------
class SinglePortUDPRelay:
    def __init__(self):
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        logger.info(f"UDP relay listening on {RELAY_HOST}:{RELAY_UDP_PORT}")

    def datagram_received(self, data, addr):
        # Find which room this client belongs to
        room_id = client_to_room.get(addr)
        if room_id is None:
            logger.warning(f"UDP from unknown {addr} – dropping")
            return
        # Forward to all other clients in same room
        for other_addr in room_clients.get(room_id, set()):
            if other_addr != addr:
                self.transport.sendto(data, other_addr)

    def error_received(self, exc):
        logger.error(f"UDP error: {exc}")

    def connection_lost(self, exc):
        logger.info("UDP relay closed")

# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    loop = asyncio.get_running_loop()
    transport, protocol = await loop.create_datagram_endpoint(
        lambda: SinglePortUDPRelay(),
        local_addr=(RELAY_HOST, RELAY_UDP_PORT)
    )
    app.state.udp_relay = protocol
    logger.info("Matchmaker started")
    yield
    if hasattr(app.state, "udp_relay") and app.state.udp_relay.transport:
        app.state.udp_relay.transport.close()
    logger.info("Shutdown")

app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

async def verify_auth(x_api_key: str = Header(...)):
    if x_api_key != SECRET_KEY:
        raise HTTPException(401, "Invalid API Key")

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
    return {"room_id": room_id, "relay_host": PUBLIC_ADDR, "relay_port": RELAY_UDP_PORT}

@app.get("/rooms")
async def list_rooms():
    now = time.time()
    result = []
    for rid, room in rooms.items():
        if now - room["last_heartbeat"] < MATCH_TIMEOUT_SECONDS:
            result.append({
                "room_id": rid,
                "public_data": room["public_data"],
                "player_count": len(room["clients"])
            })
    return {"rooms": result}

@app.post("/join/{room_id}")
async def join_room(room_id: str, req: JoinRequest, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    room = rooms[room_id]
    if time.time() - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
        del rooms[room_id]
        raise HTTPException(410, "Room expired")
    if room["private_data"] and req.private_data != room["private_data"]:
        raise HTTPException(403, "Invalid private data")
    # Client will later register its UDP address via /register_client
    return {"room_id": room_id, "relay_host": PUBLIC_ADDR, "relay_port": RELAY_UDP_PORT}

@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest, auth=Depends(verify_auth)):
    if req.room_id not in rooms:
        raise HTTPException(404, "Room not found")
    rooms[req.room_id]["last_heartbeat"] = time.time()
    return {"status": "ok"}

@app.post("/register_client")
async def register_client(room_id: str, client_addr: str, client_port: int, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    addr = (client_addr, client_port)
    client_to_room[addr] = room_id
    room_clients[room_id].add(addr)
    rooms[room_id]["clients"].add(addr)
    logger.info(f"Registered {addr} to room {room_id}")
    return {"status": "ok"}

@app.delete("/room/{room_id}")
async def delete_room(room_id: str, auth=Depends(verify_auth)):
    if room_id in rooms:
        for addr in rooms[room_id]["clients"]:
            client_to_room.pop(addr, None)
            room_clients[room_id].discard(addr)
        del rooms[room_id]
        logger.info(f"Room {room_id} deleted")
        return {"status": "deleted"}
    raise HTTPException(404, "Room not found")

# ---------- Cleanup expired rooms ----------
async def cleaner():
    while True:
        await asyncio.sleep(10)
        now = time.time()
        expired = [rid for rid, room in rooms.items() if now - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS]
        for rid in expired:
            for addr in rooms[rid]["clients"]:
                client_to_room.pop(addr, None)
                room_clients[rid].discard(addr)
            del rooms[rid]
            logger.info(f"Room {rid} expired")

@app.on_event("startup")
async def start_cleaner():
    asyncio.create_task(cleaner())

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
