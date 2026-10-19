extends CharacterBody2D
## 원거리 정예 몬스터 통합 제어 (방별 고유 원거리 몬스터 아키타입 지원):
## - "red_shotgun"  (Room 2): 붉은 산탄총 일족 — 4갈래 산탄 발사
## - "sniper_kin"   (Room 3): 저격수 일족 — 장거리 유지 + 초고속 정밀 스나이퍼 탄환 발사
## - "blue_shotgun" (Room 3): 푸른 산탄총 일족 — 5갈래 + 4갈래 2연속 더블 배럴 산탄 발사
## - "gunjurer"     (Room 4 & 5): 건전 탄환 흑마법사 — 공중 부유 이동 + 8방향 회전 마법 탄막 고리 소환

signal died

@export var monster_type: String = "red_shotgun"
@export var move_speed: float = 38.0
@export var max_hp: int = 4
@export var preferred_distance: float = 115.0
@export var fire_interval: float = 2.1
@export var enemy_bullet_scene: PackedScene = preload("res://scenes/enemy_bullet.tscn")

const TEX_RED_SHOTGUN: Texture2D = preload("res://assets/gungeon/shotgun_kin.png")
const TEX_SNIPER_KIN: Texture2D = preload("res://assets/gungeon/sniper_kin.png")
const TEX_BLUE_SHOTGUN: Texture2D = preload("res://assets/gungeon/blue_shotgun_kin.png")
const TEX_GUNJURER: Texture2D = preload("res://assets/gungeon/gunjurer.png")

var _current_hp: int
var _is_dead: bool = false
var _target: Node2D = null
var _fire_timer: float = 1.2
var _strafe_dir: float = 1.0
var _strafe_timer: float = 2.0
var _walk_time: float = 0.0
var _ring_phase: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_pivot: Node2D = get_node_or_null("WeaponPivot") as Node2D
@onready var _gun_sprite: Sprite2D = get_node_or_null("WeaponPivot/GunSprite") as Sprite2D
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_apply_monster_archetype()
	_current_hp = max_hp
	_fire_timer = randf_range(0.9, fire_interval)
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	_walk_time = randf_range(0.0, TAU)
	_target = get_tree().get_first_node_in_group("player") as Node2D

func _apply_monster_archetype() -> void:
	match monster_type:
		"sniper_kin":
			if _sprite != null:
				_sprite.texture = TEX_SNIPER_KIN
			if _weapon_pivot != null:
				_weapon_pivot.visible = true
			move_speed = 42.0
			max_hp = 4
			preferred_distance = 155.0
			fire_interval = 2.0
		"blue_shotgun":
			if _sprite != null:
				_sprite.texture = TEX_BLUE_SHOTGUN
			if _weapon_pivot != null:
				_weapon_pivot.visible = true
			move_speed = 42.0
			max_hp = 6
			preferred_distance = 105.0
			fire_interval = 2.2
		"gunjurer":
			if _sprite != null:
				_sprite.texture = TEX_GUNJURER
			if _weapon_pivot != null:
				_weapon_pivot.visible = false
			move_speed = 46.0
			max_hp = 6
			preferred_distance = 125.0
			fire_interval = 2.1
		_:
			if _sprite != null:
				_sprite.texture = TEX_RED_SHOTGUN
			if _weapon_pivot != null:
				_weapon_pivot.visible = true

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
	
	if _weapon_pivot != null and _weapon_pivot.visible and _gun_sprite != null:
		_weapon_pivot.rotation = angle
		_gun_sprite.flip_v = absf(angle) > PI * 0.5
	
	_walk_time += delta
	if _sprite != null:
		if monster_type == "gunjurer":
			# 마법사는 공중에 살짝 떠서 미끄러지듯 부유
			_sprite.position.y = -3.2 - sin(_walk_time * 6.0) * 1.6
			_sprite.rotation = sin(_walk_time * 3.0) * 0.05
		else:
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
		move_vec = dir.orthogonal() * _strafe_dir * 0.8
	
	velocity = move_vec * move_speed
	move_and_slide()
	
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_execute_ranged_attack(dir)

func _execute_ranged_attack(base_dir: Vector2) -> void:
	match monster_type:
		"sniper_kin":
			# 초고속 정밀 저격탄 발사
			_spawn_bullet(base_dir, 215.0, Color(1.0, 0.25, 0.3), 1.15)
		"blue_shotgun":
			# 1차 5갈래 푸른 산탄 + 0.22초 뒤 2차 4갈래 연속 산탄
			_shoot_spread(base_dir, 5, 9.5, 135.0, Color(0.45, 0.85, 1.0))
			var timer := get_tree().create_timer(0.22)
			timer.timeout.connect(func() -> void:
				if not _is_dead and is_inside_tree():
					_shoot_spread(base_dir, 4, 11.0, 145.0, Color(0.45, 0.85, 1.0))
			)
		"gunjurer":
			# 8방향 회전 비전 마법 탄막 고리 + 조준 마력탄 2발
			_ring_phase += 0.35
			for i in range(8):
				var ang: float = _ring_phase + (TAU / 8.0) * float(i)
				_spawn_bullet(Vector2(cos(ang), sin(ang)), 115.0, Color(0.82, 0.42, 1.0))
			_shoot_spread(base_dir, 2, 10.0, 150.0, Color(0.4, 1.0, 0.85))
		_:
			# 기본 붉은 산탄총 일족: 4갈래 산탄
			_shoot_spread(base_dir, 4, 10.0, 125.0, Color.WHITE)

func _shoot_spread(base_dir: Vector2, count: int, deg_step: float, spd: float, tint: Color) -> void:
	var step: float = deg_to_rad(deg_step)
	var start: float = -step * float(count - 1) * 0.5
	for i in range(count):
		var d: Vector2 = base_dir.rotated(start + step * float(i))
		_spawn_bullet(d, spd, tint)

func _spawn_bullet(d: Vector2, spd: float, tint: Color = Color.WHITE, sc: float = 1.0) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	var bullet: Area2D = enemy_bullet_scene.instantiate() as Area2D
	if bullet == null:
		return
	bullet.set("direction", d)
	bullet.set("speed", spd)
	bullet.modulate = tint
	bullet.scale = Vector2.ONE * sc
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
