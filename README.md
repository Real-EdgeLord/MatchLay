# 🔌 MatchLay

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Godot 4.6.3](https://img.shields.io/badge/Godot-4.6.3-478CBF?logo=godot-engine)](https://godotengine.org)
[![Python 3.12](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.104-009485?logo=fastapi)](https://fastapi.tiangolo.com)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

**MatchLay** is a lightweight, self-hosted matchmaker for Godot multiplayer games. It provides a simple HTTP API for hosting and joining game rooms, with built‑in rate limiting, heartbeat expiry, and player tracking – all wrapped in a Godot plugin.

This is not a full‑blown backend service. It’s a focused tool that gets your players together and lets you focus on the gameplay. 🎮

---

## 🚀 Features

- **HTTP matchmaker** – host/join rooms with public metadata and optional secrets.
- **Room secrets** – 6‑letter codes players use to join.
- **Host keys** – per‑room tokens for server‑side management (add/remove players, close room).
- **Automatic player tracking** – host is added as first player; player counts are always accurate.
- **Heartbeat system** – rooms expire automatically if the game server stops responding.
- **Rate limiting** – 60 requests per minute per IP to prevent abuse.
- **Dashboard** – live web UI to monitor active rooms.
- **Godot plugin** – simple GDScript API with clear signals.
- **Docker ready** – one‑command deployment with `docker compose up -d`.

---

## 📖 Table of Contents

- [🔌 MatchLay](#-matchlay)
- [🚀 Features](#-features)
- [🎮 The Big Picture](#-the-big-picture)
  * [The Game Server Flow](#the-game-server-flow)
  * [The Player Client Flow](#the-player-client-flow)
- [🛠️ Deployment (Docker)](#️-deployment-docker)
- [🎮 Godot Client Integration](#-godot-client-integration)
- [🔌 API Reference](#-api-reference)
  * [Authentication](#authentication)
  * [Endpoints](#endpoints)
- [🔒 Security & Good Practices](#-security--good-practices)
- [📜 License](#-license)
- [⚠️ Disclaimer](#️-disclaimer)
- [🤖 Certified AI Slop](#-certified-ai-slop)

---

## 🎮 The Big Picture

MatchLay is a **matchmaker** – it helps players find each other. It does **not** handle the actual game connection. That’s what Noray (or any UDP relay) is for.

### The Game Server Flow

When a game server starts, you call `POST /host` to create a room. The matchmaker returns a `secret` (6 letters) and a `host_key` (16 chars). The host shares the `secret` with players, keeps the `host_key` for itself, and starts sending heartbeats every 30 seconds to keep the room alive. When players join via Noray, the host calls `POST /room/{room_id}/player` to update the matchmaker’s player count.

### The Player Client Flow

Players enter the `secret` provided by the host. The matchmaker verifies the secret and returns the `server_oid` (Noray endpoint) and current `player_count`. The player then connects directly to the game server via Noray – the matchmaker is no longer involved in gameplay.

This separation keeps the matchmaker simple and fast while letting you plug in any UDP relay you like (Noray, ENet, etc.).

---

## 🛠️ Deployment (Docker)

The easiest way to run the matchmaker is with Docker.

1. **Clone the repository**

   ```bash
   git clone https://github.com/Real-EdgeLord/MatchLay.git
   cd MatchLay
1. **Configure environment variables**  
2. Edit docker-compose.yml and set your PUBLIC_ADDR and SECRET_KEY:  
3. yaml  
4. environment:  - SECRET_KEY=your-secure-key-here   # required for API authentication  - PUBLIC_ADDR=192.168.0.111         # public IP of your server  
5. **Start the stack**  
6. bash  
7. docker compose up -d  
8. The matchmaker will be available at http://<PUBLIC_ADDR>:8000. The dashboard lives at /dashboard/dashboard.html.  
9. **Logs & status**  
10. bash  
11. docker logs matchmakercurl http://<PUBLIC_ADDR>:8000/health   # should return {"status":"alive"}  
## **🎮 Godot Client Integration**  
The Godot plugin is the easiest way to talk to the matchmaker.  
12. **Copy the plugin** – Move the addons/matchlay folder into your Godot project’s addons/ directory.  
13. **Enable the plugin** – Go to Project → Project Settings → Plugins and enable MatchLay.  
14. **Use the ** **MatchLayAPI** ** class**  
15. gdscript  
16. # Create the API objectvar api = MatchLayAPI.new()add_child(api)# Initialize with your server URL and secret keyapi.init("http://your-server:8000", "your-secret-key")# Connect signalsapi.room_hosted.connect(_on_room_hosted)api.room_joined.connect(_on_room_joined)api.error_occurred.connect(_on_error)  
17. **Host a game**  
18. gdscript  
19. func host_match():    api.host_game(        "my-noray-server-oid",  # your Noray server OID        300,                    # match duration in seconds        {"map": "arena", "mode": "deathmatch"}    )  
20. **Join a game using the 6‑letter secret**  
21. gdscript  
22. func join_match(secret_code: String):    api.join_with_secret(secret_code)  
All signals and methods are fully documented in the plugin’s matchlay_api.gd file. The heartbeat is managed automatically – you don’t need to worry about it.  
## **🔌 API Reference**  
All endpoints (except /health) require the X-API-Key header. Rate limiting is set to 60 requests per minute per IP.  
### **Authentication**  
http  
X-API-Key: your-secret-key  
### **Endpoints**  
| | | |  
|-|-|-|  
| **Method** | **Endpoint** | **Description** |   
| POST | /host | Create a new room |   
| GET | /rooms | List all active rooms |   
| POST | /join | Join a room using a 6‑letter secret |   
| POST | /join/{room_id} | Join a room using the room ID (less secure) |   
| POST | /room/{room_id}/player | Add a player (host only, requires X-Host-Key) |   
| DELETE | /room/{room_id}/player | Remove a player (host only, requires X-Host-Key) |   
| POST | /heartbeat | Keep a room alive (host only, requires X-Host-Key) |   
| DELETE | /room/{room_id} | Close a room (host only, requires X-Host-Key) |   
| GET | /health | Health check (no API key required) |   
#### ***Example: Host a room***  
bash  
curl -X POST http://localhost:8000/host \  -H "X-API-Key: your-secret-key" \  -H "Content-Type: application/json" \  -d '{    "server_oid": "my-noray-server-oid",    "match_time": 300,    "public_data": {"map": "arena"}  }'  
**Response:**  
json  
{  "room_id": "a1b2c3d4",  "secret": "ABCDEF",  "host_key": "1234567890abcdef"}  
#### ***Example: Join a room using the secret***  
bash  
curl -X POST http://localhost:8000/join \  -H "X-API-Key: your-secret-key" \  -H "Content-Type: application/json" \  -d '{"secret": "ABCDEF"}'  
**Response:**  
json  
{  "room_id": "a1b2c3d4",  "server_oid": "my-noray-server-oid",  "player_count": 1}  
## **🔒 Security & Good Practices**  
- **Keep your ** **SECRET_KEY** ** safe** – this is the master key for all matchmaker operations. Store it in environment variables, never in code or version control.  
- **Use HTTPS in production** – put the matchmaker behind a reverse proxy (nginx, Caddy) with TLS termination.  
- **Rate limiting is enabled** – 60 requests per minute per IP is a reasonable default, but adjust it in main.py (line 14) if needed.  
- **Secrets vs. room IDs** – use POST /join with the 6‑letter secret for private rooms. Room IDs are shorter and easier to guess; they’re fine for public lobbies.  
- **Host keys are never exposed to players** – they are used only by the game server for management operations.  
- **Automatic cleanup** – rooms expire after 60 seconds without a heartbeat, or immediately when player count reaches zero.  
## **📜 License**  
MIT. See [LICENSE](https://license/ "https://license/") for details.  
## **⚠️ Disclaimer**  
This software is provided “as is”, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.  
You are responsible for securing your own deployment. The default configuration is not suitable for production without proper hardening (HTTPS, firewall rules, rate limiting tuning, etc.). This project is intended for educational and self‑hosted use; you assume all risks associated with its operation.  
## **🤖 Certified AI Slop**  
*“This README was generated by an AI that can’t even play your game, let alone host a room. If you find any bugs, you keep them. The AI is not responsible for lost weekends, coffee spills, or inexplicable UDP packet loss.”*  
Yes, parts of this documentation were written by a large language model. The **code** is human‑made (mostly), but the soothing, reassuring tone of this README? That’s pure vectorized cognition, baby. Use it, laugh at it, and remember: the real matchmaker was the friends we made along the way. 🎲  
[https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square](https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square "https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square")  
*Made with ❤️ and ☕ for the Godot community.*  
   
