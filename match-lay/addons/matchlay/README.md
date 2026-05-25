# 🎮 MatchLay Godot Plugin

[![Godot 4.6.3](https://img.shields.io/badge/Godot-4.6.3-478CBF?logo=godot-engine)](https://godotengine.org)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Built with AI slop](https://img.shields.io/badge/Built%20with-Certified%20AI%20Slop-ff69b4?style=flat-square)](https://github.com/Real-EdgeLord/MatchLay)

This plugin provides a **GDScript client** for the MatchLay matchmaker. It handles room creation, joining, player counts, and heartbeats – but **it does NOT handle the actual game connection**. For that, you need a UDP relay like [Noray](https://github.com/foxssake/noray). Think of MatchLay as the *directory* and Noray as the *bridge* that moves packets between players.

---

## 📦 Installation

1. Copy the `matchlay` folder into your Godot project's `addons/` directory.
2. Enable the plugin in **Project → Project Settings → Plugins**.
3. The `MatchLayAPI` class will be globally available.

---

## 🚀 Quick Start

### 1. Initialize the API

```gdscript
var api = MatchLayAPI.new()
add_child(api)
api.init("http://your-matchmaker-server:8000", "your-secret-key")

    your-secret-key must match the SECRET_KEY environment variable of your MatchLay server.

2. Host a Game (Game Server)
gdscript

api.room_hosted.connect(_on_room_hosted)

# server_oid: the Noray OID of your game server (obtained from Noray)
api.host_game(server_oid, 300, {"map": "arena", "mode": "dm"})

func _on_room_hosted(room_id: String, secret: String, host_key: String):
    print("Room created! Share this secret with players: ", secret)
    # The host_key is stored internally – you don't need to use it directly.
    # The plugin automatically adds the host as the first player.

3. Join a Game (Player Client)
gdscript

api.room_joined.connect(_on_room_joined)

# The secret is entered by the player (6 uppercase letters)
api.join_with_secret("ABCDEF")

func _on_room_joined(room_id: String, server_oid: String, player_count: int):
    print("Joined room ", room_id, " | server OID: ", server_oid)
    # Now connect your Noray client to the server_oid and the Noray host/port
    # (those are configured on the Noray server, not in MatchLay)

4. Handle Errors & Expiry
gdscript

api.error_occurred.connect(_on_error)
api.room_expired.connect(_on_room_expired)

func _on_error(code: int, message: String):
    print("MatchLay error: ", code, " - ", message)

func _on_room_expired(room_id: String):
    print("Room ", room_id, " expired or was closed")
    # Clean up local game state

📡 Signals (Full List)
Signal	Arguments	Description
rooms_listed	rooms: Array	Response to list_rooms(). Each room contains room_id, public_data, player_count, match_time.
room_hosted	room_id: String, secret: String, host_key: String	Successful room creation. The host key is stored internally; you only need the secret to share with players.
room_joined	room_id: String, server_oid: String, player_count: int	Successful join. Use server_oid to connect via Noray.
player_count_updated	room_id: String, player_count: int	Sent after add_player() or remove_player().
heartbeat_ok	–	Heartbeat successfully sent (host only).
room_closed	–	Room successfully closed via close_room().
error_occurred	code: int, message: String	Any HTTP or API error.
room_expired	room_id: String	The matchmaker deleted the room (no heartbeat or zero players).
server_down	–	The matchmaker server is unreachable (health check failed).
🛠️ API Methods
Method	Arguments	Description
init(url, key)	url: String, key: String	Sets the matchmaker URL and global API key. Must be called first.
host_game(server_oid, match_time, public_data)	server_oid: String, match_time: int, public_data: Dictionary	Creates a new room. Heartbeat starts automatically.
join_with_secret(secret)	secret: String	Joins a room using the 6‑letter secret.
join_with_room_id(room_id)	room_id: String	Joins a room using the short room ID (less secure).
list_rooms()	–	Fetches all active rooms; emits rooms_listed.
add_player(player_oid)	player_oid: String	Host only. Adds a player to the room.
remove_player(player_oid)	player_oid: String	Host only. Removes a player from the room.
close_room()	–	Host only. Closes the room permanently.
leave_room()	–	Cleans local state (does not call the server).
🔗 The Big Picture: MatchLay + Noray

MatchLay does not move game packets – it only helps players discover each other. The actual UDP relay is handled by Noray (or any other solution). Here's how they work together:

    Game server starts and registers itself with Noray, obtaining a server_oid.

    Game server calls host_game(server_oid, ...) on MatchLay. MatchLay returns a secret.

    Player receives the secret (e.g., from a chat message).

    Player calls join_with_secret(secret). MatchLay returns the server_oid.

    Player connects to Noray using the server_oid (and the public Noray host/port, which is known from your Noray deployment). From that point on, MatchLay is not involved – all game traffic flows via Noray.

This separation keeps the matchmaker simple and allows you to use any UDP relay (or even direct IP connections).
⚠️ Disclaimer

This software is provided “as is”, without warranty of any kind, express or implied. The authors are not responsible for any loss of data, network failures, or unexpected disconnections. You are responsible for securing your own deployment (HTTPS, firewall, etc.). MatchLay is intended for self‑hosted and educational use.
🤖 Certified AI Slop

    “This README was written by an AI that has never hosted a lobby and thinks UDP stands for ‘Unbelievably Dumb Packets’. If something breaks, please blame the AI – but fix it yourself.”

Yes, this documentation was generated by a large language model. The code is human‑written (mostly), but the friendly tone and reassuring bullet points are pure vectorized cognition. Use it, share it, and remember: the real latency was the friends we met along the way. 🎲

https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square

Made with ❤️ and ☕ for the Godot community.
