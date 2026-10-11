extends Panel

# Панель множителя клика: само значение и сколько секунд осталось до
# падения ступеньки. До покупки апгрейда скрыта целиком — множителя
# без него не существует.
#
# Цвет ведёт от белого к золотому по мере набора, чтобы шкалу читалось
# боковым зрением, не разбирая цифры.

@onready var multiplier_label: Label = %MultiplierLabel
@onready var timer_label: Label = %TimerLabel

const COLOR_MIN := Color(1, 1, 1, 1)
const COLOR_MAX := Color(1.0, 0.84, 0.0, 1)

func _ready() -> void:
	if GameState:
		GameState.click_multiplier_changed.connect(_on_multiplier_changed)
		GameState.upgrades_changed.connect(_on_upgrades_changed)
	refresh()

func refresh() -> void:
	visible = GameState != null and GameState.is_multiplier_unlocked()
	if visible:
		_on_multiplier_changed(GameState.click_multiplier, GameState.click_multiplier_timer)

func _on_multiplier_changed(multiplier: float, time_left: float) -> void:
	if multiplier_label:
		multiplier_label.text = "×%.1f" % multiplier
		var span: float = GameState.MULTIPLIER_MAX - GameState.MULTIPLIER_MIN
		multiplier_label.modulate = COLOR_MIN.lerp(COLOR_MAX,
			clampf((multiplier - GameState.MULTIPLIER_MIN) / span, 0.0, 1.0))

	if timer_label:
		if multiplier > GameState.MULTIPLIER_MIN:
			timer_label.text = "через %d с" % maxi(ceili(time_left), 0)
		else:
			timer_label.text = "кликайте"

func _on_upgrades_changed() -> void:
	refresh()
