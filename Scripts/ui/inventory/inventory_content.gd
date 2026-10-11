extends ScrollContainer
class_name InventoryContent

# Вызывается, когда игрок выбрал слизня в режиме выбора (см. select_mode)
signal slime_selected(instance_uid: int, slime_id: String)

@onready var item_list: HFlowContainer = %ItemList

const ITEM_SCENE := preload("res://Resources/ui/dialogs/inventory/inventory_item.tscn")
const PIXEL_FONT := preload("res://Resources/fonts/pixelFont.ttf")

# Режим выбора: у карточек прячутся кнопки Put/Sell, а клик по самой
# карточке возвращает слизня. Так открывается выбор гонщика в гонке.
# По умолчанию выключен — обычный инвентарь работает как раньше.
@export var select_mode: bool = false

func _ready():
	if GameState:
		GameState.slimes_changed.connect(_on_data_changed)
	build()

func _exit_tree():
	if GameState and GameState.slimes_changed.is_connected(_on_data_changed):
		GameState.slimes_changed.disconnect(_on_data_changed)

func _on_data_changed():
	if is_visible_in_tree():
		build()

func build():
	if item_list == null:
		push_error("[InventoryContent] ItemList не найден")
		return

	for child in item_list.get_children():
		child.queue_free()

	var instances = GameState.get_all_instances()

	if instances.is_empty():
		var empty = Label.new()
		empty.text = "Инвентарь пуст\nКупи слизня в магазине"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_override("font", PIXEL_FONT)
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.66, 0.68, 0.75))
		item_list.add_child(empty)
		return

	for inst in instances:
		var item: InventoryItem = ITEM_SCENE.instantiate()
		item_list.add_child(item)
		item.setup(inst.id, inst.uid, select_mode)   # ← передаём id, uid и режим
		if select_mode:
			item.picked.connect(_on_item_picked)

# ============================================
# ВЫБОР
# ============================================
func _on_item_picked(instance_uid: int, slime_id: String) -> void:
	slime_selected.emit(instance_uid, slime_id)
