class_name MovementComponent
extends Node

# ============================================
# СИГНАЛЫ
# ============================================
signal direction_changed(new_direction: Vector2)
signal move_state_changed(is_walking: bool)

# ============================================
# НАСТРОЙКИ
# ============================================
@export_group("Скорость")
@export var speed: float = 100.0

@export_group("Тайминги")
@export var min_move_time: float = 2.0
@export var max_move_time: float = 4.0
@export var min_idle_time: float = 1.0
@export var max_idle_time: float = 3.0

@export_group("Границы")
@export var boundary_padding: float = 20.0
@export var use_screen_bounds: bool = true

# ============================================
# СОСТОЯНИЕ
# ============================================
enum MoveState { WALK, IDLE }

var state: MoveState = MoveState.WALK
var direction: Vector2 = Vector2.ZERO
var last_direction: Vector2 = Vector2.DOWN

var _timer: float = 0.0
var _parent: Node2D
var _enabled: bool = true
var _screen_size: Vector2

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	_parent = get_parent() as Node2D
	if _parent == null:
		push_error("[MovementComponent] Родитель должен быть Node2D")
		return

	_screen_size = _parent.get_viewport_rect().size
	_start_walk()

func _process(delta):
	if not _enabled or _parent == null:
		return

	_timer -= delta
	if _timer <= 0:
		_switch_state()

	if state == MoveState.WALK:
		_parent.global_position += direction * speed * delta
		_handle_boundaries()

# ============================================
# ПУБЛИЧНЫЙ API
# ============================================
func enable():
	_enabled = true

func disable():
	_enabled = false

func is_walking() -> bool:
	return state == MoveState.WALK

func set_direction(new_dir: Vector2):
	direction = new_dir.normalized()
	if direction != Vector2.ZERO:
		last_direction = direction
		direction_changed.emit(direction)

func set_random_direction():
	var angle = randf() * TAU
	set_direction(Vector2(cos(angle), sin(angle)))

func turn_around():
	set_direction(-direction)

# Принудительно в IDLE (например, при атаке)
func force_idle(duration: float = -1.0):
	state = MoveState.IDLE
	_timer = duration if duration > 0 else randf_range(min_idle_time, max_idle_time)
	move_state_changed.emit(false)

func force_walk():
	state = MoveState.WALK
	set_random_direction()
	_timer = randf_range(min_move_time, max_move_time)
	move_state_changed.emit(true)

# ============================================
# ВНУТРЕННЕЕ
# ============================================
func _start_walk():
	state = MoveState.WALK
	set_random_direction()
	_timer = randf_range(min_move_time, max_move_time)

func _switch_state():
	if state == MoveState.WALK:
		state = MoveState.IDLE
		_timer = randf_range(min_idle_time, max_idle_time)
		move_state_changed.emit(false)
	else:
		state = MoveState.WALK
		set_random_direction()
		_timer = randf_range(min_move_time, max_move_time)
		move_state_changed.emit(true)

func _handle_boundaries():
	if not use_screen_bounds:
		return

	var pad = Vector2(boundary_padding, boundary_padding)
	var min_pos = pad
	var max_pos = _screen_size - pad

	if _parent.global_position.x < min_pos.x:
		_parent.global_position.x = min_pos.x
		direction.x = abs(direction.x)
	elif _parent.global_position.x > max_pos.x:
		_parent.global_position.x = max_pos.x
		direction.x = -abs(direction.x)

	if _parent.global_position.y < min_pos.y:
		_parent.global_position.y = min_pos.y
		direction.y = abs(direction.y)
	elif _parent.global_position.y > max_pos.y:
		_parent.global_position.y = max_pos.y
		direction.y = -abs(direction.y)
