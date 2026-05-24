extends Node

#const MatchLayAPI = preload("res://scripts/matchlay_api.gd")

var api: MatchLayAPI
var current_room_id: String = ""
var is_host: bool = false
var room_to_join_id: String = ""
var room_to_join_private_data: Dictionary = {"password": "123"}
var noray_client: Node  # This will hold the NorayClient node

func _ready():
	# --- Create the NorayClient node ---
	noray_client = load("res://addons/netfox.noray/noray.gd").new()
	add_child(noray_client)
	
	# --- Connect NorayClient signals ---
	noray_client.connect("on_oid", _on_noray_oid)
	noray_client.connect("on_pid", _on_noray_pid)
	noray_client.connect("on_connect_nat", _on_noray_connect_nat)
	noray_client.connect("on_connect_relay", _on_noray_connect_relay)
	noray_client.connect("on_connect_to_host", _on_noray_connect_to_host)
	noray_client.connect("on_disconnect_from_host", _on_noray_disconnect_from_host)
	noray_client.connect("on_command", _on_noray_command)

	# --- Initialize matchmaking API ---
	api = MatchLayAPI.new()
	api.init("http://192.168.0.111:8000", "cat")
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.rooms_received.connect(_on_rooms_received)
	api.error_occurred.connect(_on_api_error)
	api.room_expired.connect(_on_room_expired)

# ------------------------------------------------------------------
# Matchmaking button callbacks (unchanged)
# ------------------------------------------------------------------
func _on_host_button_down():
	api.host_game({"map": "arena", "max_players": 4}, {"password": "123"})

func _on_get_rooms_button_down():
	api.list_rooms()

func _on_join_button_down():
	if room_to_join_id.is_empty():
		print("No room selected. Get rooms first.")
		return
	api.join_game(room_to_join_id, room_to_join_private_data)

func _on_close_button_down():
	_cleanup_room()

func _on_firerpc_button_down():
	if is_host:
		fire_rpc.rpc("Hello from host")
	else:
		fire_rpc.rpc_id(1, "Hello from client")

# ------------------------------------------------------------------
# Matchmaking API callbacks (updated signal names)
# ------------------------------------------------------------------
func _on_room_hosted(room_id: String, noray_host: String, noray_port: int):
	current_room_id = room_id
	is_host = true
	print("Room hosted: ", room_id)
	# Connect to noray server
	noray_client.connect_to_host(noray_host, noray_port)
	# Register as host with the room ID
	noray_client.register_host()
	noray_client.call_deferred("register_remote", 8809, 5.0, 0.5)

func _on_room_joined(room_id: String, noray_host: String, noray_port: int):
	current_room_id = room_id
	is_host = false
	print("Joined room: ", room_id)
	# Connect to noray server
	noray_client.connect_to_host(noray_host, noray_port)
	# We'll connect to the host using its OID (OpenID) later
	# The OpenID is the same as the room_id
	noray_client.connect_nat(room_id)

func _on_rooms_received(rooms: Array):
	for room in rooms:
		var room_id = room["room_id"]
		var public_data = room["public_data"]
		var player_count = room["player_count"]
		var created_seconds_ago = room["created_seconds_ago"]
		print("Room %s: %s players, data: %s, created %s seconds ago" % [room_id, player_count, public_data, created_seconds_ago])
	if rooms.size() > 0:
		room_to_join_id = rooms[0]["room_id"]

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " - ", msg)

func _on_room_expired(room_id: String):
	print("Room expired or server unreachable: ", room_id)
	if room_id == current_room_id:
		_cleanup_room()

# ------------------------------------------------------------------
# NorayClient signal handlers
# ------------------------------------------------------------------
func _on_noray_oid(oid: String):
	print("OpenID received: ", oid)
	if is_host:
		# The host's OpenID is the same as the room_id
		pass

func _on_noray_pid(pid: String):
	print("PrivateID received: ", pid)


func _on_noray_connect_nat(address: String, port: int):
	print("NAT connection established")
	_set_multiplayer_peer()
	api.report_player_joined(current_room_id)

func _on_noray_connect_relay(address: String, port: int):
	print("Relay connection established")
	_set_multiplayer_peer()
	api.report_player_joined(current_room_id)

func _set_multiplayer_peer():
	# The noray client has a peer property (ENetMultiplayerPeer)
	if noray_client.has_method("get_peer"):
		multiplayer.multiplayer_peer = noray_client.get_peer()
	else:
		# fallback: assume noray_client.peer exists
		multiplayer.multiplayer_peer = noray_client.peer



func _on_noray_connect_to_host():
	print("Connected to noray server")
	if is_host:
		# After connecting, register the host's local port
		noray_client.register_remote(8809, 5.0, 0.5)

func _on_noray_disconnect_from_host():
	print("Disconnected from noray server")
	_cleanup_room()

func _on_noray_command(command: String, data: String):
	print("Noray command: ", command, " ", data)

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------
var _is_cleaning_up: bool = false

func _cleanup_room():
	if _is_cleaning_up:
		return
	_is_cleaning_up = true

	if noray_client:
		noray_client.disconnect_from_host()
	if api:
		if is_host:
			api.close_room()
		else:
			api.leave_room()

	current_room_id = ""
	is_host = false
	_is_cleaning_up = false

func _exit_tree():
	_cleanup_room()

# ------------------------------------------------------------------
# RPCs
# ------------------------------------------------------------------
@rpc("any_peer", "reliable")
func fire_rpc(msg: String):
	print(msg)
