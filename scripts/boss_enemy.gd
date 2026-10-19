extends CharacterBody2D
## 5번 방(보스방) 최종 보스: 심연의 외눈 거인(Cyclops Overlord)
## 패턴 1: 3갈래 조준 사격 | 패턴 2: 8방향 전방위 탄막 노바 | 패턴 3: 예고 후 고속 돌진

signal died
signal boss_hp_changed(current_hp: int, max_hp: int)

@export var move_speed: float = 38.0
@export var charge_speed: float = 155.0
@export var max_hp: int = 32
@export var enemy_bullet_scene: PackedScene = preload("res://scenes/enemy_bullet.tscn")

var _current_hp: int
var _is_dead: bool = false
var _target: Node2D = null

var _pattern_timer: float = 2.0
var _pattern_index: int = 0
var _is_charging: bool = false
var _charge_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.RIGHT

@onready var _sprite: Sprite2D = $Sprite2D
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	_current_hp = max_hp
	_target = get_tree().get_first_node_in_group("player") as Node2D
	boss_hp_changed.emit(_current_hp, max_hp)

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		return
	
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node2D
		if not is_instance_valid(_target):
			velocity = Vector2.ZERO
			return
	
	var dir_to_player: Vector2 = global_position.direction_to(_target.global_position)
	if _sprite != null and absf(dir_to_player.x) > 0.1 and not _is_charging:
		_sprite.flip_h = dir_to_player.x < 0.0
	
	if _is_charging:
		_charge_timer -= delta
		velocity = _charge_dir * charge_speed
		move_and_slide()
		_check_player_collision()
		if _charge_timer <= 0.0:
			_is_charging = false
			if _sprite != null:
				_sprite.modulate = Color.WHITE
		return
	
	# 평소에는 플레이어를 향해 천천히 압박 이동
	var rage_mult: float = 1.3 if _current_hp <= max_hp / 2 else 1.0
	velocity = dir_to_player * (move_speed * rage_mult)
	move_and_slide()
	_check_player_collision()
	
	# 보스 공격 패턴 사이클
	_pattern_timer -= delta * rage_mult
	if _pattern_timer <= 0.0:
		_execute_next_pattern(dir_to_player)

func _execute_next_pattern(dir_to_player: Vector2) -> void:
	_pattern_index = (_pattern_index + 1) % 3
	match _pattern_index:
		0:
			# 3갈래 부채꼴 조준탄 발사
			_fire_fan(dir_to_player, 3, 18.0, 155.0)
			_pattern_timer = 1.8
		1:
			# 8방향(광폭화 시 10방향) 원형 노바 탄막
			var count: int = 10 if _current_hp <= max_hp / 2 else 8
			_fire_ring(count, 125.0)
			_pattern_timer = 2.2
		2:
			# 돌진 패턴
			_is_charging = true
			_charge_timer = 0.55
			_charge_dir = dir_to_player
			if _sprite != null:
				_sprite.modulate = Color(1.0, 0.55, 0.25, 1.0)
			_pattern_timer = 2.0

func _fire_fan(base_dir: Vector2, count: int, spread_deg: float, spd: float) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	var step: float = deg_to_rad(spread_deg)
	var start: float = -step * float(count - 1) * 0.5
	for i in range(count):
		var d: Vector2 = base_dir.rotated(start + step * float(i))
		_spawn_bullet(d, spd)

func _fire_ring(count: int, spd: float) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	for i in range(count):
		var angle: float = (TAU / float(count)) * float(i)
		var d: Vector2 = Vector2.RIGHT.rotated(angle)
		_spawn_bullet(d, spd)

func _spawn_bullet(dir: Vector2, spd: float) -> void:
	var b: Area2D = enemy_bullet_scene.instantiate() as Area2D
	if b == null:
		return
	b.set("direction", dir)
	b.set("speed", spd)
	get_tree().current_scene.add_child(b)
	b.global_position = global_position + dir * 10.0

func _check_player_collision() -> void:
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		if col == null:
			continue
		var collider: Object = col.get_collider()
		if collider is Node and (collider as Node).is_in_group("player"):
			if collider.has_method("take_damage"):
				collider.call("take_damage", 1)
			break

func take_damage(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	
	_current_hp = maxi(0, _current_hp - amount)
	boss_hp_changed.emit(_current_hp, max_hp)
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
