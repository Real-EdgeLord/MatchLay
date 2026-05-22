extends Node

const RelayPeer = preload("res://addons/matchlay/relay_peer.gd")
#const MatchLayAPI = preload("res://addons/matchlay/matchlay_api.gd")

var api: MatchLayAPI
var relay_peer: RelayPeer

func _ready():
	api = MatchLayAPI.new()
	# Connect signals BEFORE calling init
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.error_occurred.connect(_on_api_error)
	# Initialize with server URL (port 8000) and your secret key
	api.init("http://192.168.0.111:8000", "cat")
	# Wait a frame for HTTPRequest to be added, then host a game
	await get_tree().process_frame
	api.host_game({"map": "arena"}, {"password": "secret"})

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	print("Room hosted: ", room_id, " at ", relay_host, ":", relay_port)
	relay_peer = RelayPeer.new()
	var err = relay_peer.connect_to_relay(relay_host, relay_port, room_id)
	if err == OK:
		multiplayer.multiplayer_peer = relay_peer
		print("Relay peer active – you can now use @rpc")
	else:
		print("Failed to connect to relay: ", err)

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
	print("Joined room: ", room_id)
	relay_peer = relay_peer.new()
	var err = relay_peer.connect_to_relay(relay_host, relay_port, room_id)
	if err == OK:
		multiplayer.multiplayer_peer = relay_peer

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " – ", msg)
