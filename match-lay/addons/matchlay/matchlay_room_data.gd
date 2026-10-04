# matchlay_room_data.gd
extends RefCounted
class_name MatchLayRoomData

## Room identifier (8 characters)
var room_id: String = ""
## Public metadata provided by the host (e.g., map, mode)
var public_data: Dictionary = {}
## Current number of players in the room
var player_count: int = 0
## Seconds since the room was created (age)
var age_seconds: int = 0
## Whether the room requires a secret to join (true = private, false = public)
var is_private: bool = true

func _init(p_room_id: String, p_public_data: Dictionary, p_player_count: int, p_age_seconds: int, p_is_private: bool = true) -> void:
	room_id = p_room_id
	public_data = p_public_data
	player_count = p_player_count
	age_seconds = p_age_seconds
	is_private = p_is_private
