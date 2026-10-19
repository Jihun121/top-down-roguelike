extends Area2D

@export var speed: float = 260.0
@export var max_lifetime: float = 2.5
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var _life_timer: float = 0.0
var _has_hit: bool = false

func _ready() -> void:
	_life_timer = max_lifetime
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	# [예외 방어 1] 동일 프레임 다중 타격 차단
	if _has_hit:
		return
	
	# [예외 방어 2] 발사 주체인 플레이어와의 충돌 무시
	if body.is_in_group("player"):
		return
	
	# 몬스터(take_damage 함수를 가진 대상)에 닿으면 데미지를 주고 총알 소멸
	if body.has_method("take_damage"):
		_has_hit = true
		body.call("take_damage", damage)
		queue_free()
		return
	
	# [예외 방어 3] 개별 물리 벽(StaticBody2D) 및 타일맵 벽(TileMapLayer) 충돌 시 소멸
	if body is StaticBody2D or body is TileMapLayer:
		_has_hit = true
		queue_free()
