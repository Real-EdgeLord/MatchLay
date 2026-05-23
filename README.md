# MatchLay

MatchLay is a self‑hosted, open‑source matchmaking and UDP relay server designed for Godot games. It provides a simple HTTP API for creating and joining game rooms, and a high‑performance UDP relay for forwarding game traffic.

## Features
- HTTP matchmaker with public/private room data
- Single‑port UDP relay with room isolation
- Automatic client registration and packet forwarding
- Room heartbeat to prevent timeouts
- Web dashboard for monitoring active rooms

## Getting Started

### Server Deployment (Docker)
1. Clone the repository: `git clone https://github.com/Real-EdgeLord/MatchLay.git`
2. Edit `docker-compose.yml` and set your `PUBLIC_ADDR` and `SECRET_KEY`.
3. Run: `docker compose up -d`

### Godot Client Integration
1. Copy the `addons/matchlay` folder into your Godot project.
2. Enable the plugin in **Project Settings → Plugins**.
3. Use the `MatchLayAPI` class to host/join rooms, and the standard `ENetMultiplayerPeer` for game traffic.

## API Endpoints
- `POST /host` – Create a new game room.
- `GET /rooms` – List available rooms.
- `POST /join/{room_id}` – Join an existing room.
- `POST /heartbeat` – Keep a room alive.
- `DELETE /room/{room_id}` – Delete a room.

## License
MIT
