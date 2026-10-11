extends Camera2D

@export var target: Node2D
@export var offset_x: float = 200.0
@export var fixed_y: float = 300.0

var _prev_x: float
var _curr_x: float

func _ready() -> void:
	_prev_x = target.global_position.x
	_curr_x = _prev_x
	global_position = Vector2(_curr_x + offset_x, fixed_y)

func _physics_process(_delta: float) -> void:
	_prev_x = _curr_x
	_curr_x = target.global_position.x

func _process(_delta: float) -> void:
	var t := Engine.get_physics_interpolation_fraction()
	var x := lerpf(_prev_x, _curr_x, t) + offset_x
	global_position = Vector2(x, fixed_y)
