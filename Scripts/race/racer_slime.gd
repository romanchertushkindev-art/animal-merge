class_name RacerSlime
extends CharacterBody2D

# Бегун гонки. Максимально просто:
#   - едет вправо со speed;
#   - полоса — индекс в lane_y, Y плавно подъезжает к lane_y[lane];
#   - прыжок — обычная баллистика (vy + гравитация), приземление на полосу.
#
# Никаких твинов на смену полосы: всё считается в _physics_process,
# поэтому прыжок и смена полосы не конфликтуют.

signal died()
signal finished()

# ============================================
# ПАРАМЕТРЫ
# ============================================
@export var speed: float = 190.0            # px/с вправо (менеджер пересчитывает)
@export var lane_y: Array[float] = [245.0, 275.0, 305.0]
@export var lane: int = 1                   # текущая полоса 0..2
@export var lane_speed: float = 300.0       # px/с смены полосы
@export var jump_velocity: float = 400.0    # px/с вверх
@export var gravity: float = 1000.0         # px/с²
@export var slime_id: String = "green"

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ============================================
# СОСТОЯНИЕ
# ============================================
var _uid: int = -1
var _alive: bool = false
var _vy: float = 0.0          # вертикальная скорость (только в прыжке)
var _grounded: bool = true

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	apply_slime(slime_id, -1)
	position.y = lane_y[lane]

# ============================================
# ЦИКЛ
# ============================================
func _physics_process(delta: float) -> void:
	if not _alive:
		return

	# Горизонталь: всегда едем вправо
	position.x += speed * delta

	if _grounded:
		# На земле: плавно к своей полосе (если только что её сменили)
		position.y = move_toward(position.y, lane_y[lane], lane_speed * delta)
	else:
		# В прыжке: баллистика, приземляемся на lane_y[lane]
		_vy += gravity * delta
		position.y += _vy * delta
		if position.y >= lane_y[lane]:
			position.y = lane_y[lane]
			_vy = 0.0
			_grounded = true

# ============================================
# УПРАВЛЕНИЕ
# ============================================
func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return

	if event.is_action_pressed("ui_up"):
		switch_lane(-1)
	elif event.is_action_pressed("ui_down"):
		switch_lane(1)
	elif event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		jump()

func switch_lane(dir: int) -> void:
	lane = clampi(lane + dir, 0, lane_y.size() - 1)

func jump() -> void:
	if not _grounded:
		return
	_grounded = false
	_vy = -jump_velocity

# ============================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================
func start() -> void:
	_alive = true
	_grounded = true
	_vy = 0.0
	position.y = lane_y[lane]
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("run_right"):
		sprite.play("run_right")

func die() -> void:
	if not _alive:
		return
	_alive = false
	died.emit()

func finish() -> void:
	if not _alive:
		return
	_alive = false
	finished.emit()

func flash() -> void:
	if sprite == null:
		return
	sprite.modulate.a = 0.3
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 1.0, 0.2)

# ============================================
# ВИД И СТАТЫ
# ============================================
func apply_slime(id: String, uid: int) -> void:
	slime_id = id
	_uid = uid

	var data := SlimeFactory.get_data(id)
	if data == null:
		return

	if sprite and data.sheet_texture:
		sprite.sprite_frames = SlimeBase._get_frames_for(sprite.sprite_frames, data.sheet_texture)
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("run_right"):
		sprite.play("run_right")

func race_stat(stat: String) -> float:
	if _uid >= 0:
		var value := GameState.get_instance_race_stat(_uid, stat)
		if value > 0.0:
			return value
	var data := SlimeFactory.get_data(slime_id)
	return data.get_race_stat(stat, 1) if data else 0.0

# ============================================
# ГЕОМЕТРИЯ
# ============================================
func get_body_rect() -> Rect2:
	var size := Vector2(28.0, 28.0)
	if collision_shape and collision_shape.shape is RectangleShape2D:
		size = (collision_shape.shape as RectangleShape2D).size
	return Rect2(global_position - size * 0.5, size)
