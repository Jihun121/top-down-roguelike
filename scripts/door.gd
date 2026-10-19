extends StaticBody2D
## 방 클리어 전에는 물리적으로 잠겨 있고, 모든 적 처치 시 개방되어 다음 방으로 이동시키는 출입문

signal player_entered_exit

var is_open: bool = false
var _transition_triggered: bool = false

@onready var _closed_visual: Node2D = $ClosedVisual
@onready var _open_visual: Node2D = $OpenVisual
@onready var _block_collision: CollisionShape2D = $BlockCollision
@onready var _exit_sensor: Area2D = $ExitSensor
@onready var _status_label: Label = $StatusLabel

func _ready() -> void:
	add_to_group("doors")
	_exit_sensor.body_entered.connect(_on_exit_sensor_body_entered)
	lock_door()

## 문을 잠금 상태로 전환합니다.
func lock_door() -> void:
	is_open = false
	_transition_triggered = false
	if _closed_visual != null:
		_closed_visual.visible = true
	if _open_visual != null:
		_open_visual.visible = false
	if _block_collision != null:
		_block_collision.set_deferred("disabled", false)
	if _status_label != null:
		_status_label.text = "[잠김]"
		_status_label.modulate = Color(1.0, 0.45, 0.45, 0.9)

## 방 안의 모든 적이 처치되었을 때 호출되어 문을 개방합니다.
func open() -> void:
	if is_open:
		return
	is_open = true
	if _closed_visual != null:
		_closed_visual.visible = false
	if _open_visual != null:
		_open_visual.visible = true
	
	# [엔진 에러 방지] 물리 콜백 도중 안전하게 충돌체를 비활성화합니다.
	if _block_collision != null:
		_block_collision.set_deferred("disabled", true)
	
	if _status_label != null:
		_status_label.text = "▲ 다음 방"
		_status_label.modulate = Color(0.35, 1.0, 0.55, 1.0)
	
	# 이미 플레이어가 센서 범위 안에 서 있는 경우 즉시 감지 체크
	call_deferred("_check_overlapping_player")

func _check_overlapping_player() -> void:
	if not is_open or _transition_triggered or _exit_sensor == null:
		return
	for body in _exit_sensor.get_overlapping_bodies():
		if body is Node2D and body.is_in_group("player"):
			_trigger_exit()
			return

func _on_exit_sensor_body_entered(body: Node2D) -> void:
	if not is_open or _transition_triggered:
		return
	if body.is_in_group("player"):
		_trigger_exit()

func _trigger_exit() -> void:
	if _transition_triggered:
		return
	_transition_triggered = true
	player_entered_exit.emit()
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.call("go_to_next_room")
