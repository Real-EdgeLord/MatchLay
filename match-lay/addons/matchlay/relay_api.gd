## RelayMultiplayerAPI - Custom MultiplayerAPI using UDP relay.
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
	return OK

# Must be called every frame from your game script
func poll() -> Error:
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		_packet_queue.append(packet)
	
	while _packet_queue.size() > 0:
		var pkt = _packet_queue.pop_front()
		# Decode and route RPC calls here
		# For now, just print
		print("UDP packet received: ", pkt.hex_encode())
	return OK

func _rpc(peer_id: int, object: Object, method: StringName, args: Array) -> Error:
	# Serialize and send via UDP
	var packet = method.to_utf8_buffer()
	for arg in args:
		packet += var_to_bytes(arg)
	return _udp.put_packet(packet)

func _get_peer_ids() -> PackedInt32Array:
	return PackedInt32Array()

func _get_peers() -> int:
	return 0

func _get_unique_id() -> int:
	return _unique_id

func _cleanup():
	_udp.close()
