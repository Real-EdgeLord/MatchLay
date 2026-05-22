extends Node

const MatchLayAPI = preload("res://addons/matchlay/matchlay_api.gd")

var api: MatchLayAPI
var peer: ENetMultiplayerPeer

func _ready():
	# Initialize API with your server (replace with actual IP/domain and key)
	api = MatchLayAPI.new()
	api.init("http://192.168.0.111:8000", "cat")
	
	# Connect signals
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.error_occurred.connect(_on_api_error)
	
	# Example: host a game after one frame
	await get_tree().process_frame
	api.host_game({"map": "arena", "max_players": 4}, {"password": "123"})

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	print("Room hosted: ", room_id, " at ", relay_host, ":", relay_port)
	# Create ENet peer as server (host)
	peer = ENetMultiplayerPeer.new()
	peer.create_server(relay_port)          # Bind to the relay's port
	multiplayer.multiplayer_peer = peer
	print("ENet server started, waiting for clients...")

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
	print("Joined room: ", room_id, " at ", relay_host, ":", relay_port)
	# Create ENet peer as client
	peer = ENetMultiplayerPeer.new()
	peer.create_client(relay_host, relay_port)
	multiplayer.multiplayer_peer = peer
	print("ENet client connected to relay")

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " - ", msg)
