## HTTP client for MatchLay matchmaker.
class_name MatchLayAPI
extends RefCounted

var server_url: String = ""
var api_key: String = ""
var http_request: HTTPRequest = null

## Must be called before any other methods.
func init(url: String, key: String) -> void:
	server_url = url
	api_key = key
	# Create HTTPRequest node and add it to the scene tree safely
	http_request = HTTPRequest.new()
	# Use call_deferred to avoid "busy parent" error during _ready
	Engine.get_main_loop().root.call_deferred("add_child", http_request)
	http_request.timeout = 5

func host_game(public_data: Dictionary, private_data: Dictionary = {}) -> void:
	if not http_request or not http_request.is_inside_tree():
		printerr("HTTPRequest not ready. Call init() first and wait a frame.")
		return
	var body = JSON.stringify({"public_data": public_data, "private_data": private_data})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/host", headers, HTTPClient.METHOD_POST, body)

func join_game(room_id: String, private_data: Dictionary = {}) -> void:
	if not http_request or not http_request.is_inside_tree():
		printerr("HTTPRequest not ready.")
		return
	var body = JSON.stringify({"private_data": private_data})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/join/" + room_id, headers, HTTPClient.METHOD_POST, body)

func list_rooms() -> void:
	if not http_request or not http_request.is_inside_tree():
		printerr("HTTPRequest not ready.")
		return
	var headers = ["X-API-Key: " + api_key]
	http_request.request(server_url + "/rooms", headers, HTTPClient.METHOD_GET)

func send_heartbeat(room_id: String) -> void:
	if not http_request or not http_request.is_inside_tree():
		return
	var body = JSON.stringify({"room_id": room_id})
	var headers = ["Content-Type: application/json", "X-API-Key: " + api_key]
	http_request.request(server_url + "/heartbeat", headers, HTTPClient.METHOD_POST, body)

# Connect to this signal to handle responses
signal rooms_received(rooms: Array)
signal room_hosted(room_id: String, relay_host: String, relay_port: int)
signal room_joined(room_id: String, relay_host: String, relay_port: int)
signal error_occurred(code: int, message: String)

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
		# Could be from /host or /join – we can't tell which, but both signals are fine
		# We'll emit both, the game can ignore one.
		room_hosted.emit(json.room_id, json.relay_host, json.relay_port)
		room_joined.emit(json.room_id, json.relay_host, json.relay_port)
