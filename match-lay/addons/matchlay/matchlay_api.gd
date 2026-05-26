# matchlay_api.gd – Updated for cleaned Python matchmaker
extends Node
class_name MatchLayAPI

# ----------------------------- Signals ---------------------------------
signal rooms_listed(rooms: Array[MatchLayRoomData])
signal room_hosted(room_id: String, secret: String, host_key: String)
signal room_joined(room_id: String, server_oid: String, player_count: int)
signal player_count_updated(room_id: String, player_count: int)
signal heartbeat_ok()
signal room_closed()
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)
signal server_down()

# ----------------------------- Configuration -----------------------------
const HEARTBEAT_INTERVAL: float = 30.0
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

var _http: HTTPRequest = null
var _health_http: HTTPRequest = null

# ----------------------------- Public API -----------------------------
func init(url: String, key: String) -> void:
	var full_url = url.strip_edges()
	if not full_url.begins_with("http://") and not full_url.begins_with("https://"):
		full_url = "http://" + full_url
	server_url = full_url.rstrip("/")
	api_key = key
	
	_http = HTTPRequest.new()
	_health_http = HTTPRequest.new()
	add_child(_http)
	add_child(_health_http)
	_http.timeout = HTTP_REQUEST_TIMEOUT
	_health_http.timeout = HEALTH_CHECK_TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	_initialized = true
	print("MatchLayAPI ready at ", server_url)

func host_game(server_oid: String, match_time: int = 0, public_data: Dictionary = {}) -> void:
	_pending_server_oid = server_oid
	_check_health_and_run(_internal_host_game.bind(server_oid, match_time, public_data))

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
func _internal_host_game(server_oid: String, match_time: int, public_data: Dictionary) -> void:
	var body = {
		"server_oid": server_oid,
		"match_time": match_time if match_time > 0 else null,
		"public_data": public_data
	}
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	_http.request(server_url + "/host", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _internal_join_with_secret(secret: String) -> void:
	var body = {"secret": secret}
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	_http.request(server_url + "/join", headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _internal_join_with_room_id(room_id: String) -> void:
	var headers = ["X-API-Key: " + api_key]
	_http.request(server_url + "/join/" + room_id, headers, HTTPClient.METHOD_POST)

func _internal_list_rooms() -> void:
	# No API key needed for public /rooms endpoint
	var headers = ["Content-Type: application/json"]
	_http.request(server_url + "/rooms", headers, HTTPClient.METHOD_GET)

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
	_http.request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

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
	_http.request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_DELETE, JSON.stringify(body))

func _internal_close_room() -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot close")
		return
	var headers = [
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_http.request(server_url + "/room/%s" % current_room_id, headers, HTTPClient.METHOD_DELETE)

# ----------------------------- Health check -----------------------------
func _check_health_and_run(action: Callable) -> void:
	if not _initialized or server_url.is_empty():
		error_occurred.emit(500, "MatchLayAPI not initialized. Call init() first.")
		return
	_health_http.request_completed.connect(_on_health_check_completed.bind(action), CONNECT_ONE_SHOT)
	_health_http.request(server_url + "/health", ["Content-Type: application/json"], HTTPClient.METHOD_GET)

func _on_health_check_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, action: Callable) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		server_down.emit()
		_cleanup_state()
		return
	action.call()

# ----------------------------- Heartbeat -----------------------------
func _start_heartbeat() -> void:
	if _heartbeat_timer:
		_heartbeat_timer.stop()
	else:
		_heartbeat_timer = Timer.new()
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
	var headers = ["Content-Type: application/json", "X-Host-Key: " + host_key]
	var req = HTTPRequest.new()
	add_child(req)
	req.timeout = HTTP_REQUEST_TIMEOUT
	req.request_completed.connect(_on_heartbeat_completed.bind(req))
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
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
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
	
	if json.has("rooms"):
		var typed_rooms: Array[MatchLayRoomData] = []
		for r in json.rooms:
			typed_rooms.append(MatchLayRoomData.new(
				r.get("room_id", ""),
				r.get("public_data", {}),
				r.get("player_count", 0),
				r.get("age_seconds", 0)
			))
		rooms_listed.emit(typed_rooms)
	elif json.has("room_id") and json.has("host_key") and json.has("secret"):
		is_host = true
		host_key = json.host_key
		room_secret = json.secret
		current_room_id = json.room_id
		_start_heartbeat()
		room_hosted.emit(json.room_id, json.secret, json.host_key)
		call_deferred("_auto_add_host_player")
	elif json.has("room_id") and json.has("server_oid"):
		is_host = false
		host_key = ""
		room_secret = ""
		current_room_id = json.room_id
		room_joined.emit(json.room_id, json.server_oid, json.get("player_count", 0))
	elif json.has("status") and json.get("status") == "ok":
		if json.has("player_count"):
			player_count_updated.emit(current_room_id, json.player_count)
	elif response_code == 200 and _http.get_method() == HTTPClient.METHOD_DELETE and str(_http.get_path()).find("/room/") != -1:
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
