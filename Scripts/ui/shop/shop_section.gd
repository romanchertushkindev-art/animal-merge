extends Resource
class_name ShopSection

# Описание одной вкладки магазина.
# Чтобы добавить раздел: создать .tres, положить рядом с этим файлом
# и дописать его в массив sections у ShopContent. Вкладка, сцена
# контента и кнопка появятся сами.

@export var id: String = ""
@export var title: String = ""
@export var icon: Texture2D
@export var content_scene: PackedScene
