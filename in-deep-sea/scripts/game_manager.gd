extends Node

const LEVEL_1 = preload("uid://esv4e8s4h3q6")
const LEVEL_2 = preload("uid://1w83hqlrkygx")
const LEVEL_3 = preload("uid://g7err3hw88kq")
const LEVEL_4 = preload("uid://bfibno4vuqco2")
const LEVEL_5 = preload("uid://ku4kt6dr4tfq")

var current_level_packed_scene: PackedScene
var current_level_node: Node2D

var next_level_string: String
var next_level_packed_scene: PackedScene

func _ready() -> void:
	GlobalSignals.restart_level_signal.connect(restart_level)
	GlobalSignals.go_to_next_level_reached.connect(level_finished)
	GlobalSignals.go_to_next_level_button_pressed.connect(go_to_next_level)
	
	next_level_string = "uid://ku4kt6dr4tfq"
	next_level_packed_scene = load(next_level_string)
	go_to_next_level()

func _process(_delta: float) -> void:
	pass

func level_finished(next_level: String) -> void:
	print(next_level)
	next_level_string = next_level

func go_to_next_level() -> void:
	if current_level_node:
		current_level_node.queue_free()
	
	next_level_packed_scene = load(next_level_string)
	var new_current_level = next_level_packed_scene.instantiate()
	add_child(new_current_level)
	current_level_packed_scene = next_level_packed_scene
	current_level_node = new_current_level

func restart_level() -> void:
	if current_level_node:
		current_level_node.queue_free()
	current_level_node = current_level_packed_scene.instantiate()
	add_child(current_level_node)


func _on_restart_button_pressed() -> void:
	restart_level()


func _on_continue_button_pressed() -> void:
	pass
