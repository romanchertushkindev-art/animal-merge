extends Node2D

@export var rise_distance: float = 60.0
@export var duration: float = 0.8
@export var pop_scale: float = 1.2
@export var base_font_size: int = 20
@export var big_font_size: int = 28

@onready var label: Label = $Label

# _ready только проверяет, что Label есть
func _ready():
	if label == null:
		push_warning("[FloatingText] Label не найден")
		queue_free()

# setup вызывается ПОСЛЕ установки global_position
func setup(text_value: String, color: Color = Color(0.5, 1.0, 0.7, 1.0)):
	if label == null:
		return

	label.text = text_value
	label.add_theme_color_override("font_color", color)

	if text_value.length() > 3:
		label.add_theme_font_size_override("font_size", big_font_size)
	else:
		label.add_theme_font_size_override("font_size", base_font_size)

	# ← Анимация запускается ЗДЕСЬ, когда позиция уже правильная
	start_animation()

func start_animation():
	# Стартовая позиция — там, где стоит узел (над каплей)
	var start_pos := position
	var end_pos := start_pos + Vector2(0, -rise_distance)

	label.scale = Vector2(0.5, 0.5)
	label.pivot_offset = label.size / 2.0

	var tween := create_tween()
	tween.set_parallel(true)

	# Строго вверх
	tween.tween_property(self, "position", end_pos, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Затухание
	tween.tween_property(label, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Pop-эффект: 0.5 → 1.2 → 1.0
	tween.tween_property(label, "scale", Vector2(pop_scale, pop_scale), 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Удаление
	await get_tree().create_timer(duration).timeout
	queue_free()
