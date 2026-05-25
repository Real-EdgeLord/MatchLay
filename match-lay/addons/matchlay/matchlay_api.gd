# matchlay_api.gd – fully internal heartbeat management
extends Node
class_name MatchLayAPI

# ----------------------------- Signals ---------------------------------
signal rooms_listed(rooms: Array)
signal room_hosted(room_id: String, secret: String, host_key: String, noray_host: String, noray_port: int, server_oid: String)
signal room_joined(room_id: String, server_oid: String, noray_host: String, noray_port: int)
signal player_count_updated(room_id: String, player_count: int)
signal heartbeat_ok()
signal room_closed()
signal error_occurred(code: int, message: String)
signal room_expired(room_id: String)
signal server_down()

# ----------------------------- Configuration -----------------------------
const HEARTBEAT_INTERVAL: float = 20.0      # send heartbeat every 20s
const MAIN_REQUEST_TIMEOUT: int = 15        # seconds for normal API calls
const HEARTBEAT_TIMEOUT: int = 10           # seconds for heartbeat HTTP
const HEALTH_TIMEOUT: int = 5               # seconds for health check

# ----------------------------- State ---------------------------------
var server_url: String = ""
var api_key: String = ""

var current_room_id: String = ""
var is_host: bool = false
var host_key: String = ""
var room_secret: String = ""

var _heartbeat_timer: Timer = null
var _http: HTTPRequest = null
var _health_http: HTTPRequest = null

# ----------------------------- Public API -----------------------------
func init(url: String, key: String) -> void:
	server_url = url.rstrip("/")
	api_key = key
	_http = HTTPRequest.new()
	_health_http = HTTPRequest.new()
	add_child(_http)
	add_child(_health_http)
	_http.timeout = MAIN_REQUEST_TIMEOUT
	_health_http.timeout = HEALTH_TIMEOUT
	_http.request_completed.connect(_on_request_completed)

func host_game(server_oid: String, match_time: int = 0, public_data: Dictionary = {}) -> void:
	_check_health_and_run(_internal_host_game.bind(server_oid, match_time, public_data))

func join_with_secret(secret: String) -> void:
	_check_health_and_run(_internal_join_with_secret.bind(secret))

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
	var json_body = JSON.stringify(body)
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	_http.request(server_url + "/host", headers, HTTPClient.METHOD_POST, json_body)

func _internal_join_with_secret(secret: String) -> void:
	var body = {"secret": secret}
	var json_body = JSON.stringify(body)
	var headers = ["Content-Type: application/json"]
	_http.request(server_url + "/join", headers, HTTPClient.METHOD_POST, json_body)

func _internal_list_rooms() -> void:
	var headers = ["X-API-Key: " + api_key]
	_http.request(server_url + "/rooms", headers, HTTPClient.METHOD_GET)

func _internal_add_player(player_oid: String) -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot add player")
		return
	var body = {"player_oid": player_oid}
	var json_body = JSON.stringify(body)
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_http.request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_POST, json_body)

func _internal_remove_player(player_oid: String) -> void:
	if not is_host or host_key.is_empty():
		error_occurred.emit(403, "Not hosting a room – cannot remove player")
		return
	var body = {"player_oid": player_oid}
	var json_body = JSON.stringify(body)
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Host-Key: " + host_key
	]
	_http.request(server_url + "/room/%s/player" % current_room_id, headers, HTTPClient.METHOD_DELETE, json_body)

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
	if server_url.is_empty():
		server_down.emit()
		_cleanup_state()
		return
	var headers = ["Content-Type: application/json"]
	_health_http.request_completed.connect(
		_on_health_check_completed.bind(action),
		CONNECT_ONE_SHOT
	)
	_health_http.request(server_url + "/health", headers, HTTPClient.METHOD_GET)

func _on_health_check_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, action: Callable) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		server_down.emit()
		_cleanup_state()
		return
	action.call()

# ----------------------------- Heartbeat (fully internal) -----------------------------
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
	if not is_host or current_room_id.is_empty() or host_key.is_empty():
		_stop_heartbeat()
		return
	
	var body = {"room_id": current_room_id}
	var json_body = JSON.stringify(body)
	var headers = [
		"Content-Type: application/json",
		"X-Host-Key: " + host_key
	]
	var heartbeat_req = HTTPRequest.new()
	add_child(heartbeat_req)
	heartbeat_req.timeout = HEARTBEAT_TIMEOUT
	heartbeat_req.request_completed.connect(_on_heartbeat_completed.bind(heartbeat_req))
	heartbeat_req.request(server_url + "/heartbeat", headers, HTTPClient.METHOD_POST, json_body)

func _on_heartbeat_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, req: HTTPRequest):
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		error_occurred.emit(response_code, "Heartbeat failed – room may expire")
		if response_code == 404 or response_code == 403:
			room_expired.emit(current_room_id)
			leave_room()  # stops heartbeat and cleans state
	else:
		heartbeat_ok.emit()

# ----------------------------- Response handler -----------------------------
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP request failed (network error)")
		return
	
	if response_code != 200:
		var err_msg = json.get("detail", "HTTP error %d" % response_code) if json else "HTTP error %d" % response_code
		error_occurred.emit(response_code, err_msg)
		if response_code == 410:
			room_expired.emit(current_room_id)
			leave_room()
		return
	
	# Handle different responses
	if json.has("rooms"):
		rooms_listed.emit(json.rooms)
	elif json.has("room_id") and json.has("noray_host") and json.has("noray_port"):
		if json.has("host_key") and json.has("secret"):
			# Host response
			is_host = true
			host_key = json.host_key
			room_secret = json.secret
			current_room_id = json.room_id
			_start_heartbeat()   # start internal heartbeat
			room_hosted.emit(
				json.room_id,
				json.secret,
				json.host_key,
				json.noray_host,
				json.noray_port,
				json.server_oid
			)
			# Auto-add host as player
			call_deferred("_auto_add_host_player", json.server_oid)
		else:
			# Join response
			is_host = false
			host_key = ""
			room_secret = ""
			current_room_id = json.room_id
			room_joined.emit(
				json.room_id,
				json.server_oid,
				json.noray_host,
				json.noray_port
			)
	elif json.has("status") and json.get("status") == "ok":
		if json.has("player_count"):
			player_count_updated.emit(current_room_id, json.player_count)
	elif response_code == 200 and (str(_http.get_path()) as String).contains("/room/") and _http.get_method() == HTTPClient.METHOD_DELETE:
		room_closed.emit()
		leave_room()

func _auto_add_host_player(server_oid: String) -> void:
	if is_host and not host_key.is_empty():
		_internal_add_player(server_oid)

# ----------------------------- State cleanup -----------------------------
func _cleanup_state() -> void:
	_stop_heartbeat()
	current_room_id = ""
	is_host = false
	host_key = ""
	room_secret = ""
