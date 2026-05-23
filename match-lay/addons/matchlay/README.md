# MatchLay Godot Plugin

This plugin provides a GDScript client for the MatchLay matchmaking and UDP relay server.

## Installation

1. Copy the `matchlay` folder into your Godot project's `addons/` directory.
2. Enable the plugin in **Project → Project Settings → Plugins**.
3. The `MatchLayAPI` class will be globally available.

## Usage

### Basic Setup

```gdscript
var api = MatchLayAPI.new()
api.init("http://your-server:8000", "your-secret-key")
```

### Hosting a Game

```gdscript
api.room_hosted.connect(_on_room_hosted)
api.host_game({"map": "arena"}, {"password": "secret"})

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
    var peer = ENetMultiplayerPeer.new()
    peer.create_server(relay_port)
    multiplayer.multiplayer_peer = peer
```

### Joining a Game

```gdscript
api.room_joined.connect(_on_room_joined)
api.join_game(room_id, {"password": "secret"})

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
    var peer = ENetMultiplayerPeer.new()
    peer.create_client(relay_host, relay_port)
    multiplayer.multiplayer_peer = peer
```


### Room Expiry Handling

```gdscript
api.room_expired.connect(_on_room_expired)

func _on_room_expired(room_id: String):
    multiplayer.multiplayer_peer = null
    # Show error message
```



### Signals

```gdscript
rooms_received(rooms: Array) – Response to list_rooms().
room_hosted(room_id, relay_host, relay_port) – Successful host.
room_joined(room_id, relay_host, relay_port) – Successful join.
error_occurred(code, message) – HTTP error.
room_expired(room_id) – Heartbeat failed or room deleted.
```
