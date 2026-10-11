extends Node2D

class_name Runner

# ============================================
# СОСТОЯНИЕ
# ============================================
var _player: RunnerPlayer = null
var _obstacles_root: Node2D = null
var _finish_zone: Area2D = null
var _speed: float = 200.0
var _running: bool = true

# ============================================
# ССЫЛКИ
# ============================================
@onready var ground: TileMapLayer = $Ground
@onready var obstacles: Node2D = $Obstacles
@onready var finish: Area2D = $FinishZone
@onready var camera: Camera2D = $Camera2D

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready() -> void:
	# Настройки поля зрения
	var view_w: float = get_viewport_rect().size.x
	var view_h: float = get_viewport_rect().size.y

	# Настройка摄像机
	if camera:
		camera.limit_left = -1000
		camera.limit_right = view_w + 1000
		camera.limit_top = -1000
		camera.limit_bottom = view_h + 1000

	# Создаём игрока
	_player = RunnerPlayer.new()
	_player.speed = _speed
	_player.lane_y = [80.0, 180.0, 280.0]  # три полосы (можно читать из ground)
	_player.position = Vector2(50.0, _player.lane_y[1])
	add_child(_player)

	# Создаём препятствия (пример: три obstacles на разных полосах)
	_spawn_obstacle(Vector2(200.0, _player.lane_y[0]), "rock")
	_spawn_obstacle(Vector2(400.0, _player.lane_y[1]), "spikes")
	_spawn_obstacle(Vector2(600.0, _player.lane_y[2]), "boulder")

	# Финиш Zona (Area2D)
	if finish:
		finish.body_entered.connect(_on_finish_entered)

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _process(delta: float) -> void:
	if not _running:
		return

	_tick_obstacles(delta)

func _tick_obstacles(delta: float) -> void:
	if obstacles == null:
		return
	var view_w: float = get_viewport_rect().size.x
	for child in obstacles.get_children():
		child.position.x += _speed * delta
		if child.position.x > view_w + 60.0:
			child.queue_free()

# ============================================
# СОЗДАНИЕ ПРЕПЯТСТВИЯ
# ============================================
func _spawn_obstacle(position: Vector2, type: String) -> void:
	var obstacle_scene := preload("res://Scenes/race/obstacle.tscn") as PackedScene
	if obstacle_scene == null:
		push_error("[Runner] Не удалось загрузить сцену препятствия")
		return

	var obstacle = obstacle_scene.instantiate() as Obstacle
	obstacle.obstacle_type = type
	# Используем спрайты из гонки
	var tex := _get_texture_for_type(type)
	if tex:
		obstacle.texture = tex
	obstacle.position = position
	obstacles.add_child(obstacle)

func _get_texture_for_type(type: String) -> Texture2D:
	match type:
		"rock":
			return preload("res://Sprites/race/ob_rock.png")
		"spikes":
			return preload("res://Sprites/race/ob_stump.png")
		"boulder":
			return preload("res://Sprites/race/ob_crystal.png")
		_:
			return null

# ============================================
# КОЛЛИЗИОНЫ
# ============================================
func _on_finish_entered(body: Node2D) -> void:
	if body == _player:
		_finish_game()

func _finish_game() -> void:
	_running = false
	print("[Runner] Победа!")
	# Можно перезагрузить сцену или показать экран победы
	get_tree().reload_current_scene()

# ============================================
# ПРОВЕРКА СТОЛКНОВЕНИЯ (опционально)
# ============================================
func _check_collision() -> void:
	if _player == null or obstacles == null:
		return
	var player_rect := _player.get_body_rect()
	for child in obstacles.get_children():
		if child is Obstacle:
			var obs_rect := child.get_rect()
			if player_rect.intersects(obs_rect):
				_game_over()
				return

func _game_over() -> void:
	_running = false
	print("[Runner] Проигрыш")
	# Перезагрузка сцены после короткой паузы
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()