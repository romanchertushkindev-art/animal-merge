extends PanelContainer

# ============================================
# ССЫЛКИ
# ============================================
@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %NameLabel
@onready var count_label: Label = %CountLabel
@onready var buy_button: Button = %BuyButton

# ============================================
# ДАННЫЕ
# ============================================
var data: SlimeData
var _is_buying: bool = false

signal bought(slime_id: String)

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	if buy_button:
		# Защита от двойного connect
		if buy_button.pressed.is_connected(_on_buy_pressed):
			buy_button.pressed.disconnect(_on_buy_pressed)
		buy_button.pressed.connect(_on_buy_pressed)
		buy_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(slime_data: SlimeData):
	data = slime_data

	if icon:
		icon.custom_minimum_size = Vector2(80, 80)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if data.sheet_texture:
			icon.texture = data.sheet_texture

	if name_label:
		name_label.text = data.display_name

	refresh()

# ============================================
# ОБНОВЛЕНИЕ
# ============================================
func refresh():
	if data == null:
		return

	var unlocked := GameState.has_slime(data.id)
	var count := GameState.get_on_scene_count_of(data.id)
	var cost := data.price if unlocked else data.unlock_price

	if count_label:
		count_label.text = ("Куплено: %d" % count) if unlocked else "Не открыт"

	if buy_button:
		buy_button.text = GameState.format_number(cost)

		var not_enough := GameState.slime < cost

		buy_button.disabled = not_enough or _is_buying

		if not_enough:
			buy_button.tooltip_text = "Не хватает слизи"
		else:
			buy_button.tooltip_text = ""

# ============================================
# ПОКУПКА
# ============================================
func _on_buy_pressed():
	if _is_buying or data == null:
		return

	var unlocked := GameState.has_slime(data.id)
	var cost := data.price if unlocked else data.unlock_price

	if not GameState.spend_slime(cost):
		return

	_is_buying = true

	# ✅ ТОЛЬКО добавляем в GameState
	# Farm сам заспавнит слизня через сигнал slimes_changed
	GameState.create_instance(data.id)

	_is_buying = false

	bought.emit(data.id)
	refresh()
