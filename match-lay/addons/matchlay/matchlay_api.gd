## HTTP client for MatchLay matchmaker.
class_name MatchLayAPI
extends RefCounted

signal rooms_received(rooms: Array)
signal room_hosted(room_id: String, relay_host: String, relay_port: int)
signal room_joined(room_id: String, relay_host: String, relay_port: int)
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)   # Emitted when heartbeat fails or room is gone

var server_url: String = ""
var api_key: String = ""
var http_request: HTTPRequest = null
var heartbeat_timer: Timer = null
var current_room_id: String = ""

## Must be called before any other methods.
func init(url: String, key: String) -> void:
	server_url = url
	api_key = key
	http_request = HTTPRequest.new()
	Engine.get_main_loop().root.call_deferred("add_child", http_request)
	http_request.name = "MatchLay"
	http_request.timeout = 5
	http_request.request_completed.connect(_on_request_completed)

## Start heartbeats for a given room. Call this after successful host/join.
func start_heartbeat(room_id: String) -> void:
	stop_heartbeat()
	current_room_id = room_id
	heartbeat_timer = Timer.new()
	heartbeat_timer.timeout.connect(_send_heartbeat)
	heartbeat_timer.wait_time = 30.0
	heartbeat_timer.one_shot = false
	heartbeat_timer.name = "heartbeat_timer"
	# Add and start both deferred
	var root = Engine.get_main_loop().root
	root.call_deferred("add_child", heartbeat_timer)
	# Use call_deferred to start after addition
	heartbeat_timer.call_deferred("start")

## Stop heartbeats (e.g., when room is intentionally closed).
func stop_heartbeat() -> void:
	if heartbeat_timer and heartbeat_timer.is_inside_tree():
		heartbeat_timer.queue_free()
	heartbeat_timer = null
	current_room_id = ""

func _send_heartbeat() -> void:
	if current_room_id.is_empty():
		stop_heartbeat()
		return
	var body = JSON.stringify({"room_id": current_room_id})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	var url = server_url + "/heartbeat"
	# Use a separate request to avoid interfering with other API calls
	var req = HTTPRequest.new()
	Engine.get_main_loop().root.call_deferred("add_child", req)
	req.request_completed.connect(_on_heartbeat_response.bind(req))
	req.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_heartbeat_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest):
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		# Network failure
		room_expired.emit(current_room_id)
		stop_heartbeat()
		return
	if response_code == 404 or response_code == 410:
		# Room not found or expired
		room_expired.emit(current_room_id)
		stop_heartbeat()
		return
	elif response_code != 200:
		# Other HTTP error – maybe log it but keep heartbeating
		print("Heartbeat HTTP error: ", response_code)

# ----- Original API methods (unchanged except for adding heartbeat start) -----
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

func send_heartbeat(room_id: String) -> void:
	# Legacy method – you can keep it, but it's not needed if you use start_heartbeat
	var body = JSON.stringify({"room_id": room_id})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/heartbeat", headers, HTTPClient.METHOD_POST, body)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_str = body.get_string_from_utf8()
	var json = JSON.parse_string(body_str)
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP request failed")
		return
	if response_code != 200:
		var err_msg = json.get("detail", "Unknown error") if json else "HTTP " + str(response_code)
		error_occurred.emit(response_code, err_msg)
		# If the request was for host/join and it fails, also emit room_expired with empty ID?
		# Not needed – the caller will handle error_occurred.
		return
	if json.has("rooms"):
		rooms_received.emit(json.rooms)
	elif json.has("room_id") and json.has("relay_host") and json.has("relay_port"):
		# Successfully hosted or joined – start heartbeat automatically
		room_hosted.emit(json.room_id, json.relay_host, json.relay_port)
		room_joined.emit(json.room_id, json.relay_host, json.relay_port)
		start_heartbeat(json.room_id)   # <-- automatically start heartbeats
