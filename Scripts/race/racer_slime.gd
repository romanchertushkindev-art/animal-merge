class_name RacerSlime
extends CharacterBody2D

# Бегун гонки: едет слева направо, переключает три полосы и прыгает.
# Гравитации как таковой нет — Y жёстко привязан к полосе, но прыжок
# это обычная баллистическая дуга над текущей полосой. Сменить полосу
# можно и в прыжке: тогда меняется только точка приземления.
#
# Вид берётся из SlimeData, скорость — из race_speed экземпляра.

signal died()
signal finished()
signal lane_changed(lane: int)

# ============================================
# ДВИЖЕНИЕ
# ============================================
@export_group("Движение")
@export var speed: float = 150.0           # px/с, ставит менеджер по race_speed
@export var lane_y: Array[float] = [245.0, 275.0, 305.0]
@export var lane: int = 1                  # стартовая полоса (0..2)
@export var switch_duration: float = 0.2   # секунд на смену полосы

# ============================================
# ПРЫЖОК
# ============================================
@export_group("Прыжок")
@export var jump_velocity: float = 340.0   # скорость вверх при отталкивании
@export var gravity: float = 950.0         # тяжесть, px/с²
@export var lean: float = 0.18             # наклон корпуса в полёте
@export var stretch: float = 0.8           # сплющивание на взлёте
@export var squash: float = 1.2            # растягивание при приземлении
@export var blink_time: float = 0.25       # мигание при проходе препятствия

# ============================================
# СЛИЗЕНЬ
# ============================================
@export_group("Слизень")
@export var slime_id: String = "green"

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _uid: int = -1
var _alive: bool = false
var _switching: bool = false
var _vy: float = 0.0
var _grounded: bool = true
var _ground_y: float = 0.0
var _blink_left: float = 0.0
var _lane_tween: Tween = null

func _ready() -> void:
	apply_slime(slime_id, -1)
	_ground_y = lane_y[clampi(lane, 0, lane_y.size() - 1)]
	global_position.y = _ground_y

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	global_position.x += speed * delta
	_tick_air(delta)
	_tick_blink(delta)

## Прыжок и приземление. Тень привязана к высоте, чтобы слизень не
## «висел в воздухе» над неподвижной тенью.
func _tick_air(delta: float) -> void:
	_tick_shadow(delta)

	if _grounded:
		return

	_vy += gravity * delta
	global_position.y += _vy * delta

	if global_position.y >= _ground_y:
		global_position.y = _ground_y
		_vy = 0.0
		if not _grounded:
			_grounded = true
			if sprite:
				sprite.scale = Vector2(squash, 1.0 / squash)
				sprite.rotation = 0.0
	elif sprite:
		# В полёте плавно возвращаем масштаб и клоним корпус по скорости
		sprite.scale = sprite.scale.lerp(Vector2.ONE, minf(1.0, delta * 9.0))
		sprite.rotation = lerp(sprite.rotation, clampf(_vy / 900.0, -lean, lean),
			minf(1.0, delta * 8.0))

func _tick_shadow(delta: float) -> void:
	if shadow == null:
		return
	var height := _ground_y - global_position.y
	var target := absf(shadow.scale.x) * (0.72 - clampf(height / 260.0, 0.0, 0.45))
	shadow.position.y = 12.0 - height * 0.35
	shadow.scale.y = lerpf(shadow.scale.y, target, 0.25)
	shadow.modulate.a = lerpf(shadow.modulate.a, clampf(1.0 - height / 220.0, 0.35, 1.0), 0.2)

func _tick_blink(delta: float) -> void:
	if _blink_left <= 0.0:
		return
	_blink_left -= delta
	if sprite:
		sprite.modulate.a = 1.0 if fmod(_blink_left, 0.1) < 0.05 else 0.3
		if _blink_left <= 0.0:
			sprite.modulate.a = 1.0

# ============================================
# ВИД
# ============================================
func apply_slime(id: String, uid: int) -> void:
	slime_id = id
	_uid = uid

	var data := SlimeFactory.get_data(id)
	if data == null:
		push_error("[RacerSlime] Нет данных для id: %s" % id)
		return

	if sprite and data.sheet_texture:
		sprite.sprite_frames = SlimeBase._get_frames_for(sprite.sprite_frames, data.sheet_texture)

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("run_right"):
		sprite.play("run_right")

## Гонковый стат выбранного экземпляра с учётом уровня.
func race_stat(stat: String) -> float:
	if _uid >= 0:
		var value := GameState.get_instance_race_stat(_uid, stat)
		if value > 0.0:
			return value
	var data := SlimeFactory.get_data(slime_id)
	if data == null:
		return 0.0
	return data.get_race_stat(stat, 1)

# ============================================
# УПРАВЛЕНИЕ ЗАЕЗДОМ
# ============================================
func start() -> void:
	_alive = true
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
	_blink_left = blink_time

# ============================================
# ПРЫЖОК И ПОЛОСЫ
# ============================================
func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return

	if event.is_action_pressed("ui_up"):
		switch_lane(-1)
	elif event.is_action_pressed("ui_down"):
		switch_lane(1)
	elif event.is_action_pressed("ui_accept"):
		jump()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		jump()
	elif event is InputEventScreenTouch and event.pressed:
		jump()

func jump() -> bool:
	if not _alive or not _grounded:
		return false

	_grounded = false
	_vy = -jump_velocity
	_kill_lane_tween()

	if sprite:
		sprite.scale = Vector2(stretch, 1.0 / stretch)
	return true

func switch_lane(dir: int) -> void:
	var next := lane + dir
	if next < 0 or next >= lane_y.size():
		return

	lane = next
	_ground_y = lane_y[lane]
	lane_changed.emit(lane)

	# В воздухе твинить нечего: приземлимся уже на новую полосу.
	if not _grounded:
		return

	_switching = true
	_kill_lane_tween()
	_lane_tween = create_tween()
	_lane_tween.tween_property(self, "position:y", lane_y[lane], switch_duration)
	_lane_tween.tween_callback(func() -> void: _switching = false)

func _kill_lane_tween() -> void:
	if _lane_tween and _lane_tween.is_valid():
		_lane_tween.kill()
	_lane_tween = null

func is_grounded() -> bool:
	return _grounded

# ============================================
# ГЕОМЕТРИЯ
# ============================================
func get_body_rect() -> Rect2:
	var size := Vector2(28.0, 28.0)
	if collision_shape and collision_shape.shape is RectangleShape2D:
		size = (collision_shape.shape as RectangleShape2D).size
	return Rect2(global_position - size * 0.5, size)
