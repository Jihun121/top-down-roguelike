extends CharacterBody2D
## 엔터 더 건전 스타일 원거리 정예 몬스터: 붉은 산탄총 일족 (Red Shotgun Kin)
## 거리를 유지하며 플레이어에게 4갈래 산탄총 탄막을 발사합니다.

signal died

@export var move_speed: float = 38.0
@export var max_hp: int = 4
@export var preferred_distance: float = 115.0
@export var fire_interval: float = 2.1
@export var enemy_bullet_scene: PackedScene = preload("res://scenes/enemy_bullet.tscn")

var _current_hp: int
var _is_dead: bool = false
var _target: Node2D = null
var _fire_timer: float = 1.2
var _strafe_dir: float = 1.0
var _strafe_timer: float = 2.0
var _walk_time: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_pivot: Node2D = get_node_or_null("WeaponPivot") as Node2D
@onready var _gun_sprite: Sprite2D = get_node_or_null("WeaponPivot/GunSprite") as Sprite2D
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_current_hp = max_hp
	_fire_timer = randf_range(0.9, fire_interval)
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
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
	
	var to_player: Vector2 = _target.global_position - global_position
	var dist: float = to_player.length()
	var dir: Vector2 = to_player.normalized() if dist > 0.001 else Vector2.RIGHT
	var angle: float = dir.angle()
	
	if _sprite != null and absf(dir.x) > 0.1:
		_sprite.flip_h = dir.x < 0.0
	
	if _weapon_pivot != null and _gun_sprite != null:
		_weapon_pivot.rotation = angle
		_gun_sprite.flip_v = absf(angle) > PI * 0.5
	
	_walk_time += delta
	if _sprite != null:
		_sprite.position.y = -absf(sin(_walk_time * 11.0)) * 1.8
		_sprite.rotation = sin(_walk_time * 5.5) * 0.07
	
	# 거리 유지 + 좌우 무빙 AI
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_dir = -_strafe_dir
		_strafe_timer = randf_range(1.4, 2.6)
	
	var move_vec: Vector2 = Vector2.ZERO
	if dist < preferred_distance - 25.0:
		move_vec = -dir
	elif dist > preferred_distance + 30.0:
		move_vec = dir
	else:
		move_vec = dir.orthogonal() * _strafe_dir * 0.75
	
	velocity = move_vec * move_speed
	move_and_slide()
	
	# 4갈래 산탄총 발사 타이머
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot_shotgun_spread(dir)

func _shoot_shotgun_spread(base_dir: Vector2) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	
	var count: int = 4
	var step: float = deg_to_rad(10.0)
	var start: float = -step * float(count - 1) * 0.5
	for i in range(count):
		var bullet: Area2D = enemy_bullet_scene.instantiate() as Area2D
		if bullet == null:
			continue
		var d: Vector2 = base_dir.rotated(start + step * float(i))
		bullet.set("direction", d)
		bullet.set("speed", 125.0)
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = global_position + d * 9.0

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
	_flash_tween.tween_property(_sprite, "self_modulate", Color.WHITE, 0.08)

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.set("total_kills", int(gm.get("total_kills")) + 1)
	died.emit()
	queue_free()
