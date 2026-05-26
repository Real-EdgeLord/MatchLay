extends Node

# UI references (adjust to your actual scene tree)
@export var host_button : Button
@export var join_button : Button
@export var refresh_button : Button
@export var sendrpc : Button
@export var room_list : ItemList
@export var status_label :Label
@export var line : LineEdit

# State
var noray_connected : bool = false
var my_room_id : String = ""
var my_room_secret : String = ""
var my_room_data : Dictionary
var is_host : bool = false
var player_count : int = 0
var is_private : bool = false
var matchmaker : MatchLayAPI = null

var my_oid : String

var room_oid: String 

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(_on_JoinButton_pressed)
	refresh_button.pressed.connect(_on_RefreshButton_pressed)
	sendrpc.pressed.connect(_on_fire_rpc)
	# Connect to the Noray server
	var err = await Noray.connect_to_host("192.168.0.111", 8890)
	if err != OK:
		noray_connected = false
		print("Failed to connect to Noray server")
		return
	noray_connected = true
	print("Connected to Noray server")
	
	#Connect to Noray
	Noray.on_disconnect_from_host.connect(on_onray_disconnect_from_host)
	
	
	
	# Connect to Matchlay
	matchmaker = MatchLayAPI.new()
	add_child(matchmaker)
	matchmaker.init("192.168.0.111:8000","cat")
	print("finished matchmaker")
	#matchmaker.server_down.connect(_on_server_down)
	#matchmaker.error_occurred.connect(_on_error)
	#matchmaker.room_expired
	#matchmaker.room_closed
	matchmaker.player_count_updated.connect(_on_player_count_updated)
	matchmaker.room_joined.connect(_on_room_joined)
	matchmaker.room_hosted.connect(_on_room_hosted)
	matchmaker.rooms_listed.connect(_on_rooms_listed)
	

# ===== BUTTON ACTIONS =====
func host_game():
	# 1. Register as a host with the noray server
	Noray.register_host()
	
	# 2. Wait for the server to assign you a Private ID
	await Noray.on_pid
	
	# 3. Register your local port with the remote address
	var err = await Noray.register_remote()
	if err != OK:
		print("Failed to register remote address: ", error_string(err))
		return
	my_oid = Noray.oid
	
	# 4. Create the room on match lay
	my_room_data ={
		level = "desert",
		type ="deathmatch"
	}
	matchmaker.host_game(my_oid,0,my_room_data,true)
	await matchmaker.room_hosted
	matchmaker.add_player(my_oid)
	
	# 5. Now Noray.local_port is valid — use it to start the server
	print("Registered local port: ", Noray.local_port)
	var peer = ENetMultiplayerPeer.new()
	err = peer.create_server(Noray.local_port)
	if err != OK:
		print("Failed to create server on port ", Noray.local_port, ": ", error_string(err))
		return
	
	multiplayer.multiplayer_peer = peer
	print("Server listening on port ", Noray.local_port)
	print("Share this Open ID with your friend: ", Noray.oid)
	status_label.text = my_room_secret
	is_host = true

func _on_JoinButton_pressed():
	# Step 1: Join a room by secret code to get server oid
	matchmaker.join_with_secret(line.text)
	await matchmaker.room_joined
	# Step 2: Register as host
	Noray.register_host()
	await Noray.on_pid          # Wait for Private ID
	print("Got PID: ", Noray.pid)

	# Step 3: Register local port with Noray server (critical!)
	var err = await Noray.register_remote()
	if err != OK:
		print("Failed to register remote address: ", error_string(err))
		return
	print("Registered remote address. Local port: ", Noray.local_port)
	# Connect using NAT punchthrough
	
	Noray.connect_nat(room_oid)

	# Wait for the NAT connection signal
	Noray.on_connect_nat.connect(_on_nat_connected)

func _on_nat_connected(address: String, port: int):
	# Create an ENet client and connect to the host's address/port
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		print("Failed to join game")
		return

	multiplayer.multiplayer_peer = peer
	print("Connected to host. My peer ID: ", multiplayer.get_unique_id())

func _on_RefreshButton_pressed():
	matchmaker.list_rooms()


func _on_fire_rpc() -> void :
	the_rpc_called.rpc(str(multiplayer.get_unique_id()))


@rpc("any_peer","reliable")
func the_rpc_called (mes : String) -> void :
	
	print(mes)




# ===== Noray SINGLES  =====



func on_onray_disconnect_from_host() -> void :
	
	pass


# ===== MATCH MAKER SINGLES AND FUCNTIONS =====

func _on_server_down() -> void :
	
	pass


func _on_error() -> void :
	
	pass

func _on_room_expired() -> void :
	
	pass


func _on_room_closed() -> void :
	
	pass


func _on_player_count_updated(_room_id: String, _player_count: int) -> void :
	player_count = _player_count
	pass


func _on_room_joined(room_id: String, server_oid: String, _player_count: int) -> void :
	my_room_id = room_id
	room_oid = server_oid
	player_count = player_count
	pass


func _on_room_hosted(room_id: String, secret: String, _host_key: String,_is_private: bool) -> void :
	my_room_id = room_id
	my_room_secret = secret
	is_private = _is_private
	pass

func _on_rooms_listed(rooms: Array[MatchLayRoomData]) -> void : 
	for room in rooms:
		print("Room %s has %d players, age %d seconds, data: %s, privacy = %s" % [room.room_id, room.player_count, room.age_seconds, room.public_data, room.is_private])
