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
@export var lane_y: Array[float] = [200.0, 275.0, 305.0]
@export var lane: int = 1                   # текущая полоса 0..2
@export var lane_speed: float = 300.0       # px/с смены полосы
@export var jump_velocity: float = 400.0    # px/с вверх
@export var gravity: float = 1000.0         # px/с²
@export var slime_id: String = "green"

# ============================================
# БОТ
# ============================================
@export var is_bot: bool = false              # бот едет сам и сам меняет полосы
@export var bot_switch_interval: float = 1.2  # раз в сколько секунд бот думает о смене
@export var bot_switch_chance: float = 0.5    # шанс сменить полосу

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var effects: AnimatedSprite2D = $Effects
@onready var overhead_pointer: AnimatedSprite2D = $OverheadPointer

# ============================================
# СОСТОЯНИЕ
# ============================================
var _uid: int = -1
var _alive: bool = false
var _vy: float = 0.0          # вертикальная скорость (только в прыжке)
var _grounded: bool = true
var _bot_timer: float = 0.0   # таймер бота до следующей попытки сменить полосу
var obstacles_layer: TileMapLayer = null   # ставит менеджер, чтобы бот видел препятствия
var _dashing: bool = false      # идёт ли деш (смена полосы на земле)
var _dash_from_lane: int = -1   # полоса, с которой дешнули (для отката)
var _stun_timer: float = 0.0    # оглушение: пока > 0 не едем вперёд

# ============================================
# СОСТОЯНИЕ (публичный доступ)
# ============================================
func is_grounded() -> bool:
	return _grounded

func is_dashing() -> bool:
	return _dashing

func get_dash_from_lane() -> int:
	return _dash_from_lane

## Оглушение: слизень ненадолго перестаёт ехать вперёд и показывает звёзды.
func bump() -> void:
	_stun_timer = 0.5
	if overhead_pointer:
		overhead_pointer.visible = true
		overhead_pointer.play("bump")

## Плавно вернуться на полосу (после неудачного деша в другого слизня).
func return_to_lane(target: int) -> void:
	lane = clampi(target, 0, lane_y.size() - 1)
	_dashing = false
	# Y сам плавно подъедет через move_toward в _physics_process

## Включает/выключает коллизию в зависимости от состояния.
## Вызывается при старте, прыжке и приземлении.
func _update_collision() -> void:
	if collision_shape:
		collision_shape.disabled = not _grounded
		
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
		
	# Горизонталь: едем вправо (оглушён — стоим на месте)
	if _stun_timer > 0.0:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			# Оглушение кончилось: игроку возвращаем указатель, боту прячем
			if overhead_pointer:
				if is_bot:
					overhead_pointer.visible = false
				else:
					overhead_pointer.play("pointer")
	else:
		position.x += speed * delta

	if _grounded:
		# На земле: плавно к своей полосе (если только что её сменили)
		position.y = move_toward(position.y, lane_y[lane], lane_speed * delta)
		if _dashing and absf(position.y - lane_y[lane]) < 0.5:
			_dashing = false
	else:
		# В прыжке: баллистика, приземляемся на lane_y[lane]
		_vy += gravity * delta
		position.y += _vy * delta
		if position.y >= lane_y[lane]:
			position.y = lane_y[lane]
			_vy = 0.0
			_grounded = true
			_update_collision()

	# Бот: перепрыгивает препятствие впереди, иначе сам меняет полосу
	if is_bot:
		if _grounded and _obstacle_ahead():
			jump()
		_bot_timer -= delta
		if _bot_timer <= 0.0:
			_bot_timer = bot_switch_interval
			if randf() < bot_switch_chance:
				switch_lane(-1 if randf() < 0.5 else 1)

## Есть ли препятствие на полосе бота чуть впереди.
func _obstacle_ahead() -> bool:
	if obstacles_layer == null:
		return false
	for cell in obstacles_layer.get_used_cells():
		var data := obstacles_layer.get_cell_tile_data(cell)
		if data == null:
			continue
		var lane_v: Variant = data.get_custom_data("lane")
		if lane_v == null or int(lane_v) != lane:
			continue
		var center := obstacles_layer.to_global(obstacles_layer.map_to_local(cell))
		if center.x > global_position.x and center.x < global_position.x + 140.0:
			return true
	return false

# ============================================
# УПРАВЛЕНИЕ
# ============================================
func _unhandled_input(event: InputEvent) -> void:
	if is_bot or not _alive:
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
	if _grounded == false:
		return
	
	_dash_from_lane = lane
	playDash(dir)
	lane = clampi(lane + dir, 0, lane_y.size() - 1)
	_dashing = true

func playDash(dir: int) -> void: 
	if lane == 0 and dir == -1 or lane == 2 and dir == 1:
		return
		
	if dir == 1:
		effects.rotation_degrees = -90
		effects.position = Vector2(0, -25)
	else:
		effects.rotation_degrees = 90
		effects.position = Vector2(0, 25)
		
	effects.play("dash")
	
func playJump() -> void:
	effects.rotation_degrees = 0
	effects.position = Vector2(0, 25)
	effects.play("jump")
	
func jump() -> void:
	if not _grounded:
		return
	_dashing = false
	playJump()
	_grounded = false
	_vy = -jump_velocity
	_update_collision()

# ============================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================
func start() -> void:
	_alive = true
	_grounded = true
	_vy = 0.0
	position.y = lane_y[lane]
	_update_collision()     
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
	
	overhead_pointer.visible = !is_bot
	
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
