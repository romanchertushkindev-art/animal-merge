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

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	_finish_x = finish_layer.global_position.x if finish_layer else 100000.0
	_open_selection()

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
	slime.start()
	_spawn_bots()
	print("[Race] Заезд: %s (uid %d), скорость %d px/с" % [slime_id, uid, roundi(slime.speed)])

## Спавнит ботов-слаймов: те же бегуны, но с is_bot = true.
## Едут рядом со своей скоростью, сами меняют полосы, ни с чем не сталкиваются.
func _spawn_bots() -> void:
	for i in bot_count:
		var bot: RacerSlime = RACER_SCENE.instantiate()
		bot.is_bot = true
		bot.slime_id = "blue" if i % 2 == 0 else "green"
		bot.lane_y = slime.lane_y
		bot.lane = randi() % slime.lane_y.size()
		bot.speed = slime.speed * randf_range(0.85, 1.1)
		add_child(bot)
		bot.position.x = slime.position.x - randf_range(60.0, 300.0)
		bot.start()

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(_delta: float) -> void:
	if not _running:
		return

	_check_hits()

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
