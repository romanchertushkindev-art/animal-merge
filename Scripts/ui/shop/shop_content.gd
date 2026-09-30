extends HBoxContainer
class_name ShopContent

# Контейнер магазина: слева полоса вкладок, справа хост контента.
# Сами вкладки не зашиты в сцену — они берутся из массива sections,
# поэтому новый раздел добавляется файлом .tres, а не правкой .tscn.
#
# Контент строится лениво: сцена вкладки создаётся при первом
# открытии и дальше просто показывается. Это заодно снимает
# пересборку списка на каждый slime_changed.

@onready var tab_strip: VBoxContainer = %TabStrip
@onready var tab_host: Control = %TabHost

@export var sections: Array[ShopSection] = []

# id -> уже созданная панель
var _panels: Dictionary = {}
# id -> кнопка вкладки
var _buttons: Dictionary = {}
var _group := ButtonGroup.new()

# Стили табов. Раньше они жили в .tscn на каждой кнопке; теперь
# кнопки создаются кодом, поэтому стили переносим сюда.
const TAB_FONT := preload("res://Resources/fonts/pixelFont.ttf")
const TAB_STYLE := preload("res://Resources/tres/uiStyles/shop/slot_normal.tres")
const TAB_STYLE_SELECTED := preload("res://Resources/tres/uiStyles/shop/slot_selected.tres")
const TAB_SIZE := Vector2(156, 36)
const TAB_FONT_SIZE := 16

func _ready() -> void:
	if sections.is_empty():
		push_error("[ShopContent] sections пуст — вкладок не будет")
		return
	_build_tabs()
	show_tab(sections[0].id)

func _build_tabs() -> void:
	for section in sections:
		var button := _make_tab_button(section)
		tab_strip.add_child(button)
		_buttons[section.id] = button
		button.pressed.connect(show_tab.bind(section.id))

func _make_tab_button(section: ShopSection) -> Button:
	var button := Button.new()
	button.text = section.title
	button.icon = section.icon
	# toggle_mode + общая группа: нажатая вкладка остаётся нажатой,
	# остальные автоматически отжимаются
	button.toggle_mode = true
	button.button_group = _group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = TAB_SIZE
	button.focus_mode = Control.FOCUS_NONE

	button.add_theme_font_override("font", TAB_FONT)
	button.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	button.add_theme_stylebox_override("normal", TAB_STYLE)
	button.add_theme_stylebox_override("hover", TAB_STYLE)
	button.add_theme_stylebox_override("focus", TAB_STYLE)
	# У вкладки в нажатом состоянии наш стиль активной
	button.add_theme_stylebox_override("pressed", TAB_STYLE_SELECTED)
	button.add_theme_constant_override("h_separation", 15)
	button.add_theme_constant_override("icon_max_width", 22)
	return button

func show_tab(id: String) -> void:
	# Подсветка активной вкладки. Группа сама отожмёт остальные.
	if _buttons.has(id):
		(_buttons[id] as Button).button_pressed = true

	if not _panels.has(id):
		var section := _find_section(id)
		if section == null:
			push_warning("[ShopContent] нет вкладки «%s»" % id)
			return
		if section.content_scene == null:
			push_warning("[ShopContent] у вкладки «%s» нет content_scene" % id)
			return

		var panel: Control = section.content_scene.instantiate()
		tab_host.add_child(panel)
		_panels[id] = panel

	var target: Control = _panels[id]
	for key in _panels.keys():
		(_panels[key] as Control).visible = key == id
	target.visible = true

	# Цены могли уехать, пока вкладка была скрыта
	if target.has_method("refresh"):
		target.refresh()
	_scroll_to_top(target)

func _find_section(id: String) -> ShopSection:
	for section in sections:
		if section.id == id:
			return section
	return null

func _scroll_to_top(panel: Control) -> void:
	for child in panel.get_children():
		if child is ScrollContainer:
			(child as ScrollContainer).scroll_vertical = 0
