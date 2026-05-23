extends Node


var api: MatchLayAPI
var peer: ENetMultiplayerPeer
var current_room_id: String = ""

func _ready():
	api = MatchLayAPI.new()
	api.init("http://192.168.0.111:8000", "cat")
	
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.error_occurred.connect(_on_api_error)
	api.room_expired.connect(_on_room_expired)   # <-- connect to expiry signal
	
	await get_tree().process_frame
	api.host_game({"map": "arena", "max_players": 4}, {"password": "123"})

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	current_room_id = room_id
	print("Room hosted: ", room_id, " at ", relay_host, ":", relay_port)
	peer = ENetMultiplayerPeer.new()
	peer.create_server(relay_port)
	multiplayer.multiplayer_peer = peer
	# Heartbeat automatically started by matchlay_api

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
	current_room_id = room_id
	print("Joined room: ", room_id)
	peer = ENetMultiplayerPeer.new()
	peer.create_client(relay_host, relay_port)
	multiplayer.multiplayer_peer = peer
	# Heartbeat automatically started

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " - ", msg)
	# If this happens while hosting/joining, we should clean up
	_cleanup_room()

func _on_room_expired(room_id: String):
	print("Room expired or server unreachable: ", room_id)
	# Only react if it's the current room
	if room_id == current_room_id:
		_cleanup_room()
		# Show a UI message: "Connection lost: match closed"

func _cleanup_room():
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
	if api:
		api.stop_heartbeat()
	current_room_id = ""

# Optional: clean up when the node exits
func _exit_tree():
	_cleanup_room()
