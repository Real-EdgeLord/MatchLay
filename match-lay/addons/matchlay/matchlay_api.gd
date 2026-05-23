## MatchLay API client – HTTP matchmaking + UDP relay helper.
class_name MatchLayAPI
extends RefCounted

signal rooms_received(rooms: Array)
signal room_hosted(room_id: String, relay_host: String, relay_port: int, host_token: String)
signal room_joined(room_id: String, relay_host: String, relay_port: int)
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)

var server_url: String = ""
var api_key: String = ""
var http_request: HTTPRequest = null
var heartbeat_request: HTTPRequest = null  # dedicated for heartbeats
var heartbeat_timer: Timer = null
var current_room_id: String = ""

func init(url: String, key: String) -> void:
	server_url = url
	api_key = key
	# Main HTTP request for host/join/list
	http_request = HTTPRequest.new()
	http_request.name = "MatchLay.Main"
	_safe_add_child(http_request)
	http_request.timeout = 5
	http_request.request_completed.connect(_on_request_completed)
	# Dedicated heartbeat request
	heartbeat_request = HTTPRequest.new()
	heartbeat_request.name = "MatchLay.Heart"
	_safe_add_child(heartbeat_request)
	heartbeat_request.timeout = 5

func _safe_add_child(node: Node) -> void:
	# Use call_deferred to avoid "busy parent" during _ready
	Engine.get_main_loop().root.call_deferred("add_child", node)

func start_heartbeat(room_id: String) -> void:
	stop_heartbeat()
	current_room_id = room_id
	heartbeat_timer = Timer.new()
	heartbeat_timer.name = "HeartBeat"
	heartbeat_timer.wait_time = 30.0
	heartbeat_timer.one_shot = false
	heartbeat_timer.autostart = true
	heartbeat_timer.timeout.connect(_send_heartbeat)
	_safe_add_child(heartbeat_timer)

func stop_heartbeat() -> void:
	if heartbeat_timer and heartbeat_timer.is_inside_tree():
		heartbeat_timer.queue_free()
	heartbeat_timer = null
	current_room_id = ""

func _send_heartbeat() -> void:
	if current_room_id.is_empty():
		stop_heartbeat()
		return
	if not heartbeat_request or not heartbeat_request.is_inside_tree():
		# Recreate if needed (should not happen)
		heartbeat_request = HTTPRequest.new()
		_safe_add_child(heartbeat_request)
		heartbeat_request.timeout = 5
	var body = JSON.stringify({"room_id": current_room_id})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	var url = server_url + "/heartbeat"
	# Clear previous connections (optional)
	if heartbeat_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		return  # already busy, skip this heartbeat
	heartbeat_request.request(url, headers, HTTPClient.METHOD_POST, body)
	# Connect signal only once
	if not heartbeat_request.request_completed.is_connected(_on_heartbeat_response):
		heartbeat_request.request_completed.connect(_on_heartbeat_response.bind(heartbeat_request))

func _on_heartbeat_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest):
	if result != HTTPRequest.RESULT_SUCCESS:
		room_expired.emit(current_room_id)
		stop_heartbeat()
		return
	if response_code == 404 or response_code == 410:
		room_expired.emit(current_room_id)
		stop_heartbeat()
		return

# ----- Public API -----
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

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_str = body.get_string_from_utf8()
	var json = JSON.parse_string(body_str)
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP request failed")
		return
	if response_code != 200:
		var err_msg = json.get("detail", "Unknown error") if json else "HTTP " + str(response_code)
		error_occurred.emit(response_code, err_msg)
		return
	if json.has("rooms"):
		rooms_received.emit(json.rooms)
	elif json.has("room_id") and json.has("relay_host") and json.has("relay_port"):
		room_hosted.emit(json.room_id, json.relay_host, json.relay_port, json.get("host_token", ""))
		room_joined.emit(json.room_id, json.relay_host, json.relay_port)
		start_heartbeat(json.room_id)



func close_room(room_id: String, host_token: String) -> void:
	var headers = ["X-API-Key: " + api_key]
	var url = server_url + "/room/%s?host_token=%s" % [room_id, host_token]
	http_request.request(url, headers, HTTPClient.METHOD_DELETE)
