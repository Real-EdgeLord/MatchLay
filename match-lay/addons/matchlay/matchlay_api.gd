# matchlay_api.gd – Supports public/private rooms
extends Node
class_name MatchLayAPI

# ----------------------------- Signals ---------------------------------
signal rooms_listed(rooms: Array[MatchLayRoomData])
signal room_hosted(room_id: String, secret: String, host_key: String, is_private: bool)
signal room_joined(room_id: String, server_oid: String, player_count: int)
signal player_count_updated(room_id: String, player_count: int)
signal heartbeat_ok()
signal room_closed()
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)
signal server_down()

# ----------------------------- Configuration -----------------------------
const HEARTBEAT_INTERVAL: float = 10.0
const HTTP_REQUEST_TIMEOUT: int = 15
const HEALTH_CHECK_TIMEOUT: int = 5

# ----------------------------- State ---------------------------------
var server_url: String = ""
var api_key: String = ""

var current_room_id: String = ""
var is_host: bool = false
var host_key: String = ""
var room_secret: String = ""
var _pending_server_oid: String = ""

var _heartbeat_timer: Timer = null
var _heartbeat_in_flight: bool = false
var _initialized: bool = false

var _health_http: HTTPRequest = null   # only for health checks

var _pending_actions: Array[Callable] = []
var _health_check_in_progress: bool = false

# ----------------------------- Public API -----------------------------
func init(url: String, key: String) -> void:
	var full_url = url.strip_edges()
	if not full_url.begins_with("http://") and not full_url.begins_with("https://"):
		full_url = "http://" + full_url
	server_url = full_url.rstrip("/")
	api_key = key
	
	_health_http = HTTPRequest.new()
	_health_http.name = "health_http"
	add_child(_health_http)
	_health_http.timeout = HEALTH_CHECK_TIMEOUT
	_initialized = true
	print("MatchLayAPI ready at ", server_url)

func host_game(server_oid: String, public_data: Dictionary = {}, is_private: bool = true) -> void:
	_pending_server_oid = server_oid
	_check_health_and_run(_internal_host_game.bind(server_oid, public_data, is_private))

func join_with_secret(secret: String) -> void:
	_check_health_and_run(_internal_join_with_secret.bind(secret))

func join_with_room_id(room_id: String) -> void:
	_check_health_and_run(_internal_join_with_room_id.bind(room_id))

func list_rooms() -> void:
	_check_health_and_run(_internal_list_rooms)

func add_player(player_oid: String) -> void:
	_check_health_and_run(_internal_add_player.bind(player_oid))

func remove_player(player_oid: String) -> void:
	_check_health_and_run(_internal_remove_player.bind(player_oid))

func close_room() -> void:
	_check_health_and_run(_internal_close_room)

func leave_room() -> void:
	_stop_heartbeat()
	_cleanup_state()

# ----------------------------- Internal actions -----------------------------
func _send_request(url: String, headers: PackedStringArray, method: int, body: String = "") -> void:
	var req = HTTPRequest.new()
	req.name = "http_request"
	add_child(req)
	req.timeout = HTTP_REQUEST_TIMEOUT
	req.request_completed.connect(_on_request_completed.bind(req, url, method), CONNECT_ONE_SHOT)
	req.request(url, headers, method, body)

func _internal_host_game(server_oid: String, public_data: Dictionary, is_private: bool) -> void:
	var body = {
		"server_oid": server_oid,
		"match_time": 0,
		"public_data": public_data,
		"is_private": is_private
	}
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	_send_request(server_url + "/host", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _internal_join_with_secret(secret: String) -> void:
	var body = {"secret": secret}
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	_send_request(server_url + "/join", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _internal_join_with_room_id(room_id: String) -> void:
	var headers = ["X-API-Key: " + api_key]
	_send_request(server_url + "/join/" + room_id, headers, HTTPClient.METHOD_POST)

func _internal_list_rooms() -> void:
	_send_request(server_url + "/rooms", ["Content-Type: application/json"], HTTPClient.METHOD_GET)

func _internal_add_player(player_oid: String) -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot add player")
		return
	var body = {"player_oid": player_oid}
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_send_request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _internal_remove_player(player_oid: String) -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot remove player")
		return
	var body = {"player_oid": player_oid}
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_send_request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_DELETE, JSON.stringify(body))

func _internal_close_room() -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot close")
		return
	var headers = [
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_send_request(server_url + "/room/%s" % current_room_id, headers, HTTPClient.METHOD_DELETE)

# ----------------------------- Health check -----------------------------
func _check_health_and_run(action: Callable) -> void:
	if not _initialized or server_url.is_empty():
		error_occurred.emit(500, "MatchLayAPI not initialized. Call init() first.")
		return
	_pending_actions.append(action)
	if not _health_check_in_progress:
		_start_health_check()

func _start_health_check() -> void:
	if _health_check_in_progress:
		return
	# Cancel any lingering request
	if _health_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_health_http.cancel_request()
	# Avoid duplicate connections
	if _health_http.request_completed.is_connected(_on_health_check_completed):
		_health_http.request_completed.disconnect(_on_health_check_completed)
	_health_http.request_completed.connect(_on_health_check_completed, CONNECT_ONE_SHOT)
	_health_check_in_progress = true
	_health_http.request(server_url + "/health", ["Content-Type: application/json"], HTTPClient.METHOD_GET)

func _on_health_check_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_health_check_in_progress = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		server_down.emit()
		_cleanup_state()
		_pending_actions.clear()   # no point retrying if server is down
		return
	# Execute all queued actions
	var actions = _pending_actions.duplicate()
	_pending_actions.clear()
	for action in actions:
		action.call()

# ----------------------------- Heartbeat -----------------------------
func _start_heartbeat() -> void:
	if _heartbeat_timer:
		_heartbeat_timer.stop()
	else:
		_heartbeat_timer = Timer.new()
		_heartbeat_timer.name = "HeartBeatTimer"
		add_child(_heartbeat_timer)
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	_heartbeat_timer.start()

func _stop_heartbeat() -> void:
	if _heartbeat_timer:
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null

func _send_heartbeat() -> void:
	if _heartbeat_in_flight:
		return
	if not is_host or current_room_id.is_empty() or host_key.is_empty():
		_stop_heartbeat()
		return
	_heartbeat_in_flight = true
	var body = {"room_id": current_room_id}
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key, "X-Host-Key: " + host_key]
	var req = HTTPRequest.new()
	req.name = "http_heartbeat"
	add_child(req)
	req.timeout = HTTP_REQUEST_TIMEOUT
	req.request_completed.connect(_on_heartbeat_completed.bind(req), CONNECT_ONE_SHOT)
	req.request(server_url + "/heartbeat", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_heartbeat_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	_heartbeat_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		error_occurred.emit(response_code, "Heartbeat failed – room may expire")
		if response_code == 404 or response_code == 403:
			room_expired.emit(current_room_id)
			leave_room()
	else:
		heartbeat_ok.emit()

# ----------------------------- Response handler -----------------------------
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, url: String, method: int) -> void:
	req.queue_free()
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP request failed")
		return
	if response_code != 200:
		var err_msg = json.get("detail", "HTTP error %d" % response_code) if json else "HTTP error %d" % response_code
		error_occurred.emit(response_code, err_msg)
		if response_code == 410:
			room_expired.emit(current_room_id)
			leave_room()
		return
	
	# Handle successful responses
	if json.has("rooms"):
		var typed_rooms: Array[MatchLayRoomData] = []
		for r in json.rooms:
			typed_rooms.append(MatchLayRoomData.new(
				r.get("room_id", ""),
				r.get("public_data", {}),
				r.get("player_count", 0),
				r.get("age_seconds", 0),
				r.get("is_private", true)   # add is_private to room data
			))
		rooms_listed.emit(typed_rooms)
	
	elif json.has("room_id") and json.has("host_key"):
		# Host response (secret may be null)
		var secret_val = json.get("secret")  # can be null
		var is_private_val = json.get("is_private", true)
		is_host = true
		host_key = json.host_key
		room_secret = secret_val if secret_val != null else ""
		current_room_id = json.room_id
		_start_heartbeat()
		room_hosted.emit(json.room_id, room_secret, host_key, is_private_val)
		call_deferred("_auto_add_host_player")
	
	elif json.has("room_id") and json.has("server_oid"):
		# Join response (both secret and room_id endpoints)
		is_host = false
		host_key = ""
		room_secret = ""
		current_room_id = json.room_id
		room_joined.emit(json.room_id, json.server_oid, json.get("player_count", 0))
	
	elif json.has("status") and json.get("status") == "ok":
		if json.has("player_count"):
			player_count_updated.emit(current_room_id, json.player_count)
	
	elif response_code == 200 and method == HTTPClient.METHOD_DELETE and "/room/" in url:
		room_closed.emit()
		leave_room()

func _auto_add_host_player() -> void:
	if is_host and not host_key.is_empty() and not _pending_server_oid.is_empty():
		_internal_add_player(_pending_server_oid)
		_pending_server_oid = ""

# ----------------------------- State cleanup -----------------------------
func _cleanup_state() -> void:
	_stop_heartbeat()
	current_room_id = ""
	is_host = false
	host_key = ""
	room_secret = ""
	_pending_server_oid = ""


func shutdown() -> void:
	# Stop heartbeat and reset room state (reuse existing logic)
	_cleanup_state()
	
	# Cancel health‑check request and disconnect signal
	if _health_http:
		if _health_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			_health_http.cancel_request()
		if _health_http.request_completed.is_connected(_on_health_check_completed):
			_health_http.request_completed.disconnect(_on_health_check_completed)
	
	# Cancel any other in‑flight HTTP requests (from _send_request and heartbeat)
	for child in get_children():
		if child is HTTPRequest:
			if child.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
				child.cancel_request()
			child.queue_free()
	
	# Clear pending action queue (not done by _cleanup_state)
	_pending_actions.clear()
	_health_check_in_progress = false
	
	# Prevent further API calls (not done by _cleanup_state)
	_initialized = false
	
	print("MatchLayAPI fully shut down")
