extends ScrollContainer
class_name ShopTabList

# Универсальное содержимое вкладки-магазина: список карточек из
# какого-то источника данных. Отдельного скрипта на каждую вкладку
# не нужно — вкладка описывается ресурсом ShopSection, а источник
# выбирается полем source прямо в сцене.
#
# Новый раздел: завести источник (например, как upgrades у
# UpgradeFactory), добавить ветку в _entries() и указать source
# в сцене вкладки.

@export var source: String = "slimes"
@export var card_scene: PackedScene

@onready var item_list: VBoxContainer = %ItemList

func _ready() -> void:
	if card_scene == null:
		card_scene = preload("res://Resources/ui/dialogs/shop/shop_item.tscn")

	if GameState:
		GameState.slime_changed.connect(_on_slime_changed)
		GameState.slimes_changed.connect(_on_slimes_changed)
		GameState.upgrades_changed.connect(_on_upgrades_changed)
	build()

# Какие записи показывать в этом списке
func _entries() -> Array:
	var out: Array = []
	match source:
		"slimes":
			for id in SlimeFactory.get_all_ids():
				var data: SlimeData = SlimeFactory.get_data(id)
				if data != null:
					out.append(data)
		"upgrades":
			for id in UpgradeFactory.get_all_ids():
				var data: UpgradeData = UpgradeFactory.get_data(id)
				if data != null:
					out.append(data)
		_:
			push_warning("[ShopTabList] неизвестный источник «%s»" % source)
	return out

func build() -> void:
	if item_list == null:
		push_error("[ShopTabList] ItemList не найден")
		return

	for child in item_list.get_children():
		child.queue_free()

	for entry in _entries():
		var card = card_scene.instantiate()
		item_list.add_child(card)
		card.setup(entry)

# Вызывается магазином, когда вкладку открыли
func refresh() -> void:
	for card in item_list.get_children():
		if card.has_method("refresh"):
			card.refresh()

func _on_slime_changed(_value: float) -> void:
	# slime_changed летит на КАЖДУЮ каплю. Скрытая вкладка не должна
	# перерисовывать карточки — их всё равно никто не видит.
	if not is_visible_in_tree():
		return
	refresh()

func _on_slimes_changed() -> void:
	if is_visible_in_tree():
		build()

# Апгрейды не добавляют и не убирают карточки — меняются только
# цена и счётчик, поэтому хватает refresh.
func _on_upgrades_changed() -> void:
	if is_visible_in_tree():
		refresh()

func _exit_tree() -> void:
	if GameState:
		if GameState.slime_changed.is_connected(_on_slime_changed):
			GameState.slime_changed.disconnect(_on_slime_changed)
		if GameState.slimes_changed.is_connected(_on_slimes_changed):
			GameState.slimes_changed.disconnect(_on_slimes_changed)
		if GameState.upgrades_changed.is_connected(_on_upgrades_changed):
			GameState.upgrades_changed.disconnect(_on_upgrades_changed)
