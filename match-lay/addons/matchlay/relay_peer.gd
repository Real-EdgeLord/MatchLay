extends MultiplayerPeer


var _relay_host: String = ""
var _relay_port: int = 0
var _room_id: String = ""
var _handshake_sent: bool = false
var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _connection_status: ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _packet_queue: Array[PackedByteArray] = []
var _unique_id: int = 0

func connect_to_relay(host: String, port: int, room_id: String, unique_id: int = 0) -> Error:
	_relay_host = host
	_relay_port = port
	_room_id = room_id
	_unique_id = unique_id if unique_id != 0 else randi()
	_handshake_sent = false
	_packet_queue.clear()
	
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
	var err = _udp.connect_to_host(_relay_host, _relay_port)
	if err != OK:
		_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		return err
	
	# Send handshake (room_id + null byte)
	var handshake = _room_id.to_utf8_buffer() + PackedByteArray([0])
	err = _udp.put_packet(handshake)
	if err == OK:
		_handshake_sent = true
		_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	else:
		_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	return err

func _poll():
	if _connection_status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		_packet_queue.append(packet)

func _get_packet() -> PackedByteArray:
	return _packet_queue.pop_front() if _packet_queue.size() > 0 else PackedByteArray()

func _get_available_packet_count() -> int:
	return _packet_queue.size()

func _put_packet(p_buffer: PackedByteArray) -> Error:
	if _connection_status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_CONNECTION_ERROR
	return _udp.put_packet(p_buffer)

func _get_packet_mode() -> TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE

func _get_packet_channel() -> int:
	return 0

func _get_packet_peer() -> int:
	return _unique_id

func _get_connection_status() -> ConnectionStatus:
	return _connection_status

func _disconnect_peer(peer_id: int = 0, force: bool = false):
	if peer_id == _unique_id or force:
		_udp.close()
		_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED

func _close():
	_udp.close()
	_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED

func _is_server() -> bool:
	return false

func _get_unique_id() -> int:
	return _unique_id

func _get_max_packet_size() -> int:
	return 65535
