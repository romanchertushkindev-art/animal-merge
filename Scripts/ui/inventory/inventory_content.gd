extends ScrollContainer
class_name InventoryContent

@onready var item_list: HFlowContainer = %ItemList

const ITEM_SCENE := preload("res://Resources/ui/dialogs/inventory/inventory_item.tscn")

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
		item_list.add_child(empty)
		return

	for inst in instances:
		var item = ITEM_SCENE.instantiate()
		item_list.add_child(item)
		item.setup(inst.id, inst.uid)   # ← передаём id И uid
