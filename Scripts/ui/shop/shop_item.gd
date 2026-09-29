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
	var on_scene := GameState.get_on_scene_count_of(data.id)
	var cost := data.price if unlocked else data.unlock_price

	if count_label:
		# Раньше здесь писалось «Куплено», но показывалось число слизней
		# на сцене. Из-за этого покупка выглядела как потеря денег.
		count_label.text = ("На сцене: %d" % on_scene) if unlocked else "Не открыт"

	if buy_button:
		buy_button.text = GameState.format_number(cost)

		# Покупка уходит в ЗАПАС, а не сразу на ферму. Если свободных
		# слотов нет — блокируем кнопку, иначе игрок тратит деньги в никуда
		# и не получает дохода.
		var slots_used: int = GameState.get_on_scene_count()
		var no_slots := slots_used >= SlimeFactory.MAX_SLIMES_SLOT
		var not_enough := GameState.slime < cost

		buy_button.disabled = no_slots or not_enough or _is_buying

		if no_slots:
			buy_button.tooltip_text = "Все слоты заняты (%d/%d) — сначала убери слизня со сцены" % [
				slots_used, SlimeFactory.MAX_SLIMES_SLOT
			]
		elif not_enough:
			buy_button.tooltip_text = "Не хватает слизи"
		else:
			buy_button.tooltip_text = "Покупка уходит в запас — выстави его в инвентаре"

# ============================================
# ПОКУПКА
# ============================================
func _on_buy_pressed():
	if _is_buying or data == null:
		return

	# Слоты могли кончиться, пока карточка висела открытой
	if GameState.get_on_scene_count() >= SlimeFactory.MAX_SLIMES_SLOT:
		refresh()
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
