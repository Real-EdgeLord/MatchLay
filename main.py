import asyncio
import uuid
import socket
import threading
import time
import logging
import os
from collections import defaultdict
from typing import Dict, Tuple, Set
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

from enet_relay import ENetRelay

# ---------- Configuration ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
PORT_START = int(os.getenv("PORT_START", "5555"))
PORT_END = int(os.getenv("PORT_END", "5560"))

# ---------- Global Relay ----------
enet_relay = ENetRelay()

# ---------- Application state ----------
rooms: Dict[str, dict] = {}
room_port: Dict[str, int] = {}
room_clients: Dict[str, Set[Tuple[str, int]]] = defaultdict(set)
client_to_room: Dict[Tuple[str, int], str] = {}
host_token_map: Dict[str, str] = {}

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


# Global variable for the echo socket
_echo_socket = None

def start_udp_echo():
    global _echo_socket
    if _echo_socket:
        return
    _echo_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    _echo_socket.bind(('0.0.0.0', 5550))   # <-- changed to 5550
    def _echo_loop():
        while True:
            data, addr = _echo_socket.recvfrom(1024)
            logger.info(f"UDP echo from {addr}: {data}")
            _echo_socket.sendto(data, addr)
    threading.Thread(target=_echo_loop, daemon=True).start()
    logger.info("UDP echo server started on port 5550")


def start_temp_echo():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', 5558))
    def loop():
        while True:
            data, addr = sock.recvfrom(1024)
            print(f"Temp echo received: {data} from {addr}")
            sock.sendto(data, addr)
    threading.Thread(target=loop, daemon=True).start()
    print("Temp UDP echo on port 5558")

# Inside lifespan:
async def lifespan(app: FastAPI):
    start_temp_echo()   # <-- add this line
    logger.info("Matchmaker starting...")
    yield
    enet_relay.shutdown()
    logger.info("Matchmaker shut down")

app = FastAPI(lifespan=lifespan)

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
    # Find a free port
    used_ports = set(room_port.values())
    relay_port = None
    for port in range(PORT_START, PORT_END + 1):
        if port not in used_ports:
            relay_port = port
            break
    if relay_port is None:
        raise HTTPException(status_code=503, detail="No free UDP ports")

    # Start the ENet relay for this room
    enet_relay.create_room(relay_port)


    host_token = str(uuid.uuid4())[:16]
    rooms[room_id] = {
        "room_id": room_id,
        "public_data": req.public_data,
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "relay_port": relay_port,
    }
    room_port[room_id] = relay_port
    host_token_map[room_id] = host_token
    logger.info(f"Room {room_id} created on port {relay_port}")
    return {
        "room_id": room_id,
        "relay_host": PUBLIC_ADDR,
        "relay_port": relay_port,
        "host_token": host_token,
    }

@app.get("/rooms")
async def list_rooms():
    now = time.time()
    result = []
    for rid, room in rooms.items():
        if now - room["last_heartbeat"] < MATCH_TIMEOUT_SECONDS:
            player_count = enet_relay.get_peer_count(room["relay_port"])
            result.append({
                "room_id": rid,
                "public_data": room["public_data"],
                "player_count": player_count,
                "created_seconds_ago": int(now - room["created_at"])
            })
    return {"rooms": result}

@app.post("/join/{room_id}")
async def join_room(room_id: str, req: JoinRequest, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    room = rooms[room_id]
    if time.time() - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
        # Room expired
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
async def delete_room(room_id: str, host_token: str, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    if host_token_map.get(room_id) != host_token:
        raise HTTPException(status_code=403, detail="Invalid host token")
    # Stop the ENet relay for this room
    relay_port = rooms[room_id]["relay_port"]
    enet_relay.remove_room(relay_port)
    # Clean up internal state
    del room_port[room_id]
    del rooms[room_id]
    del host_token_map[room_id]
    # Remove client address mappings
    for addr, rid in list(client_to_room.items()):
        if rid == room_id:
            del client_to_room[addr]
    if room_id in room_clients:
        del room_clients[room_id]
    logger.info(f"Room {room_id} deleted")
    return {"status": "deleted"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)

