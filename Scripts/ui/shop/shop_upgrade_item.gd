extends PanelContainer

# Карточка апгрейда в магазине (жаба, множитель клика и т.п.).
# В отличие от слизня апгрейд не уходит в запас: покупка сразу
# увеличивает счётчик в GameState, а ферма ловит upgrades_changed
# и ставит апгрейд на сцену (или просто обновляет цифры, если
# у апгрейда нет сцены — как у множителя).

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
var data: UpgradeData
var _is_buying: bool = false

signal bought(upgrade_id: String)

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

func setup(upgrade_data: UpgradeData):
	data = upgrade_data

	if icon:
		icon.custom_minimum_size = Vector2(80, 80)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if data.shop_texture:
			icon.texture = data.shop_texture

	if name_label:
		name_label.text = data.display_name

	refresh()

# ============================================
# ОБНОВЛЕНИЕ
# ============================================
func refresh():
	if data == null:
		return

	var count := GameState.get_upgrade_count(data.id)
	var cost := GameState.get_upgrade_price(data.id)
	var maxed := data.max_count > 0 and count >= data.max_count

	if count_label:
		if maxed:
			count_label.text = "Максимум"
		elif count > 0:
			count_label.text = "Куплено: %d" % count
		else:
			count_label.text = "Не куплено"

	if buy_button:
		buy_button.text = GameState.format_number(cost)

		var not_enough := GameState.slime < cost
		buy_button.disabled = maxed or not_enough or _is_buying

		if maxed:
			buy_button.tooltip_text = "Максимум куплено"
		elif not_enough:
			buy_button.tooltip_text = "Не хватает слизи"
		else:
			buy_button.tooltip_text = data.description

# ============================================
# ПОКУПКА
# ============================================
func _on_buy_pressed():
	if _is_buying or data == null:
		return

	# Лимит могли упереть, пока карточка висела открытой
	if data.max_count > 0 and GameState.get_upgrade_count(data.id) >= data.max_count:
		refresh()
		return

	_is_buying = true

	# Деньги списываются внутри buy_upgrade — карточка не платит дважды
	if GameState.buy_upgrade(data.id):
		bought.emit(data.id)

	_is_buying = false
	refresh()
