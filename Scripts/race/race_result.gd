extends Control
class_name RaceResult

# Итог забега: сколько доехал, сколько заработал и из-за чего встал.
# Начисление слизи уже сделал Race — здесь только показ.

signal retry_requested()
signal quit_requested()

@onready var reason_label: Label = %ReasonLabel
@onready var distance_label: Label = %DistanceLabel
@onready var reward_label: Label = %RewardLabel
@onready var retry_btn: Button = %RetryBtn
@onready var quit_btn: Button = %QuitBtn

func setup(meters: float, reward: float, reason: String) -> void:
	if reason_label:
		reason_label.text = reason
	if distance_label:
		distance_label.text = "%d м" % roundi(meters)
	if reward_label:
		reward_label.text = "+%s" % GameState.format_number(reward)

func _ready() -> void:
	if retry_btn:
		retry_btn.pressed.connect(func(): retry_requested.emit())
		retry_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if quit_btn:
		quit_btn.pressed.connect(func(): quit_requested.emit())
		quit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND