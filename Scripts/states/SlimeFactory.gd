extends Node

# ============================================
# НАСТРОЙКИ
# ============================================
const SLIME_SCENE := preload("res://Resources/slime/slime.tscn")
const SLIMES_FOLDER := "res://Resources/slime/slimesData/"

@export var MAX_SLIMES_SLOT: int = 5

# ============================================
# БАЗА ДАННЫХ
# ============================================
var slime_db: Dictionary = {}      # { id: SlimeData }
var active_slimes: Array = []      # [SlimeBase, ...]

signal slime_count_changed(new_count: int)

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	load_all_slimes()
	print(slime_db)
	_print_db()

func _print_db():
	print("[SlimeFactory] Загружено: ", slime_db.size())
	for id in slime_db.keys():
		print("  • ", id, " — ", slime_db[id].display_name)

# ============================================
# ЗАГРУЗКА БАЗЫ
# ============================================
func load_all_slimes():
	slime_db.clear()

	var dir = DirAccess.open(SLIMES_FOLDER)
	if dir == null:
		push_error("[SlimeFactory] Не могу открыть: " + SLIMES_FOLDER)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path = SLIMES_FOLDER + file_name
				var data: SlimeData = load(path)
				if data == null:
					push_warning("[SlimeFactory] Не загрузилось: " + path)
				elif data.id.is_empty():
					push_warning("[SlimeFactory] Пустой id: " + path)
				else:
					slime_db[data.id] = data
		file_name = dir.get_next()
	dir.list_dir_end()

# ============================================
# СПАВН ПО ID (базовый)
# ============================================
func spawn_slime(slime_id: String, parent: Node, pos: Vector2) -> SlimeBase:
	if not slime_db.has(slime_id):
		push_error("[SlimeFactory] Нет слизня с id: " + slime_id)
		return null
	if parent == null:
		push_error("[SlimeFactory] parent == null")
		return null

	var slime: SlimeBase = SLIME_SCENE.instantiate()
	slime.data = slime_db[slime_id]

	parent.add_child(slime)
	slime.global_position = pos

	register_slime(slime)
	return slime

# ============================================
# СПАВН КОНКРЕТНОГО ЭКЗЕМПЛЯРА (с uid)
# ============================================
func spawn_instance(slime_id: String, uid: int, parent: Node, pos: Vector2) -> SlimeBase:
	var slime = spawn_slime(slime_id, parent, pos)
	if slime:
		slime.instance_uid = uid
	return slime

# ============================================
# СПАВН НОВОГО ЭКЗЕМПЛЯРА (создаёт uid в GameState)
# ============================================
func spawn_one_on_scene(slime_id: String, parent: Node) -> SlimeBase:
	print(">>> [SlimeFactory] spawn_one_on_scene: ", slime_id)
	if isSlimeSlotsFull():
		push_warning("[SlimeFactory] Слоты заняты")
		return null

	# Создаём экземпляр в GameState (uid + count++)
	var uid = GameState.create_instance(slime_id)
	print(">>> [SlimeFactory] получен uid=", uid)
	var pos = Vector2(
		randf_range(200, 900),
		randf_range(200, 500)
	)
	return spawn_instance(slime_id, uid, parent, pos)

# ============================================
# УБРАТЬ КОНКРЕТНЫЙ ЭКЗЕМПЛЯР СО СЦЕНЫ
# ============================================
func remove_instance_from_scene(uid: int) -> bool:
	for slime in active_slimes:
		if is_instance_valid(slime) and slime.instance_uid == uid:
			slime.queue_free()
			return true
	return false

# ============================================
# УБРАТЬ ЛЮБОЙ ЭКЗЕМПЛЯР ПО ID (для старых вызовов)
# ============================================
func remove_one_from_scene(slime_id: String) -> bool:
	for slime in active_slimes:
		if is_instance_valid(slime) and slime.data and slime.data.id == slime_id:
			slime.queue_free()
			return true
	return false

# ============================================
# ПРОВЕРКИ
# ============================================
func is_instance_on_scene(uid: int) -> bool:
	for slime in active_slimes:
		if is_instance_valid(slime) and slime.instance_uid == uid:
			return true
	return false

func get_active_count_of(slime_id: String) -> int:
	var count = 0
	for slime in active_slimes:
		if is_instance_valid(slime) and slime.data and slime.data.id == slime_id:
			count += 1
	return count

# ============================================
# РЕГИСТРАЦИЯ
# ============================================
func register_slime(slime: SlimeBase):
	if slime == null:
		return
	if slime in active_slimes:
		return

	active_slimes.append(slime)
	slime.tree_exiting.connect(_on_slime_removed.bind(slime))
	slime_count_changed.emit(active_slimes.size())

func _on_slime_removed(slime: SlimeBase):
	active_slimes.erase(slime)
	slime_count_changed.emit(active_slimes.size())

# ============================================
# СЧЁТЧИКИ СЛОТОВ
# ============================================
func get_active_count() -> int:
	active_slimes = active_slimes.filter(func(s): return is_instance_valid(s))
	return active_slimes.size()

func isSlimeSlotsFull() -> bool:
	return get_active_count() >= MAX_SLIMES_SLOT

func get_free_slots() -> int:
	return max(0, MAX_SLIMES_SLOT - get_active_count())

# ============================================
# ДАННЫЕ
# ============================================
func get_data(slime_id: String) -> SlimeData:
	if not slime_db.has(slime_id):
		push_warning("[SlimeFactory] Нет данных: " + slime_id)
		return null
	return slime_db[slime_id]

func get_all_ids() -> Array:
	return slime_db.keys()

func has_slime(slime_id: String) -> bool:
	return slime_db.has(slime_id)

func reload():
	load_all_slimes()
	_print_db()
