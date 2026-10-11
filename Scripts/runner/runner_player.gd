extends CharacterBody2D

class_name RunnerPlayer

# ============================================
# PLAYER
# ============================================
@export var speed: float = 200.0          # pixels per second, world moves past the player
@export var jump_velocity: float = 340.0
@export var gravity: float = 900.0
@export var lane_y: Array[float] = [100.0, 200.0, 300.0]  # Y positions of three stripes
@export var switch_duration: float = 0.3   # seconds to tween between lanes

# ============================================
# СОСТОЯНИЕ
# ============================================
var current_lane: int = 1                    # 0 = верх, 1 = средняя, 2 = низ (соответственно)
var is_switching: bool = false               # блокировка ввода во время перехода
var _vy: float = 0.0                         # вертикальная скорость для прыжка
var _grounded: bool = true                  # стоит ли на земле
var _animation_played: bool = false         # предотвращение лишних переключений

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	clamp(current_lane, 0, lane_y.size() - 1)
	position.y = lane_y[current_lane]
	sprite.play(&"run_left")
	# Инициализируем коллизию по умолчанию (прямоугольник)
	if collision_shape == null:
		collision_shape = CollisionShape2D.new()
		collision_shape.shape = RectangleShape2D.new(28.0, 28.0)
		add_child(collision_shape)

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(delta: float) -> void:
	# Горизонтальное движение: мир едет вправо, значит позиция игрока не меняется.
	# Если мы хотим, чтобы игрок двигался вперёд, можно сделать так:
	# position.x += speed * delta
	# Но для простоты оставим его на месте, так как земля движется.
	_tick_gravity(delta)
	_tick_jump()

func _tick_gravity(delta: float) -> void:
	if not _grounded:
		_vy += gravity * delta
		position.y += _vy * delta

	# Проверяем, не коснулись ли земли
	var ground_y := lane_y[current_lane]
	if position.y >= ground_y:
		position.y = ground_y
		_vy = 0.0
		if not _grounded:
			_grounded = true
			# Анимация при приземлении
		if sprite and not _animation_played:
			sprite.play(&"run_left")
			_animation_played = true

func _tick_jump() -> void:
	if Input.is_action_just_pressed("ui_up") and _grounded and not is_switching:
		_grounded = false
		_vy = -jump_velocity
		_animation_played = false
		sprite.play(&"run_left")

# ============================================
# ПЕРЕКЛЮЧЕНИЕ ПОЛОС
# ============================================
func _input(event: InputEvent) -> void:
	if is_switching:
		return

	if event.is_action_pressed("ui_right"):
		_change_lane(+1)
	elif event.is_action_pressed("ui_left"):
		_change_lane(-1)

func _change_lane(direction: int) -> void:
	var next: int = current_lane + direction
	if next < 0 or next >= lane_y.size():
		return
	is_switching = true
	var target_y: float = lane_y[next]

	# Анимация бега в сторону
	if direction > 0:
		sprite.play(&"run_right")
	else:
		sprite.play(&"run_left")

	# Плавно перемещаемся
	var tween := create_tween()
	tween.tween_property(self, &"position:y", target_y, switch_duration)
	tween.tween_callback(func(): is_switching = false)
	tween.tween_callback(func(): current_lane = next)
tween.play()

# ============================================
# ПОЛУЧЕНИЕ ГЕОМЕТРИИ
# ============================================
func get_body_rect() -> Rect2:
	if collision_shape == null:
		return Rect2(-14, -14, 28, 28)
	var size: Vector2 = collision_shape.shape.get_rect().size
	return Rect2(global_position - size * 0.5, size)