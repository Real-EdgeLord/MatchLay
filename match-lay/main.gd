extends Node

const MatchLayAPI = preload("res://scripts/matchlay_api.gd")
const NorayClient = preload("res://addons/netfox.noray/client.gd")  # adjust path

var api: MatchLayAPI
var peer: ENetMultiplayerPeer  # still used for actual gameplay? No – NorayClient handles the peer.

func _ready():
	api = MatchLayAPI.new()
	api.init("http://192.168.0.111:8000", "cat")
	api.room_hosted.connect(_on_room_hosted)
	api.room_joined.connect(_on_room_joined)
	api.error_occurred.connect(_on_api_error)
	# For testing, automatically host after a frame
	await get_tree().process_frame
	api.host_game({"map": "arena"}, {"password": "123"})

func _on_room_hosted(room_id: String, noray_host: String, noray_port: int):
	print("Room hosted with ID: ", room_id)
	# Use noray client to host
	NorayClient.host_game(room_id)  # open_id = room_id
	NorayClient.on_host_game.connect(_on_noray_host_success)
	NorayClient.on_connection_lost.connect(_on_noray_disconnect)

func _on_noray_host_success(open_id: String, private_data: Variant):
	print("Noray hosting succeeded, OpenID: ", open_id)
	# Now the game can start – the MultiplayerPeer is automatically set by netfox.noray
	# You can now use multiplayer.rpc, etc.

func _on_room_joined(room_id: String, noray_host: String, noray_port: int):
	print("Joining room: ", room_id)
	NorayClient.join_game(room_id)
	NorayClient.on_join_game_success.connect(_on_noray_join_success)
	NorayClient.on_connection_lost.connect(_on_noray_disconnect)

func _on_noray_join_success(open_id: String):
	print("Noray join succeeded, OpenID: ", open_id)

func _on_noray_disconnect():
	print("Disconnected from noray")
	# Clean up, possibly call api.leave_room()

func _on_api_error(code: int, msg: String):
	print("API error: ", code, " - ", msg)


#func _on_host_button_down() -> void:
	#api.host_game({"map": "arena", "max_players": 4}, {"password": "123"})
#
#
#func _on_close_button_down() -> void:
	#_cleanup_room()
#
#
#func _on_join_button_down() -> void:
	#await get_tree().create_timer(1).timeout
	#var test_peer = ENetMultiplayerPeer.new()
	#var err = test_peer.create_client("192.168.0.111", 5559)
	#print("Test ENet client create_client returned: ", err)
	#await get_tree().create_timer(2).timeout
	#print("Test ENet connection status: ", test_peer.get_connection_status())
	#
	#
	##api.join_game(room_to_join_id,room_to_join_Dick)
#
#var room_to_join_id : String = ""
#var room_to_join_Dick : Dictionary = {"password": "123"}
#
#
#func _on_get_rooms_button_down() -> void:
	#api.list_rooms()
#
#
#
#func _on_rooms_recevied(rooms: Array):
	#for room in rooms:
		#var room_id = room["room_id"]
		#var public_data = room["public_data"]
		#var player_count = room["player_count"]
		#var created_seconds_ago = room["created_seconds_ago"]
		#print("Room %s: %s players, data: %s, and created %s seconds ago" % [room_id, player_count, public_data, created_seconds_ago])
		## Example: store first room ID for joining
		#if rooms.size() > 0:
			#room_to_join_id = rooms[0]["room_id"]
			##room_to_join_Dick = rooms[0].get("public_data", {})  # private data not exposed
#
#
#
#func _on_firerpc_button_down() -> void:
	#if is_host:
		#fire_rpc.rpc("Hello from host")
	#else:
		#fire_rpc.rpc_id(1, "Hello from client")
#
#
#@rpc("any_peer","reliable")
#func fire_rpc(test_from : String) -> void :
	#print(test_from)
