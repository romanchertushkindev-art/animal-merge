extends CanvasLayer

# ============================================
# ССЫЛКИ (ищем по имени, независимо от структуры)
# ============================================
@onready var dimmer: ColorRect = %Dimmer
@onready var item_list: VBoxContainer = %ItemList
@onready var close_button: TextureButton = %CloseBtn

const SHOP_ITEM_SCENE := preload("res://Resources/UI/Dialogs/shop/shopItem.tscn")

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	visible = false

	print("[Shop] dimmer = ", dimmer)
	print("[Shop] item_list = ", item_list)
	print("[Shop] close_button = ", close_button)

	if close_button:
		close_button.pressed.connect(_on_close)
	if dimmer:
		dimmer.gui_input.connect(_on_dimmer_input)

	#if GameState:
		#GameState.slime_changed.connect(_on_slime_changed)
		#_on_slime_changed(GameState.slime)

	build_shop()

## ============================================
## СЧЁТЧИК СЛИЗИ
## ============================================
#func _on_slime_changed(value: float):
	#if slime_counter:
		#slime_counter.text = "Ваша слизь: " + GameState.format_number(value)

# ============================================
# ПОСТРОЕНИЕ СПИСКА
# ============================================
func build_shop():
	if item_list == null:
		push_error("[Shop] item_list не найден! Проверь имя узла.")
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
		item.bought.connect(_on_item_bought)

# ============================================
# СОБЫТИЯ
# ============================================
func _on_item_bought(slime_id: String):
	print("[Shop] Куплен: ", slime_id)

func _on_close():
	close()

func _on_dimmer_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

# ============================================
# ОТКРЫТИЕ / ЗАКРЫТИЕ
# ============================================
func open():
	visible = true
	for item in item_list.get_children():
		if item.has_method("set_process"):
			item.set_process(true)
	build_shop()
	
func close():
	visible = false
	set_process(false)  # выключаем
