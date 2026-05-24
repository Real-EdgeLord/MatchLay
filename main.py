# main.py – No ENetRelay, just matchmaking
import asyncio
import uuid
import time
import logging
import os
from contextlib import asynccontextmanager
from typing import Dict, Optional

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
NORAY_HOST = os.getenv("NORAY_HOST", "noray")
NORAY_PORT = int(os.getenv("NORAY_PORT", "8890"))
MATCH_TIMEOUT_SECONDS = 60

# ---------- State ----------
rooms: Dict[str, dict] = {}
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

# ---------- FastAPI ----------
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Matchmaker starting...")
    yield
    logger.info("Matchmaker shut down")

app = FastAPI(lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

async def verify_auth(x_api_key: str = Header(...)):
    if x_api_key != SECRET_KEY:
        raise HTTPException(401, "Invalid API key")

# ---------- Static dashboard ----------
static_dir = "static"
if not os.path.exists(static_dir):
    os.makedirs(static_dir)
app.mount("/dashboard", StaticFiles(directory=static_dir, html=True), name="static")

@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <html><head><meta http-equiv="refresh" content="0; url=/dashboard/dashboard.html"></head>
    <body>Redirecting to dashboard...</body></html>
    """

# ---------- API Endpoints ----------
@app.post("/host")
async def host_game(req: HostRequest, auth=Depends(verify_auth)):
    room_id = str(uuid.uuid4())[:8]
    host_token = str(uuid.uuid4())[:16]
    rooms[room_id] = {
        "room_id": room_id,
        "public_data": req.public_data,
        "private_data": req.private_data,
        "created_at": time.time(),
        "last_heartbeat": time.time(),
        "player_count": 0,
    }
    host_token_map[room_id] = host_token
    logger.info(f"Room {room_id} created")
    return {
        "room_id": room_id,
        "noray_host": PUBLIC_ADDR,      # public IP of your server
        "noray_port": NORAY_PORT,       # 8890
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
                "player_count": 0,    # We won't track counts now; can be added later
                "created_seconds_ago": int(now - room["created_at"])
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
        raise HTTPException(403, "Private data mismatch")
    return {
        "room_id": room_id,
        "noray_host": PUBLIC_ADDR,
        "noray_port": NORAY_PORT,
    }



@app.post("/player_joined")
async def player_joined(req: dict, auth=Depends(verify_auth)):
    room_id = req.get("room_id")
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    rooms[room_id]["player_count"] = rooms[room_id].get("player_count", 0) + 1
    return {"status": "ok"}

@app.post("/player_left")
async def player_left(req: dict, auth=Depends(verify_auth)):
    room_id = req.get("room_id")
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    rooms[room_id]["player_count"] = max(rooms[room_id].get("player_count", 0) - 1, 0)
    return {"status": "ok"}


@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest, auth=Depends(verify_auth)):
    if req.room_id not in rooms:
        raise HTTPException(404, "Room not found")
    rooms[req.room_id]["last_heartbeat"] = time.time()
    return {"status": "ok"}

@app.delete("/room/{room_id}")
async def delete_room(room_id: str, host_token: str, auth=Depends(verify_auth)):
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    if host_token_map.get(room_id) != host_token:
        raise HTTPException(403, "Invalid host token")
    del rooms[room_id]
    del host_token_map[room_id]
    logger.info(f"Room {room_id} deleted")
    return {"status": "deleted"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=HTTP_PORT)
