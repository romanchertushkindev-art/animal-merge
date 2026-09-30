extends ScrollContainer
class_name ShopTabSlimes

# Содержимое вкладки «Слаймы». Живёт своей сценой, магазин только
# подставляет её в хост вкладок.

@onready var item_list: VBoxContainer = %ItemList

const SHOP_ITEM_SCENE := preload("res://Resources/ui/dialogs/shop/shop_item.tscn")

func _ready():
	if GameState:
		GameState.slime_changed.connect(_on_slime_changed)
		GameState.slimes_changed.connect(_on_slimes_changed)
	build()

func _on_slime_changed(_value: float) -> void:
	# slime_changed летит на КАЖДУЮ каплю. Скрытая вкладка не должна
	# перерисовывать карточки — их всё равно никто не видит.
	if not is_visible_in_tree():
		return
	refresh()

func _on_slimes_changed() -> void:
	if is_visible_in_tree():
		build()

# Вызывается магазином, когда вкладку открыли
func refresh() -> void:
	for item in item_list.get_children():
		if item.has_method("refresh"):
			item.refresh()

func build() -> void:
	if item_list == null:
		push_error("[ShopTabSlimes] ItemList не найден")
		return

	for child in item_list.get_children():
		child.queue_free()

	for id in SlimeFactory.get_all_ids():
		var data: SlimeData = SlimeFactory.get_data(id)
		if data == null:
			continue

		var item = SHOP_ITEM_SCENE.instantiate()
		item_list.add_child(item)
		item.setup(data)

func _exit_tree() -> void:
	if GameState:
		if GameState.slime_changed.is_connected(_on_slime_changed):
			GameState.slime_changed.disconnect(_on_slime_changed)
		if GameState.slimes_changed.is_connected(_on_slimes_changed):
			GameState.slimes_changed.disconnect(_on_slimes_changed)
