extends Node

# Автолоад для плавных переходов между сценами.
# Сам создаёт CanvasLayer + ColorRect, не требует .tscn.
# Использование: SceneTransition.change_scene("res://Scenes/main.tscn")

var _layer: CanvasLayer
var _rect: ColorRect
var _is_transitioning: bool = false

func _ready() -> void:
	# Слой поверх всего
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	# Затемняющий прямоугольник на весь экран
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)          # изначально прозрачный
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_rect)

## Плавно затемняет экран, меняет сцену, плавно проявляет.
func change_scene(path: String, duration: float = 0.4) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	# Блокируем ввод на время перехода
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Затемнение
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, duration)
	await tw.finished

	# 2. Смена сцены
	get_tree().change_scene_to_file(path)
	# Ждём, пока новая сцена реально окажется в дереве
	await get_tree().process_frame
	await get_tree().process_frame

	# 3. Проявление
	var tw2 := create_tween()
	tw2.tween_property(_rect, "color:a", 0.0, duration)
	await tw2.finished

	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
