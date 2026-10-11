class_name Obstacle
extends Node2D

# База препятствия гонки. Уровень собирается из TileMapLayer, а
# препятствия расставляются вручную поверх земли — поэтому каждое
# препятствие настраивается прямо в инспекторе без правки кода:
#   - texture          — как выглядит
#   - lane / lane_span — какую полосу (или две) перекрывает
#   - required_stat    — какой стат нужен, чтобы пройти (пусто = смерть)
#
# Для особой логики или анимации наследуйся от этого класса и
# переопредели resolve() (пропустить/убить), on_hit() (отклик на касание)
# или _process() (движение, мигание и т.п.).

signal hit(player: RacerSlime)

# ============================================
# ВИД И ГЕОМЕТРИЯ
# ============================================
@export_group("Вид и геометрия")
@export var texture: Texture2D
@export var hitbox_scale: Vector2 = Vector2(0.75, 0.85)

# ============================================
# ПОЛОСА
# ============================================
@export_group("Полоса")
@export var lane: int = 0          # первая перекрываемая полоса
@export var lane_span: int = 1     # сколько полос подряд перекрывает (1 или 2)

# ============================================
# ПРОВЕРКА СТАТА
# ============================================
# Пустой required_stat означает «касание смертельно». Если стат задан,
# слизень проходит, когда его стат не меньше required_value, — иначе
# забег обрывается. Так камень и шипы различаются одними полями,
# а не отдельными скриптами.
@export_group("Проверка")
@export var title: String = "Препятствие"
@export var required_stat: String = ""
@export var required_value: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

var _size: Vector2 = Vector2.ZERO
var _lane_y: Array[float] = []

func _ready() -> void:
	if texture == null:
		push_error("[Obstacle] Не задана текстура")
		return

	_size = texture.get_size()
	sprite.texture = texture
	# Текстура выровнена по низу: низ по центру попадает в начало координат
	sprite.offset = Vector2(-_size.x * 0.5, -_size.y)

## Менеджер передаёт полосы, чтобы препятствие встало ровно на свою полосу
func setup(lane_y: Array[float]) -> void:
	_lane_y = lane_y
	if not _lane_y.is_empty():
		position.y = _lane_y[clampi(lane, 0, _lane_y.size() - 1)]

## Прямоугольник препятствия в мировых координатах
func get_rect() -> Rect2:
	var s := _size * hitbox_scale
	return Rect2(global_position - Vector2(s.x * 0.5, s.y), s)

## Перекрывает ли препятствие полосу l
func blocks_lane(l: int) -> bool:
	return l >= lane and l < lane + lane_span

## Прошёл ли слизень: true — выжил и сломал препятствие, false — умер.
## Переопределяется для особой логики (например, всегда пропускать).
func resolve(player: RacerSlime) -> bool:
	if required_stat == "":
		return false
	return player.race_stat(required_stat) >= required_value

## Отклик на касание (анимация, звук). Переопределять.
func on_hit(player: RacerSlime) -> void:
	hit.emit(player)

## Анимация — переопределять в наследниках (движущиеся препятствия и т.п.)
func _process(_delta: float) -> void:
	pass
