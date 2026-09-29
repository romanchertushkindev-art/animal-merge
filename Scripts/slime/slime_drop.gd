class_name SlimeDrop
extends Area2D

# ============================================
# ССЫЛКА НА СЦЕНУ ВСПЛЫВАЮЩЕГО ТЕКСТА
# ============================================
const FLOATING_TEXT_SCENE := preload("res://Resources/ui/floating_text.tscn")

# ============================================
# ДАННЫЕ (приходят от слизня)
# ============================================
@export var value: float = 1.0
@export var drop_color: Color = Color(0.3, 1.0, 0.4, 1.0)
@export var drop_texture: Texture2D

# ============================================
# НАСТРОЙКИ ПОЛЁТА
# ============================================
@export var flight_duration: float = 0.5
@export var pop_force: float = 200.0
@export var horizontal_spread: float = 60.0
@export var fall_gravity: float = 1800.0

# ============================================
# НАСТРОЙКИ ЛЕЖАНИЯ
# ============================================
@export var idle_duration: float = 3.0

# ============================================
# ССЫЛКИ
# ============================================
@onready var sprite: Sprite2D = $Sprite2D

# ============================================
# СОСТОЯНИЕ
# ============================================
enum Phase { FLYING, IDLE, DEAD }
var phase: Phase = Phase.FLYING

var velocity: Vector2 = Vector2.ZERO
var flight_timer: float = 0.0
var idle_timer: float = 0.0
var collected: bool = false

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Текстура
	if sprite and drop_texture:
		sprite.texture = drop_texture

	# Цвет
	self_modulate = drop_color

	# Начальная скорость: вверх + разброс
	velocity = Vector2(
		randf_range(-horizontal_spread, horizontal_spread),
		-pop_force
	)
	flight_timer = flight_duration
	
	add_to_group("slime_drops")

# ============================================
# ОСНОВНОЙ ЦИКЛ
# ============================================
func _process(delta):
	match phase:
		Phase.FLYING:
			process_flying(delta)
		Phase.IDLE:
			process_idle(delta)

# ============================================
# ФАЗА 1: ПОЛЁТ
# ============================================
func process_flying(delta):
	flight_timer -= delta

	velocity.y += fall_gravity * delta
	global_position += velocity * delta

	if flight_timer <= 0:
		start_idle()

# ============================================
# ФАЗА 2: ЛЕЖАНИЕ
# ============================================
func start_idle():
	phase = Phase.IDLE
	velocity = Vector2.ZERO
	idle_timer = idle_duration

func process_idle(delta):
	idle_timer -= delta

	# Плавное затухание за последнюю секунду
	if idle_timer < 1.0:
		modulate.a = max(idle_timer, 0.0)

	if idle_timer <= 0:
		phase = Phase.DEAD
		queue_free()

# ============================================
# КЛИК
# ============================================
func _on_input_event(viewport, event, shape_idx):
	if collected or phase == Phase.DEAD:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		collect()

func collect():
	if collected:
		return
	collected = true

	if GameState:
		GameState.add_slime(value)

	# Всплывающий текст над каплей
	spawn_floating_text()

	queue_free()

# ============================================
# ВСПЛЫВАЮЩИЙ ТЕКСТ
# ============================================
func spawn_floating_text():
	if FLOATING_TEXT_SCENE == null:
		return

	var ft = FLOATING_TEXT_SCENE.instantiate()
	if ft == null:
		return

	# 1. Сначала добавляем в корень сцены
	get_parent().add_child(ft)

	# 2. Устанавливаем позицию над каплей
	ft.global_position = global_position + Vector2(0, -20)

	# 3. ТОЛЬКО ТЕПЕРЬ запускаем setup — анимация начнётся с правильной позиции
	var label_text = "+" + GameState.format_number(value)
	ft.setup(label_text, drop_color)
	
# ============================================
# КУРСОР
# ============================================
func _on_mouse_entered():
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_mouse_exited():
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
