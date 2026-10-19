extends CharacterBody2D
## 근중거리 추격형 몬스터 통합 제어 (방별 고유 몬스터 아키타입 지원):
## - "bullet_kin"  (Room 1): 황동 총탄 일족 — 뒤뚱거리며 권총 단발 조준 사격
## - "bullat"      (Room 1): 공포의 탄환 박쥐 — 공중 날개짓 비행 + 급가속 돌진 & 사망 시 4방향 탄막 방출
## - "grenade_kin" (Room 2): 고블린 유탄병 — 통통 튀며 대각선 4방향 유탄 발사 & 사망 시 6방향 파편 폭발
## - "gun_nut"     (Room 4): 중장갑 흑철 총기 기사 — 대형 장갑 기사(HP 9)로 7갈래 초승달 검기 탄막 파동 발사

signal died

@export var monster_type: String = "bullet_kin"
@export var move_speed: float = 44.0
@export var max_hp: int = 3
@export var contact_damage: int = 1
@export var fire_interval: float = 2.2
@export var enemy_bullet_scene: PackedScene = preload("res://scenes/enemy_bullet.tscn")

const TEX_BULLET_KIN: Texture2D = preload("res://assets/gungeon/bullet_kin.png")
const TEX_BULLAT: Texture2D = preload("res://assets/gungeon/bullat.png")
const TEX_GRENADE_KIN: Texture2D = preload("res://assets/gungeon/grenade_kin.png")
const TEX_GUN_NUT: Texture2D = preload("res://assets/gungeon/gun_nut.png")

var _current_hp: int
var _is_dead: bool = false
var _target: Node2D = null
var _fire_timer: float = 1.5
var _walk_time: float = 0.0
var _swoop_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_pivot: Node2D = get_node_or_null("WeaponPivot") as Node2D
@onready var _gun_sprite: Sprite2D = get_node_or_null("WeaponPivot/GunSprite") as Sprite2D
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	_apply_monster_archetype()
	_current_hp = max_hp
	_fire_timer = randf_range(0.8, fire_interval)
	_walk_time = randf_range(0.0, TAU)
	_target = get_tree().get_first_node_in_group("player") as Node2D

func _apply_monster_archetype() -> void:
	match monster_type:
		"bullat":
			if _sprite != null:
				_sprite.texture = TEX_BULLAT
			if _weapon_pivot != null:
				_weapon_pivot.visible = false
			move_speed = 62.0
			max_hp = 2
			fire_interval = 2.4
		"grenade_kin":
			if _sprite != null:
				_sprite.texture = TEX_GRENADE_KIN
			if _weapon_pivot != null:
				_weapon_pivot.visible = false
			move_speed = 54.0
			max_hp = 4
			fire_interval = 2.0
		"gun_nut":
			if _sprite != null:
				_sprite.texture = TEX_GUN_NUT
				_sprite.scale = Vector2(1.35, 1.35)
			if _weapon_pivot != null:
				_weapon_pivot.visible = false
			move_speed = 36.0
			max_hp = 9
			fire_interval = 2.1
		_:
			if _sprite != null:
				_sprite.texture = TEX_BULLET_KIN
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
	
	var direction: Vector2 = global_position.direction_to(_target.global_position)
	var angle: float = direction.angle()
	if _sprite != null and absf(direction.x) > 0.1:
		_sprite.flip_h = direction.x < 0.0
	
	if _weapon_pivot != null and _weapon_pivot.visible and _gun_sprite != null:
		_weapon_pivot.rotation = angle
		_gun_sprite.flip_v = absf(angle) > PI * 0.5
	
	# 몬스터 종류별 고유 모션 및 이동 속도 연출
	_walk_time += delta
	var cur_spd: float = move_speed
	if _sprite != null:
		match monster_type:
			"bullat":
				# 공중에서 빠르게 날개짓하며 주기적으로 급가속 비행
				_sprite.position.y = -3.8 - sin(_walk_time * 22.0) * 2.2
				_sprite.rotation = sin(_walk_time * 11.0) * 0.14
				if _swoop_timer > 0.0:
					_swoop_timer -= delta
					cur_spd = move_speed * 1.75
			"grenade_kin":
				# 통통 크게 튀어오르는 수류탄 점프 모션
				_sprite.position.y = -absf(sin(_walk_time * 15.0)) * 3.8
				_sprite.rotation = sin(_walk_time * 7.5) * 0.12
			"gun_nut":
				# 묵직한 중장갑 기사의 발걸음
				_sprite.position.y = -absf(sin(_walk_time * 8.0)) * 1.4
				_sprite.rotation = sin(_walk_time * 4.0) * 0.05
			_:
				_sprite.position.y = -absf(sin(_walk_time * 12.0)) * 1.8
				_sprite.rotation = sin(_walk_time * 6.0) * 0.08
	
	velocity = direction * cur_spd
	move_and_slide()
	
	# 몬스터 종류별 고유 공격 패턴
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval + randf_range(-0.25, 0.25)
		_execute_attack(direction)
	
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

func _execute_attack(dir: Vector2) -> void:
	match monster_type:
		"bullat":
			# 급가속 돌진 + 전방 빠른 침탄 발사
			_swoop_timer = 0.55
			_spawn_bullet(dir, 145.0, Color(0.85, 0.45, 1.0))
		"grenade_kin":
			# X자 대각선 4방향 유탄 발사
			for i in range(4):
				var ang: float = PI * 0.25 + (PI * 0.5) * float(i)
				_spawn_bullet(Vector2(cos(ang), sin(ang)), 110.0, Color(1.0, 0.65, 0.25))
		"gun_nut":
			# 7갈래 초승달 검기 탄막 파동 (Sword Wave)
			var count: int = 7
			var step: float = deg_to_rad(11.0)
			var start: float = -step * float(count - 1) * 0.5
			for i in range(count):
				var d: Vector2 = dir.rotated(start + step * float(i))
				_spawn_bullet(d, 140.0, Color(1.0, 0.3, 0.35), 1.15)
		_:
			_spawn_bullet(dir, 115.0)

func _spawn_bullet(dir: Vector2, spd: float, tint: Color = Color.WHITE, sc: float = 1.0) -> void:
	if enemy_bullet_scene == null or get_tree().current_scene == null:
		return
	var b: Area2D = enemy_bullet_scene.instantiate() as Area2D
	if b == null:
		return
	b.set("direction", dir)
	b.set("speed", spd)
	b.modulate = tint
	b.scale = Vector2.ONE * sc
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
	
	# 탄환 박쥐(bullat)나 고블린 유탄병(grenade_kin)은 처치 시 마지막 유언 탄막을 방출
	if monster_type == "grenade_kin":
		for i in range(6):
			var ang: float = (TAU / 6.0) * float(i)
			_spawn_bullet(Vector2(cos(ang), sin(ang)), 105.0, Color(1.0, 0.72, 0.25))
	elif monster_type == "bullat":
		for i in range(4):
			var ang: float = (TAU / 4.0) * float(i)
			_spawn_bullet(Vector2(cos(ang), sin(ang)), 100.0, Color(0.85, 0.45, 1.0))
	
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.set("total_kills", int(gm.get("total_kills")) + 1)
	died.emit()
	queue_free()
