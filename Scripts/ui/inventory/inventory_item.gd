extends PanelContainer
class_name InventoryItem

# ============================================
# ССЫЛКИ
# ============================================
@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %NameLabel
@onready var count_label: Label = %CountLabel
@onready var toggle_button: Button = %BuyButton
@onready var sell_button: Button = %SellBtn
@onready var level_button: Button = %LevelBtn

# ============================================
# ДАННЫЕ
# ============================================
var instance_uid: int = -1
var slime_id: String = ""
var slime_data: SlimeData
var select_mode: bool = false

signal changed()
# Клик по карточке в режиме выбора (см. select_mode в InventoryContent)
signal picked(instance_uid: int, slime_id: String)

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	if toggle_button:
		if toggle_button.pressed.is_connected(_on_toggle):
			toggle_button.pressed.disconnect(_on_toggle)
		toggle_button.pressed.connect(_on_toggle)
		toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if sell_button:
		if sell_button.pressed.is_connected(_on_sell):
			sell_button.pressed.disconnect(_on_sell)
		sell_button.pressed.connect(_on_sell)
		sell_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if level_button:
		if level_button.pressed.is_connected(_on_level_up):
			level_button.pressed.disconnect(_on_level_up)
		level_button.pressed.connect(_on_level_up)
		level_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(id: String, uid: int, in_select_mode: bool = false):
	slime_id = id
	instance_uid = uid
	slime_data = SlimeFactory.get_data(id)

	if slime_data == null:
		push_error("[InventoryItem] Нет данных для id: %s" % id)
		return

	if icon:
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if slime_data.sheet_texture:
			icon.texture = slime_data.shop_texture

	if name_label:
		name_label.text = slime_data.display_name

	_apply_select_mode(in_select_mode)

	refresh()

# ============================================
# РЕЖИМ ВЫБОРА
# ============================================
# Когда инвентарь открыт на выбор (например, «кто поедет в гонку»),
# карточка сама становится кнопкой: кнопки Put/Sell прячем, а клик
# по карточке отдаёт слизня наружу через сигнал picked.
func _apply_select_mode(enabled: bool) -> void:
	select_mode = enabled
	if not select_mode:
		return

	if sell_button:
		sell_button.visible = false
	if toggle_button:
		toggle_button.visible = false
	if level_button:
		level_button.visible = false
	if count_label:
		count_label.text = "Выбрать"
		count_label.add_theme_color_override("font_color", "99E550")

	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if not select_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		picked.emit(instance_uid, slime_id)

# ============================================
# ОБНОВЛЕНИЕ
# ============================================
func refresh():
	if slime_data == null:
		return

	var on_scene := GameState.is_on_scene(instance_uid)
	var on_scene_total := GameState.get_on_scene_count()

	if count_label:
		count_label.text = "На сцене" if on_scene else "В запасе"
		count_label.add_theme_color_override("font_color", "609a79" if on_scene else "c261b5")

	if toggle_button:
		if on_scene:
			toggle_button.text = "Del"
			toggle_button.disabled = false
			toggle_button.tooltip_text = ""
		else:
			toggle_button.text = "Put"
			var slots_full := on_scene_total >= SlimeFactory.MAX_SLIMES_SLOT
			toggle_button.disabled = slots_full
			toggle_button.tooltip_text = "Все слоты заняты" if slots_full else ""

	if sell_button:
		var price = GameState.get_sell_price(slime_id)
		# Без переноса строки: в кнопке 48x6 две строки не помещались
		sell_button.text = "Sell " + GameState.format_number(price)
		sell_button.disabled = on_scene
		sell_button.tooltip_text = "Сначала убери со сцены" if on_scene else ""

	_refresh_level_button()

# ============================================
# УРОВЕНЬ
# ============================================
# Уровень свой у каждого слизня, поэтому кнопка стоит на карточке
# конкретного экземпляра, а не в магазине у вида.
func _refresh_level_button():
	if level_button == null:
		return

	var level := GameState.get_instance_level(instance_uid)
	if GameState.is_max_level(instance_uid):
		level_button.text = "Ур.%d MAX" % level
		level_button.disabled = true
		level_button.tooltip_text = "Максимальный уровень"
		return

	# Без стрелки: символа ▲ нет в пиксельном шрифте, он рисуется
	# квадратом и съедает ширину кнопки
	var cost := GameState.get_level_price(instance_uid)
	level_button.text = "Ур.%d  %s" % [level, GameState.format_number(cost)]
	level_button.disabled = GameState.slime < cost
	level_button.tooltip_text = (
		"Не хватает слизи" if GameState.slime < cost
		else "Капля станет дороже на %d%%" % int(slime_data.level_drop_bonus * 100.0)
	)

func _on_level_up():
	if GameState.level_up_instance(instance_uid):
		changed.emit()
		refresh()

# ============================================
# ДЕЙСТВИЯ
# ============================================
func _on_toggle():
	var on_scene := GameState.is_on_scene(instance_uid)

	if on_scene:
		# Убираем со сцены
		GameState.set_on_scene(instance_uid, false)
	else:
		# Проверяем слоты
		if GameState.get_on_scene_count() >= SlimeFactory.MAX_SLIMES_SLOT:
			_flash_button(toggle_button)
			return
		GameState.set_on_scene(instance_uid, true)

	changed.emit()
	refresh()

func _on_sell():
	# Продавать можно только тех, кто в запасе
	if GameState.is_on_scene(instance_uid):
		_flash_button(sell_button)
		return

	if GameState.sell_instance(instance_uid):
		changed.emit()
		refresh()

# ============================================
# ВИЗУАЛЬНЫЙ ОТКЛИК
# ============================================
func _flash_button(button: Button):
	if button == null:
		return
	button.modulate = Color.RED
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(button):
		button.modulate = Color.WHITE
