import asyncio
import uuid
import time
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

from enet_relay import ENetRelay  # Import our new relay

# ---------- Configuration ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")
MATCH_TIMEOUT_SECONDS = int(os.getenv("MATCH_TIMEOUT_SECONDS", "60"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
RELAY_HOST = "0.0.0.0"

# ---------- Global Relay Instance ----------
enet_relay = ENetRelay()

# ---------- State ----------
rooms: Dict[str, dict] = {}          # room_id -> room data
room_port: Dict[str, int] = {}       # room_id -> assigned UDP port
room_clients: Dict[str, set] = defaultdict(set)   # room_id -> set of peer IDs (for dashboard)
host_token_map: Dict[str, str] = {}  # room_id -> host_token

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- Models (same as before) ----------
class HostRequest(BaseModel):
    public_data: dict
    private_data: dict | None = None

class JoinRequest(BaseModel):
    private_data: dict | None = None

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- FastAPI with lifespan ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: nothing needed, ENetRelay starts on demand
    logger.info("Matchmaker started")
    yield
    # Shutdown: close all ENet rooms
    enet_relay.shutdown()
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

# ---------- API endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    # Assign a free UDP port (you can reuse your port range logic)
    used_ports = set(room_port.values())
    relay_port = next((p for p in range(5555, 5561) if p not in used_ports), None)
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
            result.append({
                "room_id": rid,
                "public_data": room["public_data"],
                "player_count": len(room_clients.get(rid, [])),  # You'd need to track this from ENet
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
async def delete_room(room_id: str, host_token: str, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    if host_token_map.get(room_id) != host_token:
        raise HTTPException(status_code=403, detail="Invalid host token")
    # Stop the ENet relay
    enet_relay.remove_room(rooms[room_id]["relay_port"])
    del room_port[room_id]
    del rooms[room_id]
    del host_token_map[room_id]
    logger.info(f"Room {room_id} deleted")
    return {"status": "deleted"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)
