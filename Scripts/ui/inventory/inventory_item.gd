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

# ============================================
# ДАННЫЕ
# ============================================
var instance_uid: int = -1
var slime_id: String = ""
var slime_data: SlimeData

signal changed()

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

func setup(id: String, uid: int):
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

	refresh()

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
