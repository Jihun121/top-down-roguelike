extends CharacterBody2D
## 엔터 더 건전 스타일 기본 몬스터: 총탄 일족 (Bullet Kin)
## 뒤뚱거리며 플레이어를 추적하고, 손에 든 권총으로 조준하여 단발 적탄을 발사합니다.

signal died

@export var move_speed: float = 44.0
@export var max_hp: int = 3
@export var contact_damage: int = 1
@export var fire_interval: float = 2.3
@export var enemy_bullet_scene: PackedScene = preload("res://scenes/enemy_bullet.tscn")

var _current_hp: int
var _is_dead: bool = false
var _target: Node2D = null
var _fire_timer: float = 1.5
var _walk_time: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_pivot: Node2D = get_node_or_null("WeaponPivot") as Node2D
@onready var _gun_sprite: Sprite2D = get_node_or_null("WeaponPivot/GunSprite") as Sprite2D
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_current_hp = max_hp
	_fire_timer = randf_range(1.0, fire_interval)
	_walk_time = randf_range(0.0, TAU)
	_target = get_tree().get_first_node_in_group("player") as Node2D

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		return
	
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node2D
		if not is_instance_valid(_target):
			velocity = Vector2.ZERO
			return
	
	var direction: Vector2 = global_position.direction_to(_target.global_position)
	var angle: float = direction.angle()
	if _sprite != null and absf(direction.x) > 0.1:
		_sprite.flip_h = direction.x < 0.0
	
	if _weapon_pivot != null and _gun_sprite != null:
		_weapon_pivot.rotation = angle
		_gun_sprite.flip_v = absf(angle) > PI * 0.5
	
	# 건전 특유의 뒤뚱거리는 걸음 모션
	_walk_time += delta
	if _sprite != null:
		_sprite.position.y = -absf(sin(_walk_time * 12.0)) * 1.8
		_sprite.rotation = sin(_walk_time * 6.0) * 0.08
	
	velocity = direction * move_speed
	move_and_slide()
	
	# 권총 단발 사격
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval + randf_range(-0.3, 0.3)
		_shoot_single(direction)
	
	# 플레이어와 접촉 시 데미지 전달
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		if col == null:
			continue
		var collider: Object = col.get_collider()
		if collider is Node and (collider as Node).is_in_group("player"):
			if collider.has_method("take_damage"):
				collider.call("take_damage", contact_damage)
			break

func _shoot_single(dir: Vector2) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	var b: Area2D = enemy_bullet_scene.instantiate() as Area2D
	if b == null:
		return
	b.set("direction", dir)
	b.set("speed", 115.0)
	get_tree().current_scene.add_child(b)
	b.global_position = global_position + dir * 9.0

func take_damage(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	
	_current_hp -= amount
	_play_hit_flash()
	
	if _current_hp <= 0:
		_die()

func _play_hit_flash() -> void:
	if _sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	
	_sprite.self_modulate = Color(3.0, 3.0, 3.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.08)

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.set("total_kills", int(gm.get("total_kills")) + 1)
	died.emit()
	queue_free()
