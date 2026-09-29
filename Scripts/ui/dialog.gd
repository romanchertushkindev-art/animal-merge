extends CanvasLayer
class_name Dialog

@onready var dimmer: ColorRect = %Dimmer
@onready var title_label: Label = %TitleLabel
@onready var close_btn: TextureButton = %CloseBtn
@onready var content_slot: MarginContainer = %ContentSlot

signal closed()

var _content: Control = null

func _ready():
	visible = false
	if close_btn:
		close_btn.pressed.connect(close)
		close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if dimmer:
		dimmer.gui_input.connect(_on_dimmer_input)

func set_title(text: String):
	if title_label:
		title_label.text = text

func open_with(content: Control):
	# Удаляем старый контент
	if _content and is_instance_valid(_content):
		_content.queue_free()
	
	_content = content
	
	# Обёртка для контента
	if content_slot:
		content_slot.add_child(_content)
	
	visible = true

func close():
	visible = false
	if _content and is_instance_valid(_content):
		_content.queue_free()
		_content = null
	closed.emit()

func _on_dimmer_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
