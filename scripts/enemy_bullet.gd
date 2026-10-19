extends Area2D
## 엔터 더 건전 스타일의 적 탄환(붉은 발광 탄막 오브) 스크립트

@export var speed: float = 130.0
@export var max_lifetime: float = 4.5
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var _life_timer: float = 0.0
var _has_hit: bool = false

func _ready() -> void:
	add_to_group("enemy_bullets")
	_life_timer = max_lifetime
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _has_hit:
		return
	
	if body.is_in_group("enemies"):
		return
	
	# 플레이어 피격 처리 (구르기/닷지 롤 중에는 탄막 통과!)
	if body.is_in_group("player"):
		if body.has_method("is_invincible") and body.call("is_invincible"):
			return
		_has_hit = true
		if body.has_method("take_damage"):
			body.call("take_damage", damage)
		queue_free()
		return
	
	# 파괴 가능한 상자/나무통 타격 처리
	if body.is_in_group("destructibles") and body.has_method("take_damage"):
		_has_hit = true
		body.call("take_damage", 1)
		queue_free()
		return
	
	# 물리 벽 및 타일맵 벽 충돌 시 소멸
	if body is StaticBody2D or body is TileMapLayer:
		_has_hit = true
		queue_free()

## [Bullet Cancel] 방 클리어 시 화면 내 잔여 적탄을 일괄 소멸시킵니다.
func cancel_bullet() -> void:
	if _has_hit:
		return
	_has_hit = true
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ZERO, 0.15)
	tw.tween_callback(queue_free)
