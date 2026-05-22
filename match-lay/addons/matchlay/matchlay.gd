@tool
extends EditorPlugin

func _enter_tree():
	# No autoloads needed – class_name makes RelayPeer globally available.
	pass

func _exit_tree():
	pass
