extends Node

# ============================================
# СИГНАЛЫ
# ============================================
signal slime_changed(new_value: float)
signal slimes_changed()
signal combo_changed(count: int, multiplier: float)

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
# slime_instances остаётся источником истины: от него зависит формат
# сохранения. Индексы ниже производные — только для быстрого поиска.
var slime_instances: Array = []
var _next_instance_uid: int = 1

# uid -> экземпляр (Dictionary хранится по ссылке, правки видны сразу)
var _by_uid: Dictionary = {}
# uid -> true для тех, кто сейчас на сцене
var _on_scene_uids: Dictionary = {}
# id -> сколько таких экземпляров на сцене
var _on_scene_by_id: Dictionary = {}

# ============================================
# НАСТРОЙКИ
# ============================================
const SAVE_PATH := "user://save.cfg"
const SAVE_INTERVAL := 5.0
const SELL_PRICE_RATIO := 0.5

# ============================================
# СБОР КАПЕЛЬ: ПАССИВ vs АКТИВ
# ============================================
# Капля, съеденная лягушкой, приносит FROG_PAYOUT от стоимости:
# лягушка — гарантированная подстилка, но заметно меньше ручного сбора.
# Капля, собранная кликом, — полная стоимость плюс бонус за комбо.
# Так клик всегда выгоднее автоматики, а у игрока появляется причина
# смотреть на экран, а не просто ждать.
const FROG_PAYOUT := 0.4

# Комбо: собрал каплю раньше, чем истёкло COMBO_WINDOW секунд после
# предыдущей — множитель вырос. Потолок x2.0.
const COMBO_WINDOW := 1.5
const COMBO_STEP := 0.1
const COMBO_MAX := 10

var combo: int = 0
var combo_timer: float = 0.0

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

	# Сброс комбо, если игрок перестал кликать
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			combo_changed.emit(combo, 1.0)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()

# ============================================
# ДОБАВИТЬ СЛИЗЬ
# ============================================
func add_slime(amount: float):
	slime += amount

# ============================================
# СБОР КАПЛИ
# ============================================
# Единственная точка, где капля превращается в деньги. by_hand = true —
# игрок кликнул, false — каплю съела лягушка.
# Возвращает фактически начисленную сумму, чтобы показать её игроку.
func collect_drop(value: float, by_hand: bool) -> float:
	var payout: float = value * FROG_PAYOUT

	if by_hand:
		combo_timer = COMBO_WINDOW
		combo = mini(combo + 1, COMBO_MAX)
		payout = value * get_combo_multiplier()
		combo_changed.emit(combo, get_combo_multiplier())

	add_slime(payout)
	return payout

func get_combo_multiplier() -> float:
	return 1.0 + COMBO_STEP * combo

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
		"on_scene": false      # ← по умолчанию в запасе
	})

	if not slimes.has(slime_id):
		slimes[slime_id] = {
			"count": 0,
			"level": 1,
			"unlocked": true
		}
	slimes[slime_id].count += 1

	_by_uid[uid] = slime_instances[slime_instances.size() - 1]

	slimes_changed.emit()
	return uid

func remove_instance_by_uid(uid: int) -> bool:
	var inst: Dictionary = _by_uid.get(uid, {})
	if inst.is_empty():
		return false

	var id = inst.id
	var was_on_scene = inst.get("on_scene", false)

	# Убираем из массива, сохраняя порядок
	for i in slime_instances.size():
		if slime_instances[i].uid == uid:
			slime_instances.remove_at(i)
			break

	_by_uid.erase(uid)
	if was_on_scene:
		_on_scene_uids.erase(uid)
		_dec_on_scene_count(id)

	# Синхронизируем счётчик типов
	if slimes.has(id) and slimes[id].count > 0:
		slimes[id].count -= 1

	slimes_changed.emit()
	return true

func get_instance_by_uid(uid: int) -> Dictionary:
	return _by_uid.get(uid, {})

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

	_rebuild_indexes()

# ============================================
# СБРОС
# ============================================
func reset_progress():
	slime = 100
	total_slime_earned = 0.0

	slimes.clear()
	slime_instances.clear()
	_next_instance_uid = 1
	_rebuild_indexes()

	combo = 0
	combo_timer = 0.0
	combo_changed.emit(combo, 1.0)

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
	var inst: Dictionary = _by_uid.get(uid, {})
	if inst.is_empty():
		return false

	var was: bool = inst.get("on_scene", false)
	if was == value:
		return true

	inst.on_scene = value
	if value:
		_on_scene_uids[uid] = true
		_inc_on_scene_count(inst.id)
	else:
		_on_scene_uids.erase(uid)
		_dec_on_scene_count(inst.id)

	slimes_changed.emit()
	return true

func is_on_scene(uid: int) -> bool:
	return _on_scene_uids.has(uid)

func get_on_scene_instances() -> Array:
	var result = []
	for uid in _on_scene_uids:
		result.append(_by_uid[uid])
	return result

func get_on_scene_count() -> int:
	return _on_scene_uids.size()

func get_on_scene_count_of(slime_id: String) -> int:
	return _on_scene_by_id.get(slime_id, 0)

func _inc_on_scene_count(slime_id: String):
	_on_scene_by_id[slime_id] = _on_scene_by_id.get(slime_id, 0) + 1

func _dec_on_scene_count(slime_id: String):
	var left = _on_scene_by_id.get(slime_id, 0) - 1
	if left > 0:
		_on_scene_by_id[slime_id] = left
	else:
		_on_scene_by_id.erase(slime_id)

# Пересобирает индексы из slime_instances.
# Вызывается после загрузки и сброса — источник истины один.
func _rebuild_indexes():
	_by_uid.clear()
	_on_scene_uids.clear()
	_on_scene_by_id.clear()

	for inst in slime_instances:
		var uid = inst.get("uid", -1)
		if uid < 0:
			continue
		_by_uid[uid] = inst
		# В старых сохранениях поля on_scene может не быть
		inst["on_scene"] = inst.get("on_scene", false)
		if inst.on_scene:
			_on_scene_uids[uid] = true
			_inc_on_scene_count(inst.id)
	
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
