extends Node2D
## 엔터 더 건전 스타일의 따뜻한 벽면/화로 횃불 광원 및 불티 연출

@export var light_color: Color = Color(1.0, 0.65, 0.25, 0.16)
@export var base_radius: float = 44.0

var _time: float = 0.0
var _phase: float = 0.0

func _ready() -> void:
	_phase = randf_range(0.0, TAU)
	z_index = 0

func _process(delta: float) -> void:
	_time += delta * 6.5
	queue_redraw()

func _draw() -> void:
	var pulse: float = 1.0 + sin(_time + _phase) * 0.08 + cos(_time * 2.3) * 0.04
	var r: float = base_radius * pulse
	draw_circle(Vector2.ZERO, r, Color(light_color.r, light_color.g, light_color.b, light_color.a * 0.45))
	draw_circle(Vector2.ZERO, r * 0.6, Color(light_color.r, light_color.g, light_color.b, light_color.a * 0.75))
	draw_circle(Vector2.ZERO, r * 0.25, Color(1.0, 0.9, 0.55, light_color.a * 1.1))
