extends Button

# ============================================
# НАСТРОЙКИ
# ============================================
const DIALOG_SCENE := preload("res://Resources/ui/dialogs/dialog_base.tscn")
@export var SHOP_CONTENT: PackedScene
@export var dialog_title: String = "Магазин"

func _ready():
	pressed.connect(_on_pressed)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _on_pressed():
	open_dialog(SHOP_CONTENT, dialog_title)

# ============================================
# СОЗДАНИЕ ДИАЛОГА
# ============================================
func open_dialog(content_scene: PackedScene, title: String):
	# 1. Создаём диалог
	var dialog: Dialog = DIALOG_SCENE.instantiate()
	var content = null
	
	# 2. Создаём контент
	if content_scene:
		content = content_scene.instantiate()

	# 3. Добавляем диалог в текущую сцену
	get_tree().current_scene.add_child(dialog)

	# 4. Открываем с контентом
	dialog.set_title(title)
	dialog.open_with(content)

	# 5. Когда диалог закроется — удаляем его
	dialog.closed.connect(dialog.queue_free)
