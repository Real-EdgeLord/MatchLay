## RelayPeer - A custom MultiplayerPeer that connects to a UDP relay.
## This peer acts as a client, connecting to a central UDP relay server.
## It sends a handshake containing the room_id and then forwards raw game packets.
@tool
extends MultiplayerPeer
class_name RelayPeer

# ----- Reference Variables (Configured externally) -----
var _relay_host: String = ""
var _relay_port: int = 0
var _room_id: String = ""
var _handshake_sent: bool = false

# ----- Internal State -----
var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _connection_status: ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _packet_queue: Array[PackedByteArray] = []
var _unique_id: int = 0

## Connects this peer to the relay server.
## Must be called before setting this as the multiplayer peer.
func connect_to_relay(relay_host: String, relay_port: int, room_id: String, unique_id: int = 0) -> Error:
	_relay_host = relay_host
	_relay_port = relay_port
	_room_id = room_id
	_unique_id = unique_id if unique_id != 0 else randi()
	_handshake_sent = false
	_packet_queue.clear()
	
	_connection_status = MultiplayerPeer.CONNECTION_CONNECTING
	
	var err = _udp.connect_to_host(_relay_host, _relay_port)
	if err == OK:
		_connection_status = MultiplayerPeer.CONNECTION_CONNECTED
	else:
		_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	
	return err

## Returns the unique ID of this peer.
func _get_unique_id() -> int:
	return _unique_id

## Returns the current connection status.
func _get_connection_status() -> ConnectionStatus:
	return _connection_status

## Polls the UDP socket for incoming packets and queues them.
## This is called automatically by the engine each frame.
func _poll():
	if _connection_status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
		
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		_packet_queue.append(packet)

## Gets the next available packet from the queue.
func _get_packet() -> PackedByteArray:
	if _packet_queue.is_empty():
		return PackedByteArray()
	return _packet_queue.pop_front()

## Returns the number of packets waiting to be retrieved.
func _get_available_packet_count() -> int:
	return _packet_queue.size()

## Sends a packet to the relay.
func _put_packet(p_buffer: PackedByteArray) -> Error:
	if _connection_status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_CONNECTION_ERROR
	
	if not _handshake_sent:
		# Prepend the room_id followed by a null byte as the handshake.
		var handshake: PackedByteArray = _room_id.to_utf8_buffer() + PackedByteArray([0])
		var combined: PackedByteArray = handshake + p_buffer
		var err = _udp.put_packet(combined)
		if err == OK:
			_handshake_sent = true
		return err
	else:
		return _udp.put_packet(p_buffer)

## Required override: What packet mode is used? We are unreliable by nature (UDP).
func _get_packet_mode() -> TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE

## Required override: What channel is the next packet for?
func _get_packet_channel() -> int:
	return 0

## Required override: The ID of the peer that sent the next packet.
func _get_packet_peer() -> int:
	return _unique_id

## Required override: The maximum packet size allowed.
func _get_max_packet_size() -> int:
	return 65535

## Required override: Disconnect the peer cleanly.
func _disconnect_peer(peer_id: int = 0, force: bool = false):
	if peer_id == _unique_id or force:
		_udp.close()
		_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED

## Required override: Immediately close the peer.
func _close():
	_udp.close()
	_connection_status = MultiplayerPeer.CONNECTION_DISCONNECTED

## Required override: Is this peer acting as a server? No, this is a client peer.
func _is_server() -> bool:
	return false

## Required override: The transfer channel for the next packet.
func _get_transfer_channel() -> int:
	return 0

## Required override: Set the target peer for subsequent put_packet calls. Not used in client.
func _set_target_peer(p_peer: int):
	pass

## Required override: Set the transfer channel for subsequent put_packet calls.
func _set_transfer_channel(p_channel: int):
	pass

## Required override: Set the transfer mode for subsequent put_packet calls.
func _set_transfer_mode(p_mode: TransferMode):
	pass
