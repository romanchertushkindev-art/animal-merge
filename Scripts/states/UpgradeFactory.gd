extends Node

# ============================================
# НАСТРОЙКИ
# ============================================
const UPGRADES_FOLDER := "res://Resources/upgrades/upgradesData/"
const GROUP_NAME := "upgrades"

# ============================================
# БАЗА ДАННЫХ
# ============================================
var upgrade_db: Dictionary = {}       # { id: UpgradeData }
var active_upgrades: Array = []       # узлы, которые сейчас на ферме
var _loaded: bool = false

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	load_all_upgrades()

# Реестр не должен зависеть от того, в каком порядке Godot поднял
# автозагрузки: GameState читает его прямо в своём _ready(), и если
# UpgradeFactory окажется позже, он увидит пустую базу и не заведёт
# стартовые апгрейды. Поэтому каждый доступ к данным сначала
# гарантирует, что папка прочитана.
func _ensure_loaded() -> void:
	if not _loaded:
		load_all_upgrades()

# ============================================
# ЗАГРУЗКА БАЗЫ
# ============================================
func load_all_upgrades():
	upgrade_db.clear()
	_loaded = true

	var dir = DirAccess.open(UPGRADES_FOLDER)
	if dir == null:
		push_error("[UpgradeFactory] Не могу открыть: " + UPGRADES_FOLDER)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path = UPGRADES_FOLDER + file_name
				var data: UpgradeData = load(path)
				if data == null:
					push_warning("[UpgradeFactory] Не загрузилось: " + path)
				elif data.id.is_empty():
					push_warning("[UpgradeFactory] Пустой id: " + path)
				else:
					upgrade_db[data.id] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# ============================================
# СПАВН НА ФЕРМУ
# ============================================
# Единственная точка, где апгрейд превращается в узел сцены.
# upgrade_id ставится ДО add_child, чтобы узел сразу был опознаваем.
func spawn_upgrade(upgrade_id: String, parent: Node, pos: Vector2) -> Node2D:
	_ensure_loaded()
	if not upgrade_db.has(upgrade_id):
		push_error("[UpgradeFactory] Нет апгрейда с id: " + upgrade_id)
		return null
	if parent == null:
		push_error("[UpgradeFactory] parent == null")
		return null

	var data: UpgradeData = upgrade_db[upgrade_id]
	if data.scene == null:
		push_error("[UpgradeFactory] У апгрейда «%s» нет сцены" % upgrade_id)
		return null

	var node := data.scene.instantiate() as Node2D
	if node == null:
		push_error("[UpgradeFactory] Не инстанцировалась сцена: " + upgrade_id)
		return null

	if "upgrade_id" in node:
		node.upgrade_id = upgrade_id

	# Баланс — из данных, иначе купленная жаба вышла бы с
	# дефолтами скрипта и не ела капли. Ставим ДО add_child:
	# жаба читает attack_interval уже в своём _ready().
	_apply_settings(node, data)

	parent.add_child(node)
	node.global_position = pos

	register_upgrade(node)
	return node

# ============================================
# ПРИМЕНЕНИЕ НАСТРОЕК
# ============================================
func _apply_settings(node: Node2D, data: UpgradeData) -> void:
	_set_if_exists(node, "attack_radius", data.attack_radius)
	_set_if_exists(node, "attack_interval", data.attack_interval)
	_set_if_exists(node, "tongue_speed", data.tongue_speed)
	_set_if_exists(node, "swallow_duration", data.swallow_duration)

func _set_if_exists(node: Node, property: String, value: float) -> void:
	if value == 0.0:
		return
	if not (property in node):
		return
	node.set(property, value)

# ============================================
# РЕГИСТРАЦИЯ
# ============================================
# Ферма зовёт это и для узлов, поставленных в сцену вручную,
# чтобы «на сцене: N» считало и их тоже.
func register_upgrade(node: Node2D) -> void:
	if node == null or node in active_upgrades:
		return

	node.add_to_group(GROUP_NAME)
	active_upgrades.append(node)
	node.tree_exiting.connect(_on_upgrade_removed.bind(node))

func _on_upgrade_removed(node: Node2D):
	active_upgrades.erase(node)

# ============================================
# ДАННЫЕ
# ============================================
func get_data(upgrade_id: String) -> UpgradeData:
	_ensure_loaded()
	if not upgrade_db.has(upgrade_id):
		push_warning("[UpgradeFactory] Нет данных: " + upgrade_id)
		return null
	return upgrade_db[upgrade_id]

func get_all_ids() -> Array:
	_ensure_loaded()
	return upgrade_db.keys()

func has_upgrade(upgrade_id: String) -> bool:
	_ensure_loaded()
	return upgrade_db.has(upgrade_id)

# Сколько таких узлов реально стоит на ферме прямо сейчас
func get_on_scene_count(upgrade_id: String) -> int:
	active_upgrades = active_upgrades.filter(func(n): return is_instance_valid(n))

	var count := 0
	for node in active_upgrades:
		if "upgrade_id" in node and node.upgrade_id == upgrade_id:
			count += 1
	return count

func reload():
	load_all_upgrades()
