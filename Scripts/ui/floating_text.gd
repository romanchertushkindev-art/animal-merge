class_name FloatingText
extends Node2D

# Всплывающий текст над каплей. Вся внешность вынесена в @export,
# чтобы её можно было крутить в инспекторе, не лезя в код.
#
# Раньше цвет приходил от капли (drop_color слизня), из-за чего ручной
# сбор всегда показывался зелёным, а белый цвет, выставленный в сцене,
# затирался в setup(). Теперь цвет выбирается здесь, по стилю, а
# вызывающий код сообщает только смысл: кликнул игрок или съела жаба.

enum Style {
	MANUAL,    # игрок кликнул — ярко, это его награда за внимание
	PASSIVE,   # съела лягушка — тише, но с той же обводкой
}

# ============================================
# ЦВЕТ И ОБВОДКА
# ============================================
# Обводка — главное, что делает текст читаемым поверх пёстрой фермы.
@export_group("Цвет")
@export var color_manual: Color = Color(1, 1, 1, 1)
@export var color_passive: Color = Color(0.78, 0.88, 0.95, 0.9)
@export var outline_color: Color = Color(0.05, 0.06, 0.1, 1)
@export var outline_size: int = 3
@export var shadow_color: Color = Color(0, 0, 0, 0.55)
@export var shadow_offset: Vector2 = Vector2(1, 2)
@export var shadow_size: int = 1

# ============================================
# ДВИЖЕНИЕ
# ============================================
@export_group("Движение")
@export var rise_distance: float = 26.0
@export var drift: float = 10.0
@export var duration: float = 0.9
@export var pop_scale: float = 1.3
@export var pop_time: float = 0.14

# ============================================
# ШРИФТ
# ============================================
@export_group("Шрифт")
@export var base_font_size: int = 10
@export var big_font_size: int = 14
@export var big_text_threshold: int = 4     # длиннее — берём крупный шрифт

@onready var label: Label = $Label

func _ready() -> void:
	if label == null:
		push_warning("[FloatingText] Label не найден")
		queue_free()
		return

	# Прячем до конца первого кадра: иначе текст на одну кадр
	# мелькнёт в полный размер прежде, чем мы посчитаем точку
	# масштабирования (см. start_animation)
	label.visible = false
	_apply_look()

# Обводка и тень накладываются скриптом, а не остаются в сцене:
# так настройки живут в одном месте и не могут разъехаться с кодом.
func _apply_look() -> void:
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", shadow_color)
	label.add_theme_constant_override("shadow_offset_x", int(shadow_offset.x))
	label.add_theme_constant_override("shadow_offset_y", int(shadow_offset.y))
	label.add_theme_constant_override("shadow_outline_size", shadow_size)

func get_color(style: Style, multiplier: float = 0.0) -> Color:
	if style == Style.MANUAL:
		return get_gold_color(multiplier)
	else: 
		return color_passive

func get_gold_color(multiplier: float) -> Color:
	if multiplier < 1.2: 
		return color_manual
	if multiplier == 2.0:
		return Color("fc0056ff")
		
	var t := (multiplier - 1.0) / 1.0
	return Color.WHITE.lerp(Color("#FFD700"), t)

# setup вызывается ПОСЛЕ установки global_position
func setup(text_value: String, style: Style = Style.MANUAL, multiplayer: float = 0.0) -> void:
	if label == null:
		return

	label.text = text_value
	label.add_theme_color_override("font_color", get_color(style, multiplayer))
	label.add_theme_font_size_override(
		"font_size",
		big_font_size if text_value.length() > big_text_threshold else base_font_size
	)

	# ← Анимация запускается ЗДЕСЬ, когда позиция уже правильная
	start_animation()

func start_animation() -> void:
	# Ждём кадр: до этого лейаут ещё не посчитал размер лейбла,
	# и точка масштабирования была бы в углу — текст дёргался бы вбок
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var start_pos := position
	var end_pos := start_pos + Vector2(randf_range(-drift, drift), -rise_distance)

	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.5, 0.5)
	label.visible = true

	var tween := create_tween()
	tween.set_parallel(true)

	# Строго вверх
	tween.tween_property(self, "position", end_pos, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Затухание
	tween.tween_property(label, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Pop-эффект: 0.5 → pop_scale → 1.0
	tween.tween_property(label, "scale", Vector2(pop_scale, pop_scale), pop_time)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.chain().tween_property(label, "scale", Vector2.ONE, pop_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Удаление
	await get_tree().create_timer(duration).timeout
	queue_free()
