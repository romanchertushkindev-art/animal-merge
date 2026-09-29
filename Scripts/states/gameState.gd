extends Node

# ============================================
# СИГНАЛЫ
# ============================================
signal slime_changed(new_value: float)
signal slimes_changed()

# ============================================
# ВАЛЮТА
# ============================================
var slime: float = 0.0:
	set(value):
		slime = value
		slime_changed.emit(slime)

var total_slime_earned: float = 0.0

# ============================================
# КОЛЛЕКЦИЯ ТИПОВ (для магазина)
# ============================================
# { "green": { "count": 2, "level": 1, "unlocked": true }, ... }
var slimes: Dictionary = {}

# ============================================
# ЭКЗЕМПЛЯРЫ СЛИЗНЕЙ
# ============================================
# [ { "id": "green", "uid": 1 }, { "id": "green", "uid": 2 }, ... ]
var slime_instances: Array = []
var _next_instance_uid: int = 1

# ============================================
# НАСТРОЙКИ
# ============================================
const SAVE_PATH := "user://save.cfg"
const SAVE_INTERVAL := 5.0
const SELL_PRICE_RATIO := 0.5

var save_timer: float = 0.0

# ============================================
# ЖИЗНЕННЫЙ ЦИКЛ
# ============================================
func _ready():
	load_game()

func _process(delta):
	# Автосохранение
	save_timer += delta
	if save_timer >= SAVE_INTERVAL:
		save_timer = 0.0
		save_game()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

# ============================================
# ДОБАВИТЬ СЛИЗЬ
# ============================================
func add_slime(amount: float):
	slime += amount

# ============================================
# ТРАТА
# ============================================
func spend_slime(amount: float) -> bool:
	if slime >= amount:
		slime -= amount
		return true
	return false

# ============================================
# ТИПЫ СЛИЗНЕЙ (коллекция)
# ============================================
func unlock_slime(slime_id: String):
	if slimes.has(slime_id):
		return
	slimes[slime_id] = {
		"count": 0,
		"level": 1,
		"unlocked": true
	}
	slimes_changed.emit()
	print("[GameState] Разблокирован тип: ", slime_id)

func add_slime_instance(slime_id: String):
	if not slimes.has(slime_id):
		unlock_slime(slime_id)
		return
	slimes[slime_id].count += 1
	slimes_changed.emit()

func remove_slime_instance(slime_id: String) -> bool:
	if not slimes.has(slime_id):
		return false
	if slimes[slime_id].count <= 0:
		return false
	slimes[slime_id].count -= 1
	slimes_changed.emit()
	return true

func has_slime(slime_id: String) -> bool:
	return slimes.has(slime_id) and slimes[slime_id].unlocked

func get_slime_count(slime_id: String) -> int:
	if not slimes.has(slime_id):
		return 0
	return slimes[slime_id].count

func get_all_owned_ids() -> Array:
	var result = []
	for id in slimes.keys():
		if slimes[id].unlocked:
			result.append(id)
	return result

# ============================================
# ЭКЗЕМПЛЯРЫ (конкретные слизни)
# ============================================
func create_instance(slime_id: String) -> int:
	var uid = _next_instance_uid
	_next_instance_uid += 1

	slime_instances.append({
		"id": slime_id,
		"uid": uid,
		"on_scene": false      # ← НОВОЕ: по умолчанию в запасе
	})

	if not slimes.has(slime_id):
		slimes[slime_id] = {
			"count": 0,
			"level": 1,
			"unlocked": true
		}
	slimes[slime_id].count += 1

	slimes_changed.emit()
	return uid
	
func remove_instance_by_uid(uid: int) -> bool:
	for i in slime_instances.size():
		if slime_instances[i].uid == uid:
			var id = slime_instances[i].id
			slime_instances.remove_at(i)

			# Синхронизируем счётчик типов
			if slimes.has(id) and slimes[id].count > 0:
				slimes[id].count -= 1

			slimes_changed.emit()
			return true
	return false

func get_instance_by_uid(uid: int) -> Dictionary:
	for inst in slime_instances:
		if inst.uid == uid:
			return inst
	return {}

func get_all_instances() -> Array:
	return slime_instances

# ============================================
# ПРОДАЖА
# ============================================
func get_sell_price(slime_id: String) -> float:
	var data = SlimeFactory.get_data(slime_id)
	if data == null:
		return 0.0
	return data.price * SELL_PRICE_RATIO

# ============================================
# СОХРАНЕНИЕ
# ============================================
func save_game():
	var cfg = ConfigFile.new()
	cfg.set_value("game", "slime", slime)
	cfg.set_value("game", "slimes", slimes)
	cfg.set_value("game", "slime_instances", slime_instances)
	cfg.set_value("game", "next_instance_uid", _next_instance_uid)
	cfg.set_value("game", "last_save_time", Time.get_unix_time_from_system())
	cfg.save(SAVE_PATH)

# ============================================
# ЗАГРУЗКА + ОФЛАЙН-ПРОГРЕСС
# ============================================
func load_game():
	var cfg = ConfigFile.new()
	var err = cfg.load(SAVE_PATH)

	if err != OK:
		print("[GameState] Нет сохранения — новый запуск")
		return

	slime = cfg.get_value("game", "slime", 0.0)
	total_slime_earned = cfg.get_value("game", "total_slime_earned", 0.0)

	slimes = cfg.get_value("game", "slimes", {})
	slime_instances = cfg.get_value("game", "slime_instances", [])
	_next_instance_uid = cfg.get_value("game", "next_instance_uid", 1)

# ============================================
# СБРОС
# ============================================
func reset_progress():
	slime = 100
	total_slime_earned = 0.0

	slimes.clear()
	slime_instances.clear()
	_next_instance_uid = 1

	save_game()
	slimes_changed.emit()

	print("[GameState] Прогресс сброшен")

# ============================================
# УТИЛИТЫ
# ============================================
func format_number(n: float) -> String:
	if n >= 1_000_000_000:
		return "%.2fB" % (n / 1_000_000_000.0)
	elif n >= 1_000_000:
		return "%.2fM" % (n / 1_000_000.0)
	elif n >= 1_000:
		return "%.2fK" % (n / 1_000.0)
	return str(int(n))

func format_time(seconds: float) -> String:
	var s = int(seconds)
	var h = s / 3600
	var m = (s % 3600) / 60
	var sec = s % 60
	if h > 0:
		return "%dh %dm %ds" % [h, m, sec]
	elif m > 0:
		return "%dm %ds" % [m, sec]
	return "%ds" % sec
	
# ============================================
# УПРАВЛЕНИЕ "НА СЦЕНЕ / В ЗАПАСЕ"
# ============================================
func set_on_scene(uid: int, value: bool) -> bool:
	for inst in slime_instances:
		if inst.uid == uid:
			inst.on_scene = value
			slimes_changed.emit()
			return true
	return false

func is_on_scene(uid: int) -> bool:
	for inst in slime_instances:
		if inst.uid == uid:
			return inst.get("on_scene", false)
	return false

func get_on_scene_instances() -> Array:
	var result = []
	for inst in slime_instances:
		if inst.get("on_scene", false):
			result.append(inst)
	return result

func get_on_scene_count() -> int:
	return get_on_scene_instances().size()
	
func get_on_scene_count_of(slime_id: String) -> int:
	var count = 0
	for inst in slime_instances:
		if inst.id == slime_id and inst.get("on_scene", false):
			count += 1
	return count
	
func sell_instance(uid: int) -> bool:
	# Находим экземпляр
	var inst = get_instance_by_uid(uid)
	if inst.is_empty():
		push_warning("[GameState] sell_instance: нет uid %d" % uid)
		return false

	# Нельзя продать, если на сцене
	if inst.get("on_scene", false):
		push_warning("[GameState] sell_instance: слизень на сцене")
		return false

	# Начисляем деньги
	var price = get_sell_price(inst.id)
	slime += price

	# Удаляем из инстансов
	remove_instance_by_uid(uid)

	return true
