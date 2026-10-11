extends Node

# ============================================
# СИГНАЛЫ
# ============================================
signal slime_changed(new_value: float)
signal slimes_changed()
signal upgrades_changed()
signal click_multiplier_changed(multiplier: float, time_left: float)

# ============================================
# ВАЛЮТА
# ============================================
# Стартовый капитал: ровно столько, сколько стоит первый зелёный
# слизень. Без стартового слизня на ферме — игрок сам покупает первого.
const START_SLIME := 100.0

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
# [ { "id": "green", "uid": 1, "level": 1, "on_scene": true }, ... ]
# slime_instances остаётся источником истины: от него зависит формат
# сохранения. Индексы ниже производные — только для быстрого поиска.
# Уровень свой у каждого экземпляра: прокачивается конкретный слизень,
# а не весь вид.
var slime_instances: Array = []
var _next_instance_uid: int = 1

# uid -> экземпляр (Dictionary хранится по ссылке, правки видны сразу)
var _by_uid: Dictionary = {}
# uid -> true для тех, кто сейчас на сцене
var _on_scene_uids: Dictionary = {}
# id -> сколько таких экземпляров на сцене
var _on_scene_by_id: Dictionary = {}

# ============================================
# АПГРЕЙДЫ
# ============================================
# { "frog": { "count": 1, "unlocked": true }, ... }
# В отличие от слизней у апгрейда нет запаса: count — это ровно
# столько жаб должно стоять на ферме прямо сейчас. Покупка в
# магазине увеличивает count, ферма ловит upgrades_changed и
# сразу доставляет жабу на сцену.
var upgrades: Dictionary = {}

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

# ============================================
# МНОЖИТЕЛЬ КЛИКА
# ============================================
# Множителя нет, пока не куплен апгрейд: клик всегда приносит ровно
# каплю. После покупки клики поднимают множитель ступеньками от x1.0
# до x2.0, а если перестать собирать — он ступенька падает. Ступенька
# на экране это одновременно и отсчёт: пока собираешь, он не кончится.
const MULTIPLIER_ID := "multiplier"
const MULTIPLIER_STEP := 0.1
const MULTIPLIER_MIN := 1.0
const MULTIPLIER_MAX := 2.0
# Столько секунд есть на одну ступеньку. Раньше окно комбо было 1.5 с:
# множитель падал раньше, чем игрок успевал его увидеть, и отсчёт
# показывать было бессмысленно.
const MULTIPLIER_STEP_SECONDS := 6.0

var click_multiplier: float = MULTIPLIER_MIN
var click_multiplier_timer: float = 0.0
# Последняя показанная целая секунда: событие нужно только когда
# цифра на экране реально меняется, а не 60 раз в секунду
var _multiplier_second_shown: int = -1

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

	_update_click_multiplier(delta)

# Таймер идёт только пока есть что терять: при x1.0 отсчёт «до падения»
# показывать незачем, и падать там нечему.
func _update_click_multiplier(delta: float) -> void:
	if not is_multiplier_unlocked() or click_multiplier <= MULTIPLIER_MIN:
		return

	click_multiplier_timer -= delta
	var left := ceili(click_multiplier_timer)
	if left != _multiplier_second_shown:
		_multiplier_second_shown = left
		click_multiplier_changed.emit(click_multiplier, click_multiplier_timer)

	if click_multiplier_timer <= 0.0:
		click_multiplier = maxf(click_multiplier - MULTIPLIER_STEP, MULTIPLIER_MIN)
		click_multiplier_timer = MULTIPLIER_STEP_SECONDS
		_multiplier_second_shown = -1
		click_multiplier_changed.emit(click_multiplier, click_multiplier_timer)

## Множитель появляется только после покупки апгрейда
func is_multiplier_unlocked() -> bool:
	return get_upgrade_count(MULTIPLIER_ID) > 0

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
		if is_multiplier_unlocked():
			# Каждый собранный клик поднимает ступеньку и отодвигает падение
			click_multiplier = minf(click_multiplier + MULTIPLIER_STEP, MULTIPLIER_MAX)
			click_multiplier_timer = MULTIPLIER_STEP_SECONDS
			_multiplier_second_shown = -1
			click_multiplier_changed.emit(click_multiplier, click_multiplier_timer)
		# Ставку жабы надо перебить ВСЕГДА, а не только при купленном
		# апгрейде: иначе клик без множителя платил бы 40% от капли
		payout = value * click_multiplier

	# Без этой строки сумма считается, но в валюту не попадает:
	# плавающий текст показывает payout, а слизи не прибавляется
	add_slime(payout)
	return payout

func get_combo_multiplier() -> float:
	return click_multiplier

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
# АПГРЕЙДЫ (жабы и прочие помощники)
# ============================================
func has_upgrade(upgrade_id: String) -> bool:
	return upgrades.has(upgrade_id) and upgrades[upgrade_id].unlocked

func get_upgrade_count(upgrade_id: String) -> int:
	if not upgrades.has(upgrade_id):
		return 0
	return upgrades[upgrade_id].count

# Цена следующей покупки: первая копия стоит unlock_price,
# каждая следующая — price (как у слизней).
func get_upgrade_price(upgrade_id: String) -> float:
	var data = UpgradeFactory.get_data(upgrade_id)
	if data == null:
		return 0.0
	return data.get_copy_price(get_upgrade_count(upgrade_id))

# Покупка в магазине. Деньги списываются здесь же, чтобы карточка
# не могла заплатить дважды. Возвращает false, если не хватило
# слизи или упёрлись в max_count.
func buy_upgrade(upgrade_id: String) -> bool:
	var data = UpgradeFactory.get_data(upgrade_id)
	if data == null:
		return false

	var count := get_upgrade_count(upgrade_id)
	if data.max_count > 0 and count >= data.max_count:
		push_warning("[GameState] buy_upgrade: лимит «%s» (%d)" % [upgrade_id, data.max_count])
		return false

	if not spend_slime(data.get_effective_price(has_upgrade(upgrade_id))):
		return false

	upgrades[upgrade_id] = {
		"count": count + 1,
		"unlocked": true
	}
	upgrades_changed.emit()
	print("[GameState] Куплен апгрейд: ", upgrade_id, " (", count + 1, ")")
	return true

# Стартовые слизни. Без них новая игра начинается с нулём денег и
# без единого слизня на ферме: до первой капли заработать негде,
# а купить первого слизня тоже не на что — тупик. Стартовые ставим
# только те, которых ещё нет в сохранении, иначе сброс и старые
# сейвы ломались бы.
func _apply_starter_slimes() -> void:
	for slime_id in SlimeFactory.get_all_ids():
		var data: SlimeData = SlimeFactory.get_data(slime_id)
		if data == null or data.starter_count <= 0:
			continue

		var need: int = data.starter_count - get_slime_count(slime_id)
		for i in need:
			var uid := create_instance(slime_id)
			set_on_scene(uid, true)
			print("[GameState] Стартовый слизень: ", slime_id, " (uid ", uid, ")")

# Стартовые апгрейды. Ставим только те, которых ещё нет в сохранении:
# иначе сброс прогресса и старые сейвы ломались бы.
func _apply_starter_upgrades() -> void:
	for upgrade_id in UpgradeFactory.get_all_ids():
		if upgrades.has(upgrade_id):
			continue
		var data: UpgradeData = UpgradeFactory.get_data(upgrade_id)
		if data == null or data.starter_count <= 0:
			continue
		upgrades[upgrade_id] = {
			"count": data.starter_count,
			"unlocked": true
		}
		print("[GameState] Стартовый апгрейд: ", upgrade_id, " x", data.starter_count)

# ============================================
# ЭКЗЕМПЛЯРЫ (конкретные слизни)
# ============================================
func create_instance(slime_id: String) -> int:
	var uid = _next_instance_uid
	_next_instance_uid += 1

	slime_instances.append({
		"id": slime_id,
		"uid": uid,
		"level": 1,
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
# ЦЕНЫ (экспоненциальные)
# ============================================
# Раньше цена копии была фиксированной, а зелёный ронял по 1000 слизи
# за каплю: одна капля — и весь магазин куплен. Теперь цена растёт
# на price_growth за каждую уже купленную копию, а уровень — на
# level_growth за каждый текущий.
func get_copy_price(slime_id: String) -> float:
	var data := SlimeFactory.get_data(slime_id)
	if data == null:
		return 0.0
	return data.get_copy_price(get_slime_count(slime_id))

func get_level_price(uid: int) -> float:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return 0.0
	var data := SlimeFactory.get_data(inst.id)
	if data == null:
		return 0.0
	return data.get_level_price(get_instance_level(uid))

# ============================================
# УРОВНИ ЭКЗЕМПЛЯРА
# ============================================
func get_instance_level(uid: int) -> int:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return 1
	return maxi(int(inst.get("level", 1)), 1)

func is_max_level(uid: int) -> bool:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return true
	var data := SlimeFactory.get_data(inst.id)
	if data == null:
		return true
	return get_instance_level(uid) >= data.max_level

## Покупка уровня. Деньги списываются здесь же, чтобы карточка
## инвентаря не могла заплатить дважды.
func level_up_instance(uid: int) -> bool:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return false

	var data := SlimeFactory.get_data(inst.id)
	if data == null:
		return false

	var level := get_instance_level(uid)
	if level >= data.max_level:
		return false

	if not spend_slime(data.get_level_price(level)):
		return false

	inst.level = level + 1
	slimes_changed.emit()
	print("[GameState] Уровень %d → %d (uid %d)" % [level, level + 1, uid])
	return true

## Сколько стоит капля этого экземпляра с учётом его уровня
func get_instance_drop_value(uid: int) -> float:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return 0.0
	var data := SlimeFactory.get_data(inst.id)
	if data == null:
		return 0.0
	return data.get_drop_value(get_instance_level(uid))

## Гонковый стат экземпляра с учётом его уровня. stat — имя из
## SlimeData.RACE_STATS. Гонка спрашивает статы именно здесь, иначе
## прокачка на ферме осталась бы незаметной на трассе.
func get_instance_race_stat(uid: int, stat: String) -> float:
	var inst := get_instance_by_uid(uid)
	if inst.is_empty():
		return 0.0
	var data := SlimeFactory.get_data(inst.id)
	if data == null:
		return 0.0
	return data.get_race_stat(stat, get_instance_level(uid))

## Сколько ферма зарабатывает в секунду прямо сейчас: сумма стоимостей
## капель всех слизней на сцене, делённая на их интервал.
## Гонка считает от этой величины награду за забег — фиксированная
## сумма там не годится: она либо ломает раннюю кривую, либо на
## поздней не заметна вовсе.
func get_farm_income_per_second() -> float:
	var total := 0.0
	for uid in _on_scene_uids.keys():
		var inst: Dictionary = _by_uid.get(uid, {})
		if inst.is_empty():
			continue
		var data := SlimeFactory.get_data(inst.id)
		if data == null:
			continue
		var interval: float = (data.min_drop_interval + data.max_drop_interval) * 0.5
		total += get_instance_drop_value(int(uid)) / maxf(interval, 0.1)

	# Апгрейды собирают часть капель сами, но платят за них поменьше
	for upgrade_id in upgrades.keys():
		var count := get_upgrade_count(upgrade_id)
		if count <= 0:
			continue
		var udata := UpgradeFactory.get_data(upgrade_id)
		if udata == null or udata.income_coverage <= 0.0:
			continue
		total *= 1.0 + float(count) * udata.income_coverage * FROG_PAYOUT

	return total

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
	cfg.set_value("game", "upgrades", upgrades)
	cfg.set_value("game", "click_multiplier", click_multiplier)
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
		slime = START_SLIME
		return

	slime = cfg.get_value("game", "slime", 0.0)
	# Множитель не сохраняем: он и так падает, а через паузу вставать
	# на середину шкалы без причины незачем. Стартует с x1.0.
	click_multiplier = clampf(cfg.get_value("game", "click_multiplier", MULTIPLIER_MIN),
		MULTIPLIER_MIN, MULTIPLIER_MAX)
	total_slime_earned = cfg.get_value("game", "total_slime_earned", 0.0)

	slimes = cfg.get_value("game", "slimes", {})
	slime_instances = cfg.get_value("game", "slime_instances", [])
	upgrades = cfg.get_value("game", "upgrades", {})
	_next_instance_uid = cfg.get_value("game", "next_instance_uid", 1)

	_rebuild_indexes()

# ============================================
# СБРОС
# ============================================
func reset_progress():
	# Стартовый капитал без стартовых слизней и апгрейдов: игрок
	# покупает первого слизня сам — на 100 слизи хватает ровно на
	# первого зелёного (unlock_price = 100).
	slime = START_SLIME
	total_slime_earned = 0.0

	slimes.clear()
	slime_instances.clear()
	_next_instance_uid = 1
	_rebuild_indexes()

	upgrades.clear()

	click_multiplier = MULTIPLIER_MIN
	click_multiplier_timer = 0.0
	_multiplier_second_shown = -1
	click_multiplier_changed.emit(click_multiplier, click_multiplier_timer)

	save_game()
	slimes_changed.emit()
	upgrades_changed.emit()

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
	elif n >= 1.0:
		return str(int(n))
	# Ниже единицы округлять нельзя: жаба платит долю капли, и
	# int(0.4) превращал честную награду в «+0»
	return "%.1f" % n

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
		# В старых сохранениях полей level и on_scene может не быть
		inst["level"] = maxi(int(inst.get("level", 1)), 1)
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
