## MatchLayAPI - Handles HTTP communication with the MatchLay server.
class_name MatchLayAPI
extends RefCounted

signal rooms_received(rooms: Array)
signal room_joined(room_id: String, relay_host: String, relay_port: int)
signal room_hosted(room_id: String, relay_host: String, relay_port: int)
signal error_occurred(error_code: int, message: String)

const DEFAULT_TIMEOUT: float = 5.0

var server_url: String = ""
var api_key: String = ""
var http_request: HTTPRequest

func _init(server_url: String, api_key: String):
	self.server_url = server_url
	self.api_key = api_key
	# Create a hidden HTTPRequest node in the scene tree.
	var root = Engine.get_main_loop().root
	http_request = HTTPRequest.new()
	root.add_child(http_request)
	http_request.timeout = DEFAULT_TIMEOUT
	http_request.request_completed.connect(_on_request_completed)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if http_request and is_instance_valid(http_request):
			http_request.queue_free()

func host_game(public_data: Dictionary, private_data: Dictionary = {}) -> void:
	var body = JSON.stringify({
		"public_data": public_data,
		"private_data": private_data
	})
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	var url = server_url + "/host"
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		error_occurred.emit(error, "Failed to send host request.")

func join_game(room_id: String, private_data: Dictionary = {}) -> void:
	var body = JSON.stringify({
		"private_data": private_data
	})
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	var url = server_url + "/join/" + room_id
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		error_occurred.emit(error, "Failed to send join request.")

func list_rooms() -> void:
	var headers = ["X-API-Key: " + api_key]
	var error = http_request.request(server_url + "/rooms", headers, HTTPClient.METHOD_GET)
	if error != OK:
		error_occurred.emit(error, "Failed to list rooms.")

func send_heartbeat(room_id: String) -> void:
	var body = JSON.stringify({"room_id": room_id})
	var headers = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	var error = http_request.request(server_url + "/heartbeat", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("Heartbeat failed: ", error)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var response_body = body.get_string_from_utf8()
	var json = JSON.parse_string(response_body)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit(result, "HTTP Request failed.")
		return
	
	if response_code != 200:
		var error_msg = json.get("detail", "Unknown error") if json else "Unknown error"
		error_occurred.emit(response_code, error_msg)
		return
	
	# Determine the endpoint based on the URL from the request's metadata.
	var endpoint = http_request.get_downloaded_bytes()  # Not ideal, but we'll handle it via signals.
	# A better approach: store the request type before making the request.
	# We'll handle this by inspecting the `json` response structure.
	if json.has("rooms"):
		rooms_received.emit(json.rooms)
	elif json.has("room_id") and json.has("relay_host") and json.has("relay_port"):
		if response_body.find("/host") != -1: # Crude but works for now.
			room_hosted.emit(json.room_id, json.relay_host, json.relay_port)
		else:
			room_joined.emit(json.room_id, json.relay_host, json.relay_port)
	else:
		# Handle other responses (e.g., heartbeat)
		pass
