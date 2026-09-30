extends Control
class_name ShopTabUpgrades

# Вкладка «Апгрейды». Пока это заглушка: системы апгрейдов в игре
# ещё нет, есть только лягушка, вшитая в main.tscn как свободный узел.
# Когда появится UpgradeData — наполнять будем здесь.

const PIXEL_FONT := preload("res://Resources/fonts/pixelFont.ttf")

@onready var label: Label = %Label

func _ready() -> void:
	if label == null:
		return
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 10)
