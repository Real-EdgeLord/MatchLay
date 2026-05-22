# In your main game script
var api: MatchLayAPI
var relay_peer: RelayPeer

func _ready():
	# 1. Create an API client instance (or use the autoload)
	api = MatchLayAPI.new("http://your-server-ip:8000", "your-api-key")
	api.rooms_received.connect(_on_rooms_received)
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.error_occurred.connect(_on_api_error)

func host_game():
	api.host_game({"map": "arena", "max_players": 4}, {"password": "secret"})

func join_game(room_id: String):
	api.join_game(room_id, {"password": "secret"})

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	# 2. Create and connect the custom peer
	relay_peer = RelayPeer.new()
	relay_peer.connect_to_relay(relay_host, relay_port, room_id)
	# 3. Set it as the active multiplayer peer
	multiplayer.multiplayer_peer = relay_peer
	# 4. Now you can use @rpc and the high-level API normally.
	# For example, create a game server:
	# This part depends on your game's logic, but you can use `multiplayer.server_relay` etc.

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
	relay_peer = RelayPeer.new()
	relay_peer.connect_to_relay(relay_host, relay_port, room_id)
	multiplayer.multiplayer_peer = relay_peer
	# Now you can connect to the host via the high-level API.
