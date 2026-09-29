extends HBoxContainer

# Отображаемое (плавное) и целевое (реальное) значения
var displayed_value: float = 0.0
var target_value: float = 0.0

@onready var value_label: Label = %ValueLabel
@onready var SlimeCountOnScreen: Label = %SlimeCountOnScreen

# Скорость набегания (чем больше — тем быстрее догоняет)
@export var catch_up_speed: float = 6.0

# Минимальное отличие, при котором считаем, что «догнали»
const EPSILON: float = 0.5

# Кэшированное число слизней на сцене.
# Раньше оно бралось из SlimeFactory.get_active_count() каждый кадр,
# а тот пересобирал массив через filter() — 60 раз в секунду.
var _on_scene_count: int = 0

func _ready():
	if GameState == null:
		push_error("[SlimePanel] GameState не найден")
		return

	GameState.slime_changed.connect(_on_slime_changed)
	SlimeFactory.slime_count_changed.connect(_on_slime_count_changed)

	# Стартовое значение — без плавности (чтобы не набегало с 0)
	target_value = GameState.slime
	displayed_value = target_value
	_update_value_label()

	# Стартовое число берём один раз, дальше приходит по сигналу
	_on_scene_count = SlimeFactory.get_active_count()
	_update_count_label()

func _on_slime_changed(new_value: float):
	target_value = new_value

func _on_slime_count_changed(new_count: int):
	if _on_scene_count == new_count:
		return
	_on_scene_count = new_count
	_update_count_label()

func _process(delta):
	if abs(displayed_value - target_value) < EPSILON:
		# Догнали — фиксируем точное значение
		displayed_value = target_value
	else:
		# Плавно движемся к цели
		displayed_value = lerp(displayed_value, target_value, delta * catch_up_speed)

	_update_value_label()

func _update_value_label():
	if value_label:
		value_label.text = GameState.format_number(displayed_value)

func _update_count_label():
	if SlimeCountOnScreen:
		SlimeCountOnScreen.text = "%d/%d" % [_on_scene_count, SlimeFactory.MAX_SLIMES_SLOT]
