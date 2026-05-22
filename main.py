import asyncio
import uuid
import time
import logging
import os
import re
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
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
RELAY_HOST = "0.0.0.0"

# Parse UDP port(s) from environment – supports single port, range, or comma‑separated list
RELAY_PORTS_CONFIG = os.getenv("NORAY_UDP_RELAY_PORTS", "5555")
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

# ---------- Application state ----------
rooms: Dict[str, dict] = {}                     # room_id -> room data
client_to_room: Dict[Tuple[str, int], str] = {}  # (client_ip, client_port) -> room_id
room_clients: Dict[str, set] = defaultdict(set)  # room_id -> set of (ip, port)
# Track which UDP port each room is using (if using multiple ports)
room_port: Dict[str, int] = {}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- Pydantic models for API ----------
class HostRequest(BaseModel):
    public_data: dict
    private_data: dict | None = None

class JoinRequest(BaseModel):
    private_data: dict | None = None

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- UDP Relay (supports multiple ports) ----------
class MultiPortUDPRelay:
    """
    A UDP relay that can listen on multiple ports (one per room) or a single port.
    Each room gets its own port (if enough are available) for cleaner traffic separation.
    """
    def __init__(self):
        self.transports: Dict[int, asyncio.DatagramTransport] = {}  # port -> transport
        self.port_usage: Dict[int, str] = {}  # port -> room_id

    async def start(self):
        """Start listening on all configured ports."""
        for port in AVAILABLE_RELAY_PORTS:
            loop = asyncio.get_running_loop()
            transport, protocol = await loop.create_datagram_endpoint(
                lambda: RoomUDPProtocol(self, port),
                local_addr=(RELAY_HOST, port)
            )
            self.transports[port] = transport
            logger.info(f"UDP relay listening on {RELAY_HOST}:{port}")

    def get_port_for_room(self, room_id: str) -> int:
        """Assign a port to a new room (or return existing one)."""
        if room_id in room_port:
            return room_port[room_id]
        # Find first unused port
        used_ports = set(self.port_usage.values())
        for port in AVAILABLE_RELAY_PORTS:
            if port not in used_ports:
                self.port_usage[port] = room_id
                room_port[room_id] = port
                logger.info(f"Assigned port {port} to room {room_id}")
                return port
        logger.error(f"No free UDP ports available for room {room_id}")
        return AVAILABLE_RELAY_PORTS[0]  # fallback

    def release_port(self, room_id: str):
        """Free the port when room is deleted."""
        if room_id in room_port:
            port = room_port[room_id]
            if port in self.port_usage:
                del self.port_usage[port]
            del room_port[room_id]
            logger.info(f"Released port {port} from room {room_id}")

    async def shutdown(self):
        """Close all UDP transports."""
        for transport in self.transports.values():
            transport.close()

class RoomUDPProtocol:
    """Protocol for a single UDP port, handling clients for a specific room."""
    def __init__(self, relay: MultiPortUDPRelay, port: int):
        self.relay = relay
        self.port = port
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data: bytes, addr: Tuple[str, int]):
        # Determine which room this port belongs to
        room_id = self.relay.port_usage.get(self.port)
        if not room_id:
            logger.warning(f"Received packet on port {self.port} with no room assigned")
            return

        # If this is the first packet from this client, register them
        if addr not in client_to_room:
            # Auto‑register via handshake (room_id + null byte)
            null_pos = data.find(b'\x00')
            if null_pos == -1:
                logger.warning(f"Handshake from {addr} missing null terminator")
                return
            client_room_id = data[:null_pos].decode('utf-8')
            if client_room_id != room_id:
                logger.warning(f"Handshake for room {client_room_id} on port {self.port} (expected {room_id})")
                return
            # Register client
            client_to_room[addr] = room_id
            room_clients[room_id].add(addr)
            rooms[room_id]["clients"].add(addr)
            logger.info(f"Auto-registered {addr} to room {room_id} on port {self.port}")
            # Remove handshake prefix
            data = data[null_pos+1:]
            if not data:
                return
        else:
            # Ensure client is in the correct room (should be, but verify)
            if client_to_room.get(addr) != room_id:
                logger.warning(f"Client {addr} sent packet for wrong room")
                return

        # Forward the packet to all other clients in the same room
        for other_addr in room_clients[room_id]:
            if other_addr != addr:
                self.transport.sendto(data, other_addr)

    def error_received(self, exc):
        logger.error(f"UDP protocol error on port {self.port}: {exc}")

    def connection_lost(self, exc):
        logger.info(f"UDP connection lost on port {self.port}")

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

# ---------- API endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    # Assign a UDP port for this room
    relay_port = udp_relay.get_port_for_room(room_id)
    rooms[room_id] = {
        "room_id": room_id,
        "public_data": req.public_data,
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "clients": set(),
        "relay_port": relay_port,
    }
    logger.info(f"Room {room_id} created on UDP port {relay_port}")
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": relay_port,
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
        "relay_port": room["relay_port"],
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
    # Free the UDP port
    udp_relay.release_port(room_id)
    # Remove all client mappings
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
            udp_relay.release_port(rid)
            for addr in rooms[rid]["clients"]:
                client_to_room.pop(addr, None)
                room_clients[rid].discard(addr)
            del rooms[rid]
            logger.info(f"Room {rid} expired")

# ---------- Startup / Shutdown ----------
@app.on_event("startup")
async def startup_event():
    global udp_relay
    udp_relay = MultiPortUDPRelay()
    await udp_relay.start()
    asyncio.create_task(cleanup_expired_rooms())
    logger.info("Matchmaker started")

@app.on_event("shutdown")
async def shutdown_event():
    await udp_relay.shutdown()
    logger.info("Matchmaker shut down")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)
