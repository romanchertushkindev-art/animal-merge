extends Node2D

# ============================================
# НАСТРОЙКИ
# ============================================
@export var spawn_area_min: Vector2 = Vector2(200, 200)
@export var spawn_area_max: Vector2 = Vector2(1000, 500)

# ============================================
# СОСТОЯНИЕ
# ============================================
# { uid: SlimeBase } — кто сейчас на сцене
var _slimes_on_scene: Dictionary = {}

# { upgrade_id: [Node2D, ...] } — жабы и прочие апгрейды на сцене
var _upgrades_on_scene: Dictionary = {}

var _is_updating: bool = false
var _is_updating_upgrades: bool = false

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	GameState.slimes_changed.connect(_on_slimes_changed)
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	print(12)
	sync()
	sync_upgrades()

func _on_slimes_changed():
	if not _is_updating:
		sync()

func _on_upgrades_changed():
	sync_upgrades()

# ============================================
# СИНХРОНИЗАЦИЯ: добавляет/удаляет только изменённых
# ============================================
func sync():
	if _is_updating:
		return
	_is_updating = true

	# Чистим мёртвые ссылки
	_cleanup_dead()

	# Кто ДОЛЖЕН быть на сцене (по uid)
	var should_be: Dictionary = {}
	for inst in GameState.get_on_scene_instances():
		should_be[inst.uid] = inst

	# 1. Удаляем тех, кто больше не должен быть
	var to_remove: Array = []
	for uid in _slimes_on_scene.keys():
		if not should_be.has(uid):
			to_remove.append(uid)

	for uid in to_remove:
		var slime = _slimes_on_scene[uid]
		if is_instance_valid(slime):
			slime.queue_free()
		_slimes_on_scene.erase(uid)

	# 2. Добавляем тех, кто должен быть, но ещё не на сцене
	for uid in should_be.keys():
		if _slimes_on_scene.has(uid):
			continue   # уже на сцене — не трогаем

		var inst = should_be[uid]
		var pos = _get_spawn_position()
		var slime = SlimeFactory.spawn_instance(inst.id, uid, self, pos)

		if slime:
			_slimes_on_scene[uid] = slime

	_is_updating = false
	print("[Farm] На сцене слизней: ", _slimes_on_scene.size())

# ============================================
# СИНХРОНИЗАЦИЯ АПГРЕЙДОВ
# ============================================
# На сцене должно быть ровно столько жаб, сколько их купил игрок.
# Покупка в магазине увеличивает счётчик в GameState и шлёт
# upgrades_changed — здесь это превращается в мгновенный спавн,
# без перезагрузки уровня.
func sync_upgrades() -> void:
	if _is_updating_upgrades:
		return
	_is_updating_upgrades = true

	for upgrade_id in UpgradeFactory.get_all_ids():
		_sync_upgrade(upgrade_id)

	_is_updating_upgrades = false
	print("[Farm] Апгрейдов на сцене: ", _count_upgrades_on_scene())

func _sync_upgrade(upgrade_id: String) -> void:
	var nodes: Array = _upgrades_on_scene.get(upgrade_id, [])

	# Чистим мёртвые ссылки: узел могли удалить из сцены иначе,
	# чем через сброс прогресса, и тогда счётчик разъехался бы
	var alive: Array = []
	for node in nodes:
		if is_instance_valid(node):
			alive.append(node)
	nodes = alive

	# 1. Подбираем узлы, уже стоящие на сцене (жаба, вручную
	#    поставленная в main.tscn) — иначе покупка добавит вторую
	var adopted := 0
	for child in get_children():
		if nodes.has(child):
			continue
		if not ("upgrade_id" in child):
			continue
		if child.upgrade_id != upgrade_id:
			continue
		nodes.append(child)
		UpgradeFactory.register_upgrade(child as Node2D)
		adopted += 1
	if adopted > 0:
		print("[Farm] Подобрал готовых узлов «%s»: %d" % [upgrade_id, adopted])

	# 2. Добираем до нужного количества
	var want: int = GameState.get_upgrade_count(upgrade_id)
	# Апгрейд без сцены ничего не ставит на ферму: множитель клика
	# меняет только цифры в интерфейсе. Спавнить ему нечего, и без
	# этой проверки каждая синхронизация сыпала бы ошибками.
	if want > 0 and nodes.is_empty() and UpgradeFactory.get_data(upgrade_id).scene == null:
		return
	while nodes.size() < want:
		var node := UpgradeFactory.spawn_upgrade(upgrade_id, self, _get_visible_spawn_position())
		if node == null:
			push_error("[Farm] Не удалось заспавнить «%s»" % upgrade_id)
			break
		nodes.append(node)
		print("[Farm] Спавн «%s» (%d/%d)" % [upgrade_id, nodes.size(), want])

	# 3. Лишние убираем (например, после сброса прогресса)
	while nodes.size() > want:
		var extra: Node = nodes.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()

	_upgrades_on_scene[upgrade_id] = nodes

func _count_upgrades_on_scene() -> int:
	var total := 0
	for nodes in _upgrades_on_scene.values():
		total += nodes.size()
	return total

# ============================================
# УТИЛИТЫ
# ============================================
func _cleanup_dead():
	var dead_uids: Array = []
	for uid in _slimes_on_scene.keys():
		if not is_instance_valid(_slimes_on_scene[uid]):
			dead_uids.append(uid)
	for uid in dead_uids:
		_slimes_on_scene.erase(uid)

func _get_spawn_position() -> Vector2:
	return Vector2(
		randf_range(spawn_area_min.x, spawn_area_max.x),
		randf_range(spawn_area_min.y, spawn_area_max.y)
	)

# Апгрейд покупают, глядя на ферму, — поэтому он появляется сразу
# в кадре. Слизи могут спавниться где угодно: их игрок увидит,
# когда они дойдут.
func _get_visible_spawn_position() -> Vector2:
	var size := get_viewport_rect().size
	var pad := 64.0
	return Vector2(
		randf_range(pad, maxf(pad + 1.0, size.x - pad)),
		randf_range(pad, maxf(pad + 1.0, size.y - pad))
	)
