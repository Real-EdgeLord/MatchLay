# main.py – Matchmaker (no Noray dependency)
import asyncio
import uuid
import time
import logging
import os
import random
import string
from contextlib import asynccontextmanager
from typing import Dict, Optional, List

from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

# ---------- Configuration ----------
SECRET_KEY = os.getenv("SECRET_KEY", "change-me")
PUBLIC_ADDR = os.getenv("PUBLIC_ADDR", "localhost")
HTTP_PORT = int(os.getenv("HTTP_PORT", "8000"))
NORAY_PORT = int(os.getenv("NORAY_PORT", "8890"))   # still needed for port
MATCH_TIMEOUT_SECONDS = 60
CLEANUP_INTERVAL_SECONDS = 15

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("matchmaker")

# ---------- State ----------
rooms: Dict[str, dict] = {}

# ---------- Pydantic models ----------
class HostRequest(BaseModel):
    server_oid: str
    match_time: Optional[int] = None
    public_data: Optional[dict] = None
    private_data: Optional[dict] = None

class JoinBySecretRequest(BaseModel):
    secret: str

class AddPlayerRequest(BaseModel):
    player_oid: str

class RemovePlayerRequest(BaseModel):
    player_oid: str

class HeartbeatRequest(BaseModel):
    room_id: str

# ---------- Helper ----------
def generate_room_secret() -> str:
    while True:
        secret = ''.join(random.choices(string.ascii_uppercase, k=6))
        if not any(room.get("secret") == secret for room in rooms.values()):
            return secret

# ---------- Lifespan + cleanup ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Matchmaker starting...")
    cleanup_task = asyncio.create_task(cleanup_rooms_loop())
    yield
    cleanup_task.cancel()
    logger.info("Matchmaker shut down")

async def cleanup_rooms_loop():
    while True:
        await asyncio.sleep(CLEANUP_INTERVAL_SECONDS)
        now = time.time()
        to_delete = []
        for room_id, room in rooms.items():
            if now - room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
                logger.info(f"Room {room_id} expired (no heartbeat)")
                to_delete.append(room_id)
            elif len(room["players"]) == 0:
                logger.info(f"Room {room_id} removed (zero players)")
                to_delete.append(room_id)
        for room_id in to_delete:
            del rooms[room_id]

# ---------- FastAPI ----------
app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

async def verify_auth(x_api_key: str = Header(...)):
    if x_api_key != SECRET_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

# Static dashboard
static_dir = "static"
if not os.path.exists(static_dir):
    os.makedirs(static_dir)
app.mount("/dashboard", StaticFiles(directory=static_dir, html=True), name="static")

@app.get("/", response_class=HTMLResponse)
async def root():
    return '<html><head><meta http-equiv="refresh" content="0; url=/dashboard/dashboard.html"></head><body>Redirecting...</body></html>'

@app.get("/health")
async def health():
    return {"status": "alive"}

# ---------- API Endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    host_key = str(uuid.uuid4())[:16]
    secret = generate_room_secret()
    rooms[room_id] = {
        "room_id": room_id,
        "secret": secret,
        "host_key": host_key,
        "server_oid": req.server_oid,
        "match_time": req.match_time,
        "public_data": req.public_data or {},
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "players": [],
    }
    logger.info(f"Room {room_id} created | secret={secret} | host_key={host_key[:4]}...")
    return {
        "room_id": room_id,
        "secret": secret,
        "host_key": host_key,
        "noray_host": PUBLIC_ADDR,
        "noray_port": NORAY_PORT,
        "server_oid": req.server_oid,
    }

@app.get("/rooms")
async def list_rooms():
    now = time.time()
    result = []
    for room_id, room in rooms.items():
        if now - room["last_heartbeat"] < MATCH_TIMEOUT_SECONDS:
            result.append({
                "room_id": room_id,
                "public_data": room["public_data"],
                "player_count": len(room["players"]),
                "created_seconds_ago": int(now - room["created_at"]),
                "match_time": room["match_time"],
            })
    return {"rooms": result}

@app.post("/join")
async def join_by_secret(req: JoinBySecretRequest):
    found_room = None
    for room in rooms.values():
        if room["secret"] == req.secret:
            found_room = room
            break
    if not found_room:
        raise HTTPException(status_code=404, detail="Invalid room secret")
    if time.time() - found_room["last_heartbeat"] >= MATCH_TIMEOUT_SECONDS:
        raise HTTPException(status_code=410, detail="Room expired")
    return {
        "room_id": found_room["room_id"],
        "server_oid": found_room["server_oid"],
        "noray_host": PUBLIC_ADDR,
        "noray_port": NORAY_PORT,
    }

@app.post("/room/{room_id}/player")
async def add_player(room_id: str, req: AddPlayerRequest, x_host_key: str = Header(..., alias="X-Host-Key")):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    room = rooms[room_id]
    if room["host_key"] != x_host_key:
        raise HTTPException(status_code=403, detail="Invalid host key")
    if req.player_oid not in room["players"]:
        room["players"].append(req.player_oid)
        logger.info(f"Player {req.player_oid} joined room {room_id} (count={len(room['players'])})")
    return {"status": "ok", "player_count": len(room["players"])}

@app.delete("/room/{room_id}/player")
async def remove_player(room_id: str, req: RemovePlayerRequest, x_host_key: str = Header(..., alias="X-Host-Key")):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    room = rooms[room_id]
    if room["host_key"] != x_host_key:
        raise HTTPException(status_code=403, detail="Invalid host key")
    if req.player_oid in room["players"]:
        room["players"].remove(req.player_oid)
        logger.info(f"Player {req.player_oid} left room {room_id} (count={len(room['players'])})")
    return {"status": "ok", "player_count": len(room["players"])}

@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest, auth=Depends(verify_auth)):
    if req.room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    rooms[req.room_id]["last_heartbeat"] = time.time()
    return {"status": "ok"}

@app.delete("/room/{room_id}")
async def close_room(room_id: str, x_host_key: str = Header(..., alias="X-Host-Key"), auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    if rooms[room_id]["host_key"] != x_host_key:
        raise HTTPException(status_code=403, detail="Invalid host key")
    del rooms[room_id]
    logger.info(f"Room {room_id} closed by host")
    return {"status": "deleted"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)