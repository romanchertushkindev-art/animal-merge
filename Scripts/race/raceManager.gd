class_name RaceManager
extends Node2D

# Гонка-раннер на три полосы.
# Препятствия — тайлы в TileMapLayer "Obstacles". У каждого тайла
# в Custom Data Layer "lane" записан номер полосы (0/1/2).
# Коллизия засчитывается только если полоса препятствия == полоса слизня.
# Любая коллизия = конец заезда.

const DIALOG_SCENE := preload("res://Resources/ui/dialogs/dialog_base.tscn")
const INVENTORY_CONTENT := preload("res://Resources/ui/dialogs/inventory/inventory_content.tscn")
const RESULT_CONTENT := preload("res://Scenes/race/race_result.tscn")
const RACER_SCENE := preload("res://Scenes/race/racer_slime.tscn")
const PIXEL_FONT := preload("res://Resources/fonts/pixelFont.ttf")

# ============================================
# ТРАССА
# ============================================
@export_group("Трасса")
@export var pixels_per_meter: float = 40.0

# ============================================
# СЛИЗЕНЬ
# ============================================
@export_group("Слизень")
@export var default_slime_id: String = "green"
@export var base_speed: float = 130.0
@export var speed_per_stat: float = 6.0

# ============================================
# НАГРАДА
# ============================================
@export_group("Награда")
@export var reward_seconds_per_meter: float = 0.28

# ============================================
# БОТЫ
# ============================================
@export_group("Боты")
@export var bot_count: int = 3              # сколько ботов-слаймов едут рядом

# ============================================
# ССЫЛКИ
# ============================================
@onready var slime: RacerSlime = $RacerSlime
@onready var obstacles_layer: TileMapLayer = $TileMap/Obstacles
@onready var finish_layer: TileMapLayer = $TileMap/Finish

# ============================================
# СОСТОЯНИЕ
# ============================================
var _selected_uid: int = -1
var _selected_slime_id: String = ""
var _running: bool = false
var _finish_x: float = 0.0
var _start_x: float = 0.0
var _selection_dialog: Dialog = null
var _result_dialog: Dialog = null
var _bots: Array[RacerSlime] = []
var _countdown: float = 0.0      # секунды до старта (3, 2, 1)
var _go_timer: float = 0.0       # сколько ещё показывать «GO!»
var _countdown_label: Label = null
var _bot_dash_lock: float = 0.0

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	_spawn_bots()
	_finish_x = finish_layer.global_position.x if finish_layer else 100000.0
	_setup_countdown()
	_open_selection()

## Лейбл отсчёта «3, 2, 1, GO!» поверх мира.
func _setup_countdown() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_override("font", PIXEL_FONT)
	_countdown_label.add_theme_font_size_override("font_size", 48)
	_countdown_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.1))
	_countdown_label.add_theme_constant_override("outline_size", 4)
	_countdown_label.text = ""
	canvas.add_child(_countdown_label)

# ============================================
# ВЫБОР ГОНЩИКА
# ============================================
func _open_selection() -> void:
	if GameState.get_all_instances().is_empty():
		_start_run(default_slime_id, -1)
		return

	var dialog: Dialog = DIALOG_SCENE.instantiate()
	var content: InventoryContent = INVENTORY_CONTENT.instantiate()
	content.select_mode = true

	add_child(dialog)
	dialog.set_title("Кто поедет?")
	dialog.open_with(content)

	content.slime_selected.connect(_on_slime_selected)
	dialog.closed.connect(_on_selection_closed)
	_selection_dialog = dialog

func _on_slime_selected(instance_uid: int, slime_id: String) -> void:
	_start_run(slime_id, instance_uid)
	if _selection_dialog and is_instance_valid(_selection_dialog):
		_selection_dialog.close()

func _on_selection_closed() -> void:
	if not _running:
		_start_run(default_slime_id, -1)

# ============================================
# СТАРТ
# ============================================
func _start_run(slime_id: String, uid: int) -> void:
	_selected_slime_id = slime_id
	_selected_uid = uid

	slime.apply_slime(slime_id, uid)
	_start_x = slime.position.x
	slime.speed = base_speed + slime.race_stat("race_speed") * speed_per_stat
	
	_running = true
	_countdown = 3.0
	_go_timer = 0.0

	print("[Race] Заезд: %s (uid %d), скорость %d px/с" % [slime_id, uid, roundi(slime.speed)])

## Спавнит ботов-слаймов: те же бегуны, но с is_bot = true.
## Стоят на той же линии (X), что и игрок, но строго на других полосах.
func _spawn_bots() -> void:
	# Свободные полосы — все, кроме полосы игрока
	var lanes: Array[int] = []
	for i in slime.lane_y.size():
		if i != slime.lane:
			lanes.append(i)
	if lanes.is_empty():
		return

	for i in bot_count:
		var bot: RacerSlime = RACER_SCENE.instantiate()
		bot.is_bot = true
		bot.slime_id = "blue" if i % 2 == 0 else "green"
		bot.lane_y = slime.lane_y
		bot.lane = lanes[i % lanes.size()]
		bot.speed = slime.speed * randf_range(0.85, 1.1)
		bot.obstacles_layer = obstacles_layer
		add_child(bot)
		bot.position.x = slime.position.x
		_bots.append(bot)

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(delta: float) -> void:
	if not _running:
		return

	# Отсчёт 3, 2, 1 — слизень и боты стоят
	if _countdown > 0.0:
		_countdown -= delta
		if _countdown <= 0.0:
			_countdown = 0.0
			_countdown_label.text = "GO!"
			slime.start()
			for bot in _bots:
				bot.start()
			_go_timer = 0.6
			_bot_dash_lock = 1.0
		else:
			_countdown_label.text = str(ceili(_countdown))
		return

	# Прячем «GO!» через мгновение
	if _go_timer > 0.0:
		_go_timer -= delta
		if _go_timer <= 0.0:
			_countdown_label.text = ""
			
	if _bot_dash_lock > 0.0:
		_bot_dash_lock -= delta
		for bot in _bots:
			bot.can_dash = false
		if _bot_dash_lock <= 0.0:
			for bot in _bots:
				bot.can_dash = true

	_check_hits()
	_check_slime_collisions()

	if slime.global_position.x >= _finish_x:
		_finish_run()

## Проверяем пересечение тела слизня с клетками TileMapLayer.
## Коллизия засчитывается только если полоса тайла == полоса слизня.
func _check_hits() -> void:
	if obstacles_layer == null:
		return
	if not slime.is_grounded():
		return

	var body := slime.get_body_rect()

	# Мировые координаты -> локальные тайлмапа -> клетки
	var tl_local := obstacles_layer.to_local(body.position)
	var br_local := obstacles_layer.to_local(body.end)

	var tl_map := obstacles_layer.local_to_map(tl_local)
	var br_map := obstacles_layer.local_to_map(br_local)

	# Перебираем все клетки, которые накрывает тело
	for x in range(tl_map.x, br_map.x + 1):
		for y in range(tl_map.y, br_map.y + 1):
			var coords := Vector2i(x, y)
			var data := obstacles_layer.get_cell_tile_data(coords)
			if data == null:
				continue

			# Полоса препятствия из Custom Data Layer "lane"
			var lane_v: Variant = data.get_custom_data("lane")
			var tile_lane: int = int(lane_v) if lane_v != null else -1
			if tile_lane == -1:
				continue  # тайл не препятствие (или слой не задан)
			if tile_lane != slime.lane:
				continue  # препятствие на другой полосе

			_on_tile_hit(coords, data)
			return  # одно препятствие за кадр

func _on_tile_hit(_coords: Vector2i, data: TileData) -> void:
	# Название препятствия — из Custom Data Layer "title".
	var title_v: Variant = data.get_custom_data("title")
	var title: String = str(title_v) if title_v != null and str(title_v) != "" else "Препятствие"

	_end_run(title)

## Столкновение слизней при деше: дешнувший врезается в другого —
## жертву оглушаем, дешнувшего плавно возвращаем на прежнюю полосу.
func _check_slime_collisions() -> void:
	var all: Array[RacerSlime] = [slime]
	for bot in _bots:
		all.append(bot)

	for a in all:
		if not a.is_dashing():
			continue
		var a_rect := a.get_body_rect()
		for b in all:
			if a == b:
				continue
			if a_rect.intersects(b.get_body_rect()) and a.can_dash:
				b.bump()
				a.return_to_lane(a.get_dash_from_lane())
				break

# ============================================
# КОНЕЦ ЗАЕЗДА
# ============================================
func _finish_run() -> void:
	if not _running:
		return
	_running = false
	slime.finish()

	var meters := _distance_m()
	var reward := _reward_for(meters)
	if reward > 0.0:
		GameState.add_slime(reward)

	print("[Race] Финиш: %.0f м, награда %d" % [meters, roundi(reward)])
	_show_result(meters, reward, "Финиш!")

func _end_run(reason: String) -> void:
	if not _running:
		return
	_running = false
	slime.die()

	var meters := _distance_m()
	var reward := _reward_for(meters)
	if reward > 0.0:
		GameState.add_slime(reward)

	print("[Race] Забег окончен на %.0f м, награда %d" % [meters, roundi(reward)])
	_show_result(meters, reward, reason)

# ============================================
# НАГРАДА
# ============================================
func _distance_px() -> float:
	return maxf(slime.global_position.x - _start_x, 0.0)

func _distance_m() -> float:
	return _distance_px() / maxf(pixels_per_meter, 1.0)

func _reward_for(meters: float) -> float:
	return GameState.get_farm_income_per_second() * meters * reward_seconds_per_meter

# ============================================
# ИТОГОВЫЙ ДИАЛОГ
# ============================================
func _show_result(meters: float, reward: float, reason: String) -> void:
	var dialog: Dialog = DIALOG_SCENE.instantiate()
	var content: Control = RESULT_CONTENT.instantiate()

	add_child(dialog)
	dialog.set_title("Забег окончен")
	dialog.open_with(content)

	content.setup(meters, reward, reason)
	content.retry_requested.connect(_on_retry)
	content.quit_requested.connect(_on_quit)
	dialog.closed.connect(dialog.queue_free)

	_result_dialog = dialog

func _clear_result_dialog() -> void:
	if _result_dialog and is_instance_valid(_result_dialog):
		_result_dialog.close()
	_result_dialog = null

func _on_retry() -> void:
	_clear_result_dialog()
	SceneTransition.change_scene("res://Scenes/race/race.tscn", 1)

func _on_quit() -> void:
	_clear_result_dialog()
	SceneTransition.change_scene("res://Scenes/main.tscn", 1)


func jump() -> void:
	pass # Replace with function body.
