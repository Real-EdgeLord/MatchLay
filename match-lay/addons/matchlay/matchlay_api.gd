# matchlay_api.gd
extends Node
class_name MatchLayAPI

signal rooms_received(rooms: Array)
signal room_hosted(room_id: String, noray_host: String, noray_port: int)
signal room_joined(room_id: String, noray_host: String, noray_port: int)
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)

var server_url: String = ""
var api_key: String = ""
var http_request: HTTPRequest = null
var current_room_id: String = ""
var _is_host: bool = false
var _host_token: String = ""

func init(url: String, key: String) -> void:
	server_url = url
	api_key = key
	http_request = HTTPRequest.new()
	Engine.get_main_loop().root.call_deferred("add_child", http_request)
	http_request.timeout = 5
	http_request.request_completed.connect(_on_request_completed)

func host_game(public_data: Dictionary, private_data: Dictionary = {}) -> void:
	var body = JSON.stringify({"public_data": public_data, "private_data": private_data})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/host", headers, HTTPClient.METHOD_POST, body)

func join_game(room_id: String, private_data: Dictionary = {}) -> void:
	var body = JSON.stringify({"private_data": private_data})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/join/" + room_id, headers, HTTPClient.METHOD_POST, body)

func list_rooms() -> void:
	var headers = ["X-API-Key: " + api_key]
	http_request.request(server_url + "/rooms", headers, HTTPClient.METHOD_GET)

func close_room() -> void:
	if not _is_host or _host_token.is_empty():
		error_occurred.emit(403, "Not hosting a room")
		return
	var headers = ["X-API-Key: " + api_key]
	var url = server_url + "/room/%s?host_token=%s" % [current_room_id, _host_token]
	var req = HTTPRequest.new()
	Engine.get_main_loop().root.call_deferred("add_child", req)
	req.request_completed.connect(_on_close_completed.bind(req))
	req.request(url, headers, HTTPClient.METHOD_DELETE)

func _on_close_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest):
	req.queue_free()
	if response_code == 200:
		current_room_id = ""
		_is_host = false
		_host_token = ""

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP request failed")
		return
	if response_code != 200:
		error_occurred.emit(response_code, json.get("detail", "Unknown error") if json else "HTTP error")
		return
	if json.has("rooms"):
		rooms_received.emit(json.rooms)
	elif json.has("room_id") and json.has("noray_host") and json.has("noray_port"):
		if json.has("host_token"):  # host response
			_is_host = true
			_host_token = json.host_token
			room_hosted.emit(json.room_id, json.noray_host, json.noray_port)
		else:  # join response
			_is_host = false
			_host_token = ""
			room_joined.emit(json.room_id, json.noray_host, json.noray_port)
		current_room_id = json.room_id
		# Start heartbeat automatically
		start_heartbeat(json.room_id)

func start_heartbeat(room_id: String) -> void:
	# Implement a timer that calls /heartbeat every 30 seconds
	pass  # (you can add later)

func stop_heartbeat() -> void:
	pass
	

func report_player_joined(room_id: String) -> void:
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	var body = JSON.stringify({"room_id": room_id})
	http_request.request(server_url + "/player_joined", headers, HTTPClient.METHOD_POST, body)

func report_player_left(room_id: String) -> void:
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	var body = JSON.stringify({"room_id": room_id})
	http_request.request(server_url + "/player_left", headers, HTTPClient.METHOD_POST, body)


func leave_room() -> void:
	# For joiners, just stop heartbeat and clean up locally
	stop_heartbeat()
	current_room_id = ""
	_is_host = false
	_host_token = ""
