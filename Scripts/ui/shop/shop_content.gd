extends HBoxContainer
class_name ShopContent

@onready var item_list: VBoxContainer = %ItemList

const SHOP_ITEM_SCENE := preload("res://Resources/UI/Dialogs/shop/shop_item.tscn")

func _ready():
	if GameState:
		GameState.slime_changed.connect(_on_slime_changed)
		GameState.slimes_changed.connect(_on_slimes_changed)
	
	build()

func _on_slime_changed(_value):
	# Обновить все карточки (цены, доступность)
	for item in item_list.get_children():
		if item.has_method("refresh"):
			item.refresh()

func _on_slimes_changed():
	if is_visible_in_tree():
		build()

func build():
	if item_list == null:
		push_error("[ShopContent] ItemList не найден")
		return

	# Очистка
	for child in item_list.get_children():
		child.queue_free()

	# Список всех доступных слизней
	for id in SlimeFactory.get_all_ids():
		var data: SlimeData = SlimeFactory.get_data(id)
		if data == null:
			continue

		var item = SHOP_ITEM_SCENE.instantiate()
		item_list.add_child(item)
		item.setup(data)

func _exit_tree():
	# Отписываемся от сигналов при закрытии
	if GameState:
		if GameState.slime_changed.is_connected(_on_slime_changed):
			GameState.slime_changed.disconnect(_on_slime_changed)
		if GameState.slimes_changed.is_connected(_on_slimes_changed):
			GameState.slimes_changed.disconnect(_on_slimes_changed)
