extends Button

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	SceneTransition.change_scene("res://Scenes/race/race.tscn")
