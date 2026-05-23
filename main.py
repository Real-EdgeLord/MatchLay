import asyncio
import uuid
import time
import logging
import os
from collections import defaultdict
from typing import Dict, Tuple
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

# ---------- Configuration ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
RELAY_HOST = "0.0.0.0"

# Parse UDP port range(s) from environment
RELAY_PORTS_CONFIG = os.getenv("NORAY_UDP_RELAY_PORTS", "5555-5560")
def parse_ports(config: str) -> list:
    ports = []
    for part in config.split(','):
        part = part.strip()
        if '-' in part:
            start, end = map(int, part.split('-'))
            ports.extend(range(start, end + 1))
        else:
            ports.append(int(part))
    return ports
AVAILABLE_RELAY_PORTS = parse_ports(RELAY_PORTS_CONFIG)
if not AVAILABLE_RELAY_PORTS:
    AVAILABLE_RELAY_PORTS = [5555]

# ---------- State ----------
rooms: Dict[str, dict] = {}          # room_id -> room data
room_port: Dict[str, int] = {}       # room_id -> assigned UDP port
client_to_room: Dict[Tuple[str, int], str] = {}   # (ip,port) -> room_id
room_clients: Dict[str, set] = defaultdict(set)   # room_id -> set of (ip,port)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- Models ----------
class HostRequest(BaseModel):
    public_data: dict
    private_data: dict | None = None

class JoinRequest(BaseModel):
    private_data: dict | None = None

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- UDP Relay Protocol (per room) ----------
class RoomUDPProtocol:
    def __init__(self, room_id: str, port: int):
        self.room_id = room_id
        self.port = port
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        logger.info(f"UDP relay listening on {RELAY_HOST}:{self.port} for room {self.room_id}")

    def datagram_received(self, data: bytes, addr: Tuple[str, int]):
        # Refresh room heartbeat
        if self.room_id in rooms:
            rooms[self.room_id]["last_heartbeat"] = time.time()
        else:
            return

        # Auto-register client on first packet
        if addr not in client_to_room:
            client_to_room[addr] = self.room_id
            room_clients[self.room_id].add(addr)
            rooms[self.room_id]["clients"].add(addr)
            logger.info(f"Registered client {addr} to room {self.room_id}")

        # Forward to all other clients in the same room
        for other_addr in room_clients[self.room_id]:
            if other_addr != addr:
                self.transport.sendto(data, other_addr)

    def error_received(self, exc):
        logger.error(f"UDP error on port {self.port}: {exc}")

    def connection_lost(self, exc):
        logger.info(f"UDP connection lost on port {self.port}")

# ---------- FastAPI with lifespan ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    asyncio.create_task(cleanup_expired_rooms())
    logger.info("Matchmaker started")
    yield
    # Shutdown: close all UDP transports
    for room in rooms.values():
        if "transport" in room:
            room["transport"].close()
    logger.info("Matchmaker shut down")

app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

async def verify_auth(x_api_key: str = Header(...)):
    if x_api_key != SECRET_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

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

# ---------- API Endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    # Find free UDP port
    used_ports = set(room_port.values())
    relay_port = None
    for port in AVAILABLE_RELAY_PORTS:
        if port not in used_ports:
            relay_port = port
            break
    if relay_port is None:
        raise HTTPException(status_code=503, detail="No free UDP ports")

    # Start UDP relay for this room
    protocol = RoomUDPProtocol(room_id, relay_port)
    loop = asyncio.get_running_loop()
    transport, _ = await loop.create_datagram_endpoint(
        lambda: protocol,
        local_addr=(RELAY_HOST, relay_port)
    )

    # Generate a host token for secure deletion (random string)
    host_token = str(uuid.uuid4())[:16]

    rooms[room_id] = {
        "room_id": room_id,
        "public_data": req.public_data,
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "clients": set(),
        "relay_port": relay_port,
        "transport": transport,
        "protocol": protocol,
        "host_token": host_token,
    }
    room_port[room_id] = relay_port
    logger.info(f"Room {room_id} created on port {relay_port}")
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": relay_port,
        "host_token": host_token,   # <-- required for deletion
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
    # Return relay info, but no host_token
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": room["relay_port"],
    }

@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest, auth=Depends(verify_auth)):
    if req.room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    rooms[req.room_id]["last_heartbeat"] = time.time()
    return {"status": "ok"}

@app.delete("/room/{room_id}")
async def delete_room(room_id: str, host_token: str, auth=Depends(verify_auth)):
    """Delete a room. Requires the host_token returned during /host."""
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    room = rooms[room_id]
    if room.get("host_token") != host_token:
        raise HTTPException(status_code=403, detail="Invalid host token")
    # Close UDP transport
    if "transport" in room:
        room["transport"].close()
    # Remove client mappings
    for addr in room["clients"]:
        client_to_room.pop(addr, None)
        room_clients[room_id].discard(addr)
    del room_port[room_id]
    del rooms[room_id]
    logger.info(f"Room {room_id} deleted by host")
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
            # Close transport
            if "transport" in rooms[rid]:
                rooms[rid]["transport"].close()
            # Remove mappings
            for addr in rooms[rid]["clients"]:
                client_to_room.pop(addr, None)
                room_clients[rid].discard(addr)
            del room_port[rid]
            del rooms[rid]
            logger.info(f"Room {rid} expired")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)
