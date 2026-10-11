class_name RaceManager
extends Node2D

# Гонка-раннер на три полосы.
#
# Уровень собран из TileMapLayer (Ground + Finish + Decor), слизень едет
# слева направо и переключает полосы, препятствия расставлены вручную.
# В начале заезда игрок выбирает слизня из инвентаря: его race_speed
# задаёт скорость, а остальные статы решают, пройдёт ли он тяжёлое
# препятствие. За дистанцию платят слизем — сумма считается от текущего
# дохода ферма, чтобы гонка была одинаково выгодна на любом этапе.
#
# Масштабируемость:
#   - новое препятствие = сцена на базе Obstacle (текстура/полоса/стат в
#     инспекторе, особая логика — переопределённый resolve/on_hit/_process);
#   - новая полоса = добавить Y в lane_y и расширить TileMapLayer;
#   - новый слизень = просто выбран в инвентаре, данные уже в SlimeData.

const DIALOG_SCENE := preload("res://Resources/ui/dialogs/dialog_base.tscn")
const INVENTORY_CONTENT := preload("res://Resources/ui/dialogs/inventory/inventory_content.tscn")
const RESULT_CONTENT := preload("res://Scenes/race/race_result.tscn")

# ============================================
# ТРАССА
# ============================================
@export_group("Трасса")
@export var lane_y: Array[float] = [245.0, 275.0, 305.0]
@export var start_x: float = 100.0          # откуда стартует слизень
@export var pixels_per_meter: float = 40.0  # перевод пикселей в метры

# ============================================
# СЛИЗЕНЬ
# ============================================
@export_group("Слизень")
@export var default_slime_id: String = "green"
@export var base_speed: float = 130.0       # px/с при race_speed = 0
@export var speed_per_stat: float = 6.0     # прибавка за единицу race_speed

# ============================================
# НАГРАДА
# ============================================
# Фиксированная сумма здесь не годится: 3600 слизи — копейки на десятой
# минуте и ничто на третьем часе. Привязка к доходу ферма держит гонку
# на одной и той же выгоде на любом этапе. Проверено симуляцией.
@export_group("Награда")
@export var reward_seconds_per_meter: float = 0.28

# ============================================
# ССЫЛКИ
# ============================================
@onready var slime: RacerSlime = $RacerSlime
@onready var obstacles_root: Node2D = $Obstacles
@onready var finish_layer: TileMapLayer = $Background/Ground/Finish
@onready var sky: Sprite2D = $Background/Sky
@onready var mountains_far: Sprite2D = $Background/MountainsFar
@onready var mountains: Sprite2D = $Background/Mountains

# ============================================
# СОСТОЯНИЕ
# ============================================
var _selected_uid: int = -1
var _selected_slime_id: String = ""
var _running: bool = false
var _finish_x: float = 0.0
var _selection_dialog: Dialog = null
var _result_dialog: Dialog = null

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	# Финиш — левый край шахматных тайлов Finish. Берём из сцены, чтобы
	# не хардкодить X в двух местах.
	_finish_x = finish_layer.global_position.x if finish_layer else 100000.0

	_setup_obstacles()
	_open_selection()

## Раздаёт препятствиям полосы, чтобы они встали ровно на свою дорожку
func _setup_obstacles() -> void:
	for child in obstacles_root.get_children():
		if child is Obstacle:
			(child as Obstacle).setup(lane_y)

# ============================================
# ВЫБОР ГОНЩИКА ИЗ ИНВЕНТАРЯ
# ============================================
func _open_selection() -> void:
	# Пустой инвентарь: нечего выбирать, едем на дефолтном слизне
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
	# Старт первым: close() шлёт closed, и закрытие без выбора уже увидит,
	# что _running = true, и не станет подменять выбранного слизня.
	if _selection_dialog and is_instance_valid(_selection_dialog):
		_selection_dialog.close()

func _on_selection_closed() -> void:
	# Диалог закрыли, так и не выбрав: едем на дефолтном, чтобы заезд
	# не завис в ожидании выбора.
	if not _running:
		_start_run(default_slime_id, -1)

# ============================================
# СТАРТ ЗАЕЗДА
# ============================================
func _start_run(slime_id: String, uid: int) -> void:
	_selected_slime_id = slime_id
	_selected_uid = uid

	slime.apply_slime(slime_id, uid)
	slime.lane_y = lane_y
	slime.global_position = Vector2(start_x, lane_y[clampi(slime.lane, 0, lane_y.size() - 1)])
	slime.speed = base_speed + slime.race_stat("race_speed") * speed_per_stat

	_running = true
	slime.start()

	print("[Race] Заезд: %s (uid %d), скорость %d px/с" % [slime_id, uid, roundi(slime.speed)])

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(_delta: float) -> void:
	if not _running:
		return

	_check_hits()

	if slime.global_position.x >= _finish_x:
		_finish_run()
		
## Ручная проверка прямоугольников вместо Area2D: порядок сигналов не
## важен, результат предсказуем, а полоса проверяется явно.
func _check_hits() -> void:
	var body := slime.get_body_rect()
	for child in obstacles_root.get_children():
		if not (child is Obstacle):
			continue
		var obstacle := child as Obstacle
		if not obstacle.blocks_lane(slime.lane):
			continue
		if body.intersects(obstacle.get_rect()):
			_on_obstacle_hit(obstacle)
			return

func _on_obstacle_hit(obstacle: Obstacle) -> void:
	var survived := obstacle.resolve(slime)
	obstacle.on_hit(slime)

	if survived:
		# Выдержал: препятствие ломается, бегун едет дальше
		obstacle.queue_free()
		slime.flash()
		return

	_end_run(_death_reason(obstacle))

func _death_reason(obstacle: Obstacle) -> String:
	if obstacle.required_stat == "":
		return obstacle.title
	return "%s: %s %d, нужно %d" % [
		obstacle.title,
		_stat_title(obstacle.required_stat),
		roundi(slime.race_stat(obstacle.required_stat)),
		roundi(obstacle.required_value),
	]

func _stat_title(stat: String) -> String:
	match stat:
		"race_speed": return "Скорость"
		"race_stamina": return "Выносливость"
		"race_grip": return "Сцепление"
		"race_weight": return "Сила"
		"race_luck": return "Удача"
	return stat

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
	return maxf(slime.global_position.x - start_x, 0.0)

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
	get_tree().reload_current_scene()

func _on_quit() -> void:
	_clear_result_dialog()
	get_tree().change_scene_to_file("res://Scenes/main.tscn")
