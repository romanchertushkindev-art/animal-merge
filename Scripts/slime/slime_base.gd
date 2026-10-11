class_name SlimeBase
extends Area2D

# ============================================
# КОНСТАНТЫ
# ============================================
const GROUP_NAME := "slimes"
const DROP_SCENE := preload("res://Resources/slime/slime_drop.tscn")   # ← preload

const GRAB_HOLD_DELAY := 0.1
const IDLE_AFTER_COLLISION := 1.0

# ============================================
# ДАННЫЕ
# ============================================
@export var data: SlimeData
var instance_uid: int = -1

# ============================================
# НАСТРОЙКИ
# ============================================
@export_group("Столкновения")
@export var collision_push: float = 5.0
@export var collision_cooldown: float = 0.3

@export_group("Падение")
@export var fall_distance: float = 200.0
@export var idle_after_fall_duration: float = 1.0
@export var fall_speed: float = 4.0

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var trail_particles: GPUParticles2D = $SlimeTrail
@onready var movement: MovementComponent = $Movement

# ============================================
# СОСТОЯНИЯ (только GRABBED!)
# ============================================
enum State { FREE, GRABBED }
enum GrabStage { GRAB, HELD, FALL }

var current_state: State = State.FREE
var grab_stage: GrabStage = GrabStage.GRAB

# ============================================
# ТАЙМЕРЫ
# ============================================
var drop_timer: float = 0.0
var turn_cooldown: float = 0.0

# ============================================
# ЗАХВАТ
# ============================================
var grab_offset: Vector2 = Vector2.ZERO
var grab_timer: float = 0.0

# ============================================
# ПАДЕНИЕ
# ============================================
var fall_start: Vector2 = Vector2.ZERO
var fall_target: Vector2 = Vector2.ZERO
var fall_progress: float = 0.0

# ============================================
# РАЗМЕРЫ
# ============================================
var screen_size: Vector2
var half_sprite_size: Vector2 = Vector2(16, 16)

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	if data == null:
		push_error("[%s] data == null!" % name)
		return

	add_to_group(GROUP_NAME)
	_connect_signals()
	_apply_data()
	_setup_sizes()
	_start_drops()

	update_animation()

func _connect_signals():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	input_event.connect(_on_input_event)

	if movement:
		movement.move_state_changed.connect(_on_move_state_changed)
		movement.direction_changed.connect(_on_direction_changed)

func _apply_data():
	if data.sheet_texture:
		set_sheet_texture(data.sheet_texture)
	apply_trail_color()

func _setup_sizes():
	screen_size = get_viewport_rect().size
	if sprite.sprite_frames:
		var animations = sprite.sprite_frames.get_animation_names()
		if not animations.is_empty():
			var tex = sprite.sprite_frames.get_frame_texture(animations[0], 0)
			if tex:
				half_sprite_size = tex.get_size() / 2.0

func _start_drops():
	drop_timer = randf_range(data.min_drop_interval, data.max_drop_interval)
	print("[%s] drop_timer = %.2f" % [name, drop_timer])

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(delta):
	if data == null:
		return

	_tick_timers(delta)
	_update_drops(delta)

	if current_state == State.GRABBED:
		_process_grabbed(delta)
		return

	# Анимация НЕ обновляется каждый кадр: она зависит только от
	# состояния и направления, а они приходят через сигналы
	# move_state_changed / direction_changed (см. _connect_signals).

func _tick_timers(delta: float):
	if turn_cooldown > 0:
		turn_cooldown -= delta

func _on_move_state_changed(_is_walking: bool):
	update_animation()

func _on_direction_changed(_dir: Vector2):
	update_animation()

# ============================================
# СПАВН КАПЕЛЬ
# ============================================
func _update_drops(delta: float):
	if current_state == State.GRABBED:
		return

	drop_timer -= delta
	if drop_timer <= 0:
		drop_timer = randf_range(data.min_drop_interval, data.max_drop_interval)
		_spawn_drop()

func _spawn_drop():
	if data == null or DROP_SCENE == null:
		return

	var drop = DROP_SCENE.instantiate()
	if drop == null:
		return

	# Стоимость капли считается по уровню ЭТОГО экземпляра:
	# уровень свой у каждого слизня, а не у всего вида
	drop.value = _get_drop_value()
	if "drop_texture" in drop:
		drop.drop_texture = data.drop_texture
	if "drop_color" in drop:
		drop.drop_color = data.drop_color

	# Ставим локальную позицию ДО add_child: иначе капля один кадр
	# висит в левом верхнем углу (0,0), а потом телепортируется к слизню
	var parent := get_parent()
	drop.position = global_position - parent.global_position
	parent.add_child(drop)

func _get_drop_value() -> float:
	if instance_uid >= 0 and GameState:
		var value := GameState.get_instance_drop_value(instance_uid)
		if value > 0.0:
			return value
	return data.drop_value

# ============================================
# СТОЛКНОВЕНИЯ
# ============================================
func _on_area_entered(area: Area2D):
	if not area.is_in_group(GROUP_NAME):
		return
	if current_state == State.GRABBED:
		return
	if turn_cooldown > 0:
		return
	if not movement.is_walking():    # ← вместо current_state == RUN
		return

	turn_cooldown = collision_cooldown
	_turn_around(area.global_position)
	_start_idle_after_collision()

func _on_body_entered(body: Node2D):
	if body is Area2D:
		return
	if current_state == State.GRABBED:
		return
	if turn_cooldown > 0:
		return
	if not movement.is_walking():    # ← вместо current_state == RUN
		return

	turn_cooldown = collision_cooldown
	_turn_around(body.global_position)
	_start_idle_after_collision()

func _turn_around(other_position: Vector2):
	if movement == null:
		return

	movement.turn_around()

	var away = global_position - other_position
	if away == Vector2.ZERO:
		away = Vector2(randf_range(-1, 1), randf_range(-1, 1))

	global_position += away.normalized() * collision_push
	update_animation()

func _start_idle_after_collision():
	if movement:
		movement.force_idle(IDLE_AFTER_COLLISION)
	update_animation()

# ============================================
# ЗАХВАТ
# ============================================
func _on_input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grab_egg(get_global_mouse_position())

func grab_egg(mouse_position: Vector2):
	if current_state == State.GRABBED:
		return

	grab_offset = mouse_position - global_position
	current_state = State.GRABBED
	grab_stage = GrabStage.GRAB
	grab_timer = GRAB_HOLD_DELAY

	if movement:
		movement.disable()

	update_animation()

func _process_grabbed(delta: float):
	match grab_stage:
		GrabStage.GRAB:
			grab_timer -= delta
			if grab_timer <= 0:
				grab_stage = GrabStage.HELD
				update_animation()
			_move_with_mouse()

		GrabStage.HELD:
			_move_with_mouse()
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_release_egg()

		GrabStage.FALL:
			fall_progress += delta * fall_speed
			if fall_progress >= 1.0:
				fall_progress = 1.0
				global_position = fall_target
				_start_idle_after_fall()
			else:
				global_position = fall_start.lerp(fall_target, fall_progress)
			update_animation()

func _move_with_mouse():
	global_position = get_global_mouse_position() - grab_offset

func _release_egg():
	if current_state != State.GRABBED or grab_stage != GrabStage.HELD:
		return

	grab_stage = GrabStage.FALL
	fall_start = global_position
	fall_target = Vector2(
		global_position.x,
		min(global_position.y + fall_distance, screen_size.y - 50)
	)
	fall_progress = 0.0

	update_animation()

func _start_idle_after_fall():
	current_state = State.FREE

	if movement:
		movement.enable()
		movement.force_idle(idle_after_fall_duration)

	update_animation()

# ============================================
# АНИМАЦИИ
# ============================================
func get_cardinal_direction(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return "down"
	var norm = dir.normalized()
	if abs(norm.x) > abs(norm.y):
		return "right" if norm.x > 0 else "left"
	return "down" if norm.y > 0 else "up"

func update_animation():
	var anim_name := _get_animation_name()
	if anim_name.is_empty():
		return

	_update_trail_emitting(anim_name)
	_play_animation(anim_name)

func _get_animation_name() -> String:
	if current_state == State.GRABBED:
		match grab_stage:
			GrabStage.GRAB: return "catch"
			GrabStage.HELD: return "caught"
			GrabStage.FALL: return "fall"
		return ""

	var is_walking := movement.is_walking() if movement else false
	var dir_vec := movement.direction if is_walking else movement.last_direction

	var dir_str = get_cardinal_direction(dir_vec)
	var prefix = "run_" if is_walking else "idle_"
	return prefix + dir_str

func _update_trail_emitting(anim_name: String):
	if trail_particles == null:
		return
	trail_particles.emitting = anim_name.begins_with("run_")

func _play_animation(anim_name: String):
	if sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim_name):
		return

	if String(sprite.animation) == anim_name:
		return

	var play_once = (
		current_state == State.GRABBED and
		grab_stage == GrabStage.FALL
	)

	if play_once:
		sprite.play(anim_name, 1.0, false)
	else:
		sprite.play(anim_name)

# ============================================
# ЗАМЕНА СПРАЙТ-ЛИСТА
# ============================================
func set_sheet_texture(new_texture: Texture2D):
	if not sprite or not sprite.sprite_frames:
		return
	if new_texture == null:
		return

	sprite.sprite_frames = _get_frames_for(sprite.sprite_frames, new_texture)
	_refresh_animation()

# ============================================
# КЭШ SPRITEFRAMES
# ============================================
# Раньше на каждом спавне слизня SpriteFrames глубоко дублировался
# (duplicate(true) копирует все кадры и AtlasTexture заново).
# Сборка идёт один раз на пару «базовый набор + текстура»,
# дальше все слизни с одним атласом делят один ресурс.
# Анимация хранится в самом AnimatedSprite2D, а не в SpriteFrames,
# поэтому общий ресурс безопасен.
static var _frames_cache: Dictionary = {}

static func _get_frames_for(base_frames: SpriteFrames, new_texture: Texture2D) -> SpriteFrames:
	var key := "%s|%s" % [base_frames.resource_path, new_texture.resource_path]
	if key == "|":
		# Ресурсы без пути (встроенные в сцену) — ключ по идентификатору
		key = "%d|%d" % [base_frames.get_instance_id(), new_texture.get_instance_id()]

	if _frames_cache.has(key):
		return _frames_cache[key]

	var frames: SpriteFrames = base_frames.duplicate(true)

	for anim_name in frames.get_animation_names():
		var frame_count = frames.get_frame_count(anim_name)
		for i in frame_count:
			var old_tex = frames.get_frame_texture(anim_name, i)
			if old_tex == null:
				continue

			var new_atlas = AtlasTexture.new()
			new_atlas.atlas = new_texture

			if old_tex is AtlasTexture:
				new_atlas.region = old_tex.region
				new_atlas.margin = old_tex.margin
				new_atlas.filter_clip = old_tex.filter_clip
			else:
				new_atlas.region = Rect2(0, 0, old_tex.get_width(), old_tex.get_height())

			frames.set_frame(anim_name, i, new_atlas)

	_frames_cache[key] = frames
	return frames

func _refresh_animation():
	var old = sprite.animation
	sprite.animation = &""
	sprite.animation = old

# ============================================
# ЦВЕТ ТРЕЙЛА
# ============================================
func apply_trail_color():
	if not trail_particles or not trail_particles.process_material:
		return

	var material: ParticleProcessMaterial = trail_particles.process_material.duplicate(true)
	if material == null:
		return

	if data.trail_gradient:
		material.color_ramp = data.trail_gradient

	trail_particles.process_material = material
