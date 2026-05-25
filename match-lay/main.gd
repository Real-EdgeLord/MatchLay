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
var noray_connected = false
var handshake = null
var my_room_id = ""
var my_room_secret = ""
var is_host = false
var player_count := 0
var matchmaker : MatchLayAPI = null

var host_oid: String 

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(_on_JoinButton_pressed)
	refresh_button.pressed.connect(_on_RefreshButton_pressed)
	sendrpc.pressed.connect(_on_fire_rpc)
	# Connect to the Noray server
	var err = await Noray.connect_to_host("192.168.0.111", 8890)
	if err != OK:
		print("Failed to connect to Noray server")
		return
	print("Connected to Noray server")

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
	
	# 4. Now Noray.local_port is valid — use it to start the server
	print("Registered local port: ", Noray.local_port)
	var peer = ENetMultiplayerPeer.new()
	err = peer.create_server(Noray.local_port)
	if err != OK:
		print("Failed to create server on port ", Noray.local_port, ": ", error_string(err))
		return
	
	multiplayer.multiplayer_peer = peer
	print("Server listening on port ", Noray.local_port)
	print("Share this Open ID with your friend: ", Noray.oid)
	status_label.text = Noray.oid

func _on_JoinButton_pressed():
	# Step 1: Register as host
	Noray.register_host()
	await Noray.on_pid          # Wait for Private ID
	print("Got PID: ", Noray.pid)

	# Step 2: Register local port with Noray server (critical!)
	var err = await Noray.register_remote()
	if err != OK:
		print("Failed to register remote address: ", error_string(err))
		return
	print("Registered remote address. Local port: ", Noray.local_port)
	# Connect using NAT punchthrough
	Noray.connect_nat(host_oid)

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
	host_oid = line.text


func _on_fire_rpc() -> void :
	the_rpc_called.rpc(str(multiplayer.get_unique_id()))


@rpc("any_peer","reliable")
func the_rpc_called (mes : String) -> void :
	
	print(mes)
