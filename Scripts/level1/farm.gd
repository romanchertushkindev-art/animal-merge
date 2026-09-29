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

var _is_updating: bool = false

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	GameState.slimes_changed.connect(_on_slimes_changed)
	print(12)
	sync()

func _on_slimes_changed():
	if not _is_updating:
		sync()

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
