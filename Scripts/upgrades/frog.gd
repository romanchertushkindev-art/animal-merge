extends StaticBody2D
class_name Frog

# ============================================
# НАСТРОЙКИ — ЯЗЫК
# ============================================
@export_group("Язык")
@export var attack_radius: float = 10.0
@export var attack_interval: float = 1.5
@export var tongue_speed: float = 2000.0
@export var swallow_duration: float = 0.4
@export var tongue_base_offset: Vector2 = Vector2(10, -1)

@export_group("Атака")
@export var windup_time: float = 0.15       # задержка перед вылетом языка

# Какой это апгрейд ("frog", ...). Ставится UpgradeFactory при спавне
# и вручную в сцене — по нему ферма узнаёт, что это «его» жаба,
# и не плодит лишних при первой же покупке.
@export var upgrade_id: String = ""

# ============================================
# ССЫЛКИ
# ============================================
# ВАЖНО: TongueLine обязан оставаться с position = (0, 0) и scale = (1, 1).
# _draw_tongue пишет точки в локальных координатах жабы, поэтому любой
# трансформ самого узла (например, если нарисовать линию мышкой в
# редакторе) сдвинет язык с рта и сожмёт его длину.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var tongue: Line2D = $TongueLine
@onready var movement: MovementComponent = $Movement

# ============================================
# СОСТОЯНИЯ
# ============================================
enum State { IDLE, ATTACK, SWALLOW }
var current_state: State = State.IDLE:
	set(value):
		if current_state == value:
			return
		current_state = value
		# Зона досягаемости рисуется только в покое — перерисовываем
		queue_redraw()

# ============================================
# ТАЙМЕРЫ
# ============================================
var _attack_timer: float = 0.0
var _swallow_timer: float = 0.0

# ============================================
# ЯЗЫК
# ============================================
var _target_drop: Area2D = null
var _tongue_progress: float = 0.0
var _tongue_phase: String = ""   # "extend" | "hold" | "retract"

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	add_to_group("frogs")
	_attack_timer = attack_interval

	if tongue:
		tongue.points = PackedVector2Array()
		tongue.visible = false

	if movement:
		movement.move_state_changed.connect(_on_move_state_changed)

	_update_sprite()

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(delta):
	_attack_timer -= delta

	# Флип только когда жаба спокойна
	if current_state == State.IDLE:
		_update_flip()

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.ATTACK:
			_process_attack(delta)
		State.SWALLOW:
			_process_swallow(delta)

# ============================================
# IDLE
# ============================================
func _process_idle(_delta):
	if _attack_timer <= 0:
		var drop = _find_nearest_drop()
		if drop:
			_start_attack(drop)
			_attack_timer = attack_interval

# ============================================
# ATTACK
# ============================================
func _process_attack(delta):
	if _target_drop == null or not is_instance_valid(_target_drop):
		_finish_attack()
		return

	# Цель в ЛОКАЛЬНЫХ координатах Frog
	var target_local = to_local(_target_drop.global_position)
	var base = _get_tongue_base_local()

	if _tongue_phase == "extend":
		_tongue_progress += (tongue_speed / attack_radius) * delta
		if _tongue_progress >= 1.0:
			_tongue_progress = 1.0
			_tongue_phase = "hold"

	elif _tongue_phase == "hold":
		# Тянем каплю в ГЛОБАЛЬНЫХ координатах
		_target_drop.global_position = _target_drop.global_position.lerp(
			global_position, delta * 10.0
		)
		if global_position.distance_to(_target_drop.global_position) < 30:
			_collect_target()
			return

	elif _tongue_phase == "retract":
		_tongue_progress -= (tongue_speed / attack_radius) * delta * 1.5
		if _tongue_progress <= 0:
			_tongue_progress = 0.0
			_finish_attack()
			return

	# Интерполяция от базы к цели
	var tip = base + (target_local - base) * _tongue_progress
	_draw_tongue(base, tip)

# ============================================
# SWALLOW
# ============================================
func _process_swallow(delta):
	_swallow_timer -= delta
	if _swallow_timer <= 0:
		current_state = State.IDLE

		if movement:
			movement.enable()

		_update_sprite()

# ============================================
# ПОИСК / СТАРТ / ФИНИШ
# ============================================
func _find_nearest_drop() -> Area2D:
	var drops = get_tree().get_nodes_in_group("slime_drops")
	var nearest: Area2D = null
	var min_dist = attack_radius

	for d in drops:
		if not is_instance_valid(d):
			continue
		var dist = global_position.distance_to(d.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = d
	return nearest

func _start_attack(drop: Area2D):
	# Защита от повторного вызова
	if current_state != State.IDLE:
		return

	if movement:
		movement.disable()

	_play("tongue")

	# Задержка перед "вылетом" языка
	if windup_time > 0.0:
		await get_tree().create_timer(windup_time).timeout

	# Проверки после await
	if not is_inside_tree():
		return
	if not is_instance_valid(drop):
		# Капля уже собрана — отменяем
		current_state = State.IDLE
		if movement:
			movement.enable()
		_update_sprite()
		return

	# Начинаем атаку
	_target_drop = drop
	_tongue_progress = 0.0
	_tongue_phase = "extend"
	current_state = State.ATTACK

	if tongue:
		tongue.visible = true

func _finish_attack():
	_target_drop = null
	_tongue_progress = 0.0
	_tongue_phase = ""

	if tongue:
		tongue.visible = false
		tongue.points = PackedVector2Array()

	current_state = State.IDLE

	if movement:
		movement.enable()

	_update_sprite()

func _collect_target():
	if _target_drop == null or not is_instance_valid(_target_drop):
		return

	if _target_drop.has_method("collect"):
		_target_drop.collect(false)

	_target_drop = null

	# Сразу скрываем язык
	if tongue:
		tongue.visible = false
		tongue.points = PackedVector2Array()

	current_state = State.SWALLOW
	_swallow_timer = swallow_duration
	_play("swallow")

# ============================================
# РИСОВАНИЕ ЯЗЫКА
# ============================================
func _get_tongue_base_local() -> Vector2:
	if sprite and sprite.flip_h:
		return Vector2(-tongue_base_offset.x, tongue_base_offset.y)
	return tongue_base_offset

func _draw_tongue(from_local: Vector2, to_local: Vector2):
	if tongue == null:
		return
	tongue.points = PackedVector2Array([from_local, to_local])

# ============================================
# ЗОНА ДОСЯГАЕМОСТИ
# ============================================
# Лягушка ест только капли внутри attack_radius. Слизни появляются
# случайно по всей ферме, поэтому без этого круга не видно, какая
# часть поля кормит её сама, а какая зависит от кликов игрока.
# Рисуем только в покое, чтобы не мешать анимации атаки.
func _draw():
	if current_state != State.IDLE:
		return
	draw_arc(Vector2.ZERO, attack_radius, 0.0, TAU, 64,
		Color(1.0, 1.0, 1.0, 0.5), 2.0, true)

# ============================================
# ФЛИП
# ============================================
func _update_flip():
	if sprite == null or movement == null:
		return
	if current_state != State.IDLE:
		return

	var dir = movement.direction if movement.is_walking() else movement.last_direction
	if abs(dir.x) < 0.1:
		return

	sprite.flip_h = dir.x < 0

func _on_move_state_changed(_is_walking: bool):
	_update_sprite()

# ============================================
# АНИМАЦИИ
# ============================================
func _update_sprite():
	if current_state != State.IDLE:
		return

	var is_walking := movement.is_walking() if movement else false
	_play("run" if is_walking else "idle")

func _play(anim_name: String):
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim_name):
		return

	# Анимации атаки играем всегда с начала
	if anim_name == "tongue" or anim_name == "swallow":
		sprite.play(anim_name)
	else:
		if sprite.animation != anim_name:
			sprite.play(anim_name)
