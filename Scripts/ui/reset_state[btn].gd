extends Button

func _ready():
	pressed.connect(_on_pressed)
	text = "Сброс"

func _on_pressed():
	# Подтверждение
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Точно сбросить прогресс?"
	dialog.confirmed.connect(_do_reset)
	add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(dialog.queue_free)

func _do_reset():
	GameState.reset_progress()
	print("Прогресс сброшен через кнопку")
