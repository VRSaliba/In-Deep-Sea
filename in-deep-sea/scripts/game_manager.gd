extends Node

const LEVEL_1 = preload("uid://esv4e8s4h3q6")

var current_level_packed_scene: PackedScene
var current_level_node: Node2D

func _ready() -> void:
	GlobalSignals.restart_level_signal.connect(restart_level)
	GlobalSignals.go_to_next_level_reached.connect(change_current_level)
	
	change_current_level(LEVEL_1)

func _process(_delta: float) -> void:
	pass

func change_current_level(next_level: PackedScene) -> void:
	if current_level_node:
		current_level_node.queue_free()

	var new_current_level = next_level.instantiate()
	add_child(new_current_level)
	current_level_packed_scene = next_level
	current_level_node = new_current_level

func restart_level() -> void:
	if current_level_node:
		current_level_node.queue_free()
	current_level_node = current_level_packed_scene.instantiate()
	add_child(current_level_node)
