extends Node

const RelayAPI = preload("res://addons/matchlay/relay_api.gd")
var relay_api: RelayAPI

func _ready() -> void:
	_on_room_hosted("test","192.168.0.111",5555)

func _on_room_hosted(room_id: String, relay_host: String, relay_port: int):
	relay_api = RelayAPI.new()
	var err = relay_api.setup(relay_host, relay_port, room_id)
	if err == OK:
		multiplayer.multiplayer_api = relay_api   # ✅ This line is crucial
		print("Relay API activated – you can now use @rpc.")
