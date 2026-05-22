## RelayMultiplayerAPI – A custom MultiplayerAPI that uses a UDP relay.
@tool
extends MultiplayerAPIExtension
class_name RelayMultiplayerAPI

var _relay_host: String = ""
var _relay_port: int = 0
var _room_id: String = ""
var _unique_id: int = 0

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _handshake_sent: bool = false
var _packet_queue: Array[PackedByteArray] = []
var _polling_timer: Timer = null

func setup(relay_host: String, relay_port: int, room_id: String, unique_id: int = 0) -> Error:
	_relay_host = relay_host
	_relay_port = relay_port
	_room_id = room_id
	_unique_id = unique_id if unique_id != 0 else randi()
	_handshake_sent = false
	_packet_queue.clear()
	
	var err = _udp.set_dest_address(_relay_host, _relay_port)
	if err != OK:
		return err
	
	var handshake: PackedByteArray = _room_id.to_utf8_buffer() + PackedByteArray([0])
	err = _udp.put_packet(handshake)
	if err != OK:
		return err
	
	_handshake_sent = true
	
	_polling_timer = Timer.new()
	_polling_timer.timeout.connect(_poll)
	_polling_timer.start(0.01)
	Engine.get_main_loop().root.add_child(_polling_timer)
	
	# Do NOT set multiplayer.multiplayer_api here – let the game script do it.
	return OK

# Fixed: now returns Error, not void
func _poll() -> Error:
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		_packet_queue.append(packet)
	
	# Process queued packets (simplified – you'll need proper decoding)
	while _packet_queue.size() > 0:
		var pkt = _packet_queue.pop_front()
		print("Received packet: ", pkt.hex_encode())
		# In production: decode and call rpc_id on the appropriate object
	return OK

func _send_packet(data: PackedByteArray, to_peer: int = 0) -> Error:
	if not _handshake_sent:
		return ERR_UNCONFIGURED
	return _udp.put_packet(data)

func _rpc(peer_id: int, object: Object, method: StringName, args: Array) -> Error:
	var packet = method.to_utf8_buffer()
	for arg in args:
		packet += var_to_bytes(arg)
	return _send_packet(packet, peer_id)

func _get_peer_ids() -> PackedInt32Array:
	return PackedInt32Array()  # You'll need to implement peer tracking

func _get_peers() -> int:
	return 0

func _get_unique_id() -> int:
	return _unique_id

func _cleanup():
	if _polling_timer:
		_polling_timer.queue_free()
	_udp.close()
