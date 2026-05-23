extends Node


var api: MatchLayAPI
var peer: ENetMultiplayerPeer
var current_room_id: String = ""
var is_host: bool = false

func _ready():
	api = MatchLayAPI.new()
	api.init("http://192.168.0.111:8000", "cat")
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.rooms_received.connect(_on_rooms_recevied)
	api.error_occurred.connect(_on_api_error)
	api.room_expired.connect(_on_room_expired)
	await get_tree().process_frame
	# Automatically host for testing
	#api.host_game({"map": "arena"}, {"password": "123"})
	



func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	current_room_id = room_id
	is_host = true
	print("Room hosted: ", room_id, " at ", relay_host, ":", relay_port)
	_connect_to_relay(relay_host, relay_port)

func _on_room_joined(room_id: String, relay_host: String, relay_port: int):
	current_room_id = room_id
	is_host = false
	print("Joined room: ", room_id)
	_connect_to_relay(relay_host, relay_port)


func _connect_to_relay(host: String, port: int):
	peer = ENetMultiplayerPeer.new()
	peer.connected_to_server.connect(_on_connected_to_server)
	peer.connection_failed.connect(_on_connection_failed)
	var err = peer.create_client(host, port)
	if err != OK:
		print("Failed to create client: ", err)

func _on_connected_to_server():
	print("Connected to relay!")
	multiplayer.multiplayer_peer = peer
	if is_host:
		# Send an RPC to identify as host after a short delay
		await get_tree().create_timer(0.2).timeout
		rpc_id(1, "_set_host", multiplayer.get_unique_id())

func _on_connection_failed():
	print("Connection to relay failed")
	_cleanup_room()


@rpc("any_peer", "reliable")
func _set_host(host_id: int):
	# This RPC will be called on all clients. The host's ID is recorded.
	# You can store host_id in a global variable.
	print("Host is peer ", host_id)


var _is_cleaning_up: bool = false

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " - ", msg)
	if _is_cleaning_up:
		return
	_is_cleaning_up = true
	_cleanup_room()
	_is_cleaning_up = false

func _on_room_expired(room_id: String):
	print("Room expired or server unreachable: ", room_id)
	# Only react if it's the current room
	if room_id == current_room_id:
		_cleanup_room()
		# Show a UI message: "Connection lost: match closed"

func _cleanup_room():
	if _is_cleaning_up: return
	_is_cleaning_up = true
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null
	if api:
		if is_host:
			api.close_room()    # Deletes room on server
		else:
			api.leave_room()    # Just stops heartbeat locally
	current_room_id = ""
	is_host = false
	_is_cleaning_up = false



# Optional: clean up when the node exits
func _exit_tree():
	_cleanup_room()


@rpc("any_peer", "unreliable")
func _ping():
	print("Ping received from ", multiplayer.get_remote_sender_id())


func _on_host_button_down() -> void:
	api.host_game({"map": "arena", "max_players": 4}, {"password": "123"})


func _on_close_button_down() -> void:
	_cleanup_room()


func _on_join_button_down() -> void:
	api.join_game(room_to_join_id,room_to_join_Dick)

var room_to_join_id : String = ""
var room_to_join_Dick : Dictionary = {"password": "123"}


func _on_get_rooms_button_down() -> void:
	api.list_rooms()



func _on_rooms_recevied(rooms: Array):
	for room in rooms:
		var room_id = room["room_id"]
		var public_data = room["public_data"]
		var player_count = room["player_count"]
		var created_seconds_ago = room["created_seconds_ago"]
		print("Room %s: %s players, data: %s, and created %s seconds ago" % [room_id, player_count, public_data, created_seconds_ago])
		# Example: store first room ID for joining
		if rooms.size() > 0:
			room_to_join_id = rooms[0]["room_id"]
			#room_to_join_Dick = rooms[0].get("public_data", {})  # private data not exposed



func _on_firerpc_button_down() -> void:
	if is_host:
		fire_rpc.rpc("Hello from host")
	else:
		fire_rpc.rpc_id(1, "Hello from client")


@rpc("any_peer","reliable")
func fire_rpc(test_from : String) -> void :
	print(test_from)
