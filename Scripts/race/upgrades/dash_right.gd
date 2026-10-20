class_name DashUpgrade
extends Node

@export var dash_summ := 500.0        ## на сколько прибавить скорость
@export var dash_duration := 0.2       ## сколько держится буст (сек)
@export var dash_cooldown := 1.5       ## откат после окончания буста (сек)

@onready var racer: RacerSlime = get_parent()

var _cooldown_timer := 0.0
var _dash_timer := 0.0
var _dash_active := false

func _process(delta: float) -> void:
	# тикаем кулдаун
	if _cooldown_timer > 0.0:
		_cooldown_timer = max(_cooldown_timer - delta, 0.0)

	# если дэш активен — тикаем его длительность
	if _dash_active:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_end_dash()

## Публичный метод — дёргать из кнопки, клавиши, геймпада
func start_dash() -> void:
	if _dash_active or _cooldown_timer > 0.0:
		return
	_dash_active = true
	_dash_timer = dash_duration
	_cooldown_timer = dash_duration + dash_cooldown
	racer.speed += dash_summ

func _end_dash() -> void:
	_dash_active = false
	racer.speed -= dash_summ

## Для UI/кнопки — можно ли сейчас делать дэш
func can_dash() -> bool:
	return not _dash_active and _cooldown_timer <= 0.0


func _on_dash_pressed() -> void:
	pass # Replace with function body.
