extends Area2D

@export var scene_to_load: String = "res://Scenes/main.tscn" 
@onready var polygon: Polygon2D = $Polygon2D

func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func _on_mouse_entered():
	polygon.visible = true
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_mouse_exited():
	polygon.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if scene_to_load:
			SceneTransition.change_scene(scene_to_load)
		else:
			print("Ошибка: Сцена не выбрана в инспекторе!")
