extends CharacterBody2D
## 엔터 더 건전 스타일 플레이어 제어:
## - 360도 마우스 조준 회전 총기(WeaponPivot) + 5종 무기 교체([Q] 키) + 반동 + 총구 화염 + 탄피 배출
## - 스페이스바 360도 공중 구르기(Dodge Roll)
## - 액티브 스킬 1 ([E] 또는 우클릭): 공포탄 충격파 (적 탄막 전체 소거 + 광역 충격파 피해/넉백)
## - 액티브 스킬 2 ([R]): 전자동 3D 기계 포탑(오토 터렛) 설치 (9초간 가장 가까운 적 자동 조준·사격 및 적 탄환 요격)

signal player_died
signal dash_updated(cooldown_remaining: float, cooldown_total: float)
signal skills_updated(blank_rem: float, storm_rem: float, overdrive_rem: float)
signal skill_activated(skill_name: String)

const GM_SCRIPT: GDScript = preload("res://scripts/game_manager.gd")
const TURRET_SCRIPT: GDScript = preload("res://scripts/auto_turret.gd")

@export var move_speed: float = 98.0
@export var bullet_scene: PackedScene

@export var dash_speed: float = 235.0
@export var invincibility_duration: float = 1.0

# 액티브 스킬 기본 쿨타임
const BASE_BLANK_COOLDOWN: float = 8.0
const BASE_STORM_COOLDOWN: float = 13.0
const OVERDRIVE_DURATION: float = 9.0

var _is_dead: bool = false
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_total_duration: float = 0.24
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _ghost_spawn_timer: float = 0.0

var _blank_cooldown_timer: float = 0.0
var _storm_cooldown_timer: float = 0.0
var _overdrive_timer: float = 0.0

var _invincible_timer: float = 0.0
var _fire_timer: float = 0.0
var _shake_strength: float = 0.0
var _walk_time: float = 0.0
var _gun_recoil: float = 0.0
var _muzzle_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _gun_sprite: Sprite2D = $WeaponPivot/GunSprite
@onready var _muzzle_flash: Polygon2D = $WeaponPivot/GunSprite/MuzzleFlash
@onready var _camera: Camera2D = $Camera2D

func _get_gm() -> Node:
	var root_vp: Window = get_tree().root
	var gm: Node = root_vp.get_node_or_null("GameManager")
	if gm == null:
		gm = GM_SCRIPT.new()
		gm.name = "GameManager"
		root_vp.add_child(gm)
	return gm

func _ready() -> void:
	add_to_group("player")
	_sync_stats_from_manager()
	var gm: Node = _get_gm()
	if gm != null:
		if gm.has_signal("stats_changed") and not gm.is_connected("stats_changed", _sync_stats_from_manager):
			gm.connect("stats_changed", _sync_stats_from_manager)
		if gm.has_signal("skills_reset_requested") and not gm.is_connected("skills_reset_requested", _on_skills_reset_requested):
			gm.connect("skills_reset_requested", _on_skills_reset_requested)

func _sync_stats_from_manager() -> void:
	var gm: Node = _get_gm()
	if gm == null:
		return
	move_speed = float(gm.get("move_speed"))
	if _gun_sprite != null:
		var tint_val: Variant = gm.get("weapon_tint")
		if tint_val is Color:
			_gun_sprite.self_modulate = tint_val as Color

func _on_skills_reset_requested() -> void:
	_blank_cooldown_timer = 0.0
	_storm_cooldown_timer = 0.0
	skills_updated.emit(_blank_cooldown_timer, _storm_cooldown_timer, _overdrive_timer)

func _unhandled_input(event: InputEvent) -> void:
	if _is_dead or get_tree().paused:
		return
	
	# [Q] 키: 보유 무기 교체
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			var gm: Node = _get_gm()
			if gm != null:
				var owned: Array = gm.get("owned_weapons")
				if owned.size() > 1:
					var w_info: Dictionary = gm.call("cycle_weapon")
					_sync_stats_from_manager()
					skill_activated.emit("🔫 무기 교체: %s" % String(w_info.get("name", "총기")))
				else:
					skill_activated.emit("보급 상자에서 새 무기를 획득하면 [Q]로 교체할 수 있습니다!")
		elif event.keycode == KEY_E:
			_try_activate_blank_skill()
		elif event.keycode == KEY_R:
			_try_activate_storm_skill()
	
	# 마우스 우클릭: 액티브 스킬 1 (공포탄 충격파) 발동
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_try_activate_blank_skill()

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		return
	
	var gm: Node = _get_gm()
	
	# 1. 타이머 갱신 (사격 쿨타임, 구르기 쿨타임, 액티브 스킬 쿨타임, 오버드라이브 버프)
	if _fire_timer > 0.0:
		_fire_timer = maxf(0.0, _fire_timer - delta)
	
	if _muzzle_timer > 0.0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0.0 and _muzzle_flash != null:
			_muzzle_flash.visible = false
	
	if _gun_recoil > 0.01:
		_gun_recoil = lerpf(_gun_recoil, 0.0, 22.0 * delta)
	else:
		_gun_recoil = 0.0
	
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
		var total_cd: float = float(gm.get("dash_cooldown")) if gm != null else 0.82
		dash_updated.emit(_dash_cooldown_timer, total_cd)
	
	var skill_dirty: bool = false
	if _blank_cooldown_timer > 0.0:
		_blank_cooldown_timer = maxf(0.0, _blank_cooldown_timer - delta)
		skill_dirty = true
	if _storm_cooldown_timer > 0.0:
		_storm_cooldown_timer = maxf(0.0, _storm_cooldown_timer - delta)
		skill_dirty = true
	if _overdrive_timer > 0.0:
		_overdrive_timer = maxf(0.0, _overdrive_timer - delta)
		skill_dirty = true
	if skill_dirty:
		skills_updated.emit(_blank_cooldown_timer, _storm_cooldown_timer, _overdrive_timer)
	
	if _invincible_timer > 0.0:
		_invincible_timer = maxf(0.0, _invincible_timer - delta)
		if _sprite != null and not _is_dashing:
			_sprite.modulate.a = 0.35 if int(_invincible_timer * 20.0) % 2 == 0 else 1.0
	elif _sprite != null and not _is_dashing:
		_sprite.modulate = Color.WHITE
	
	_update_camera_shake(delta)
	
	# 2. 마우스 360도 조준 및 총기 회전 연출
	var mouse_pos: Vector2 = _get_aim_world_position()
	var aim_dir: Vector2 = global_position.direction_to(mouse_pos)
	if aim_dir.is_zero_approx():
		aim_dir = Vector2.RIGHT
	var aim_angle: float = aim_dir.angle()
	
	if _sprite != null and not _is_dashing and absf(mouse_pos.x - global_position.x) > 2.0:
		_sprite.flip_h = mouse_pos.x < global_position.x
	
	if _weapon_pivot != null and _gun_sprite != null:
		_weapon_pivot.rotation = aim_angle
		_weapon_pivot.z_index = -1 if aim_dir.y < -0.35 else 1
		_gun_sprite.flip_v = absf(aim_angle) > PI * 0.5
		_gun_sprite.position.x = 9.0 - _gun_recoil
	
	# 3. 스페이스바 닷지 롤(Dodge Roll) 입력 및 공중 360도 회전 모션
	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if Input.is_action_just_pressed("dash") and not _is_dashing and _dash_cooldown_timer <= 0.0:
		_start_dash(input_direction)
	
	if _is_dashing:
		_dash_timer -= delta
		_ghost_spawn_timer -= delta
		if _ghost_spawn_timer <= 0.0:
			_spawn_dash_ghost()
			_ghost_spawn_timer = 0.045
		
		var progress: float = clampf(1.0 - (_dash_timer / maxf(0.01, _dash_total_duration)), 0.0, 1.0)
		if _sprite != null:
			var roll_sign: float = -1.0 if _dash_direction.x < 0.0 else 1.0
			_sprite.position.y = -sin(progress * PI) * 7.5
			_sprite.rotation = progress * TAU * roll_sign
		
		velocity = _dash_direction * dash_speed
		move_and_slide()
		
		if _dash_timer <= 0.0:
			_end_dash()
	else:
		velocity = input_direction * move_speed
		move_and_slide()
		
		if _sprite != null:
			if velocity.length_squared() > 10.0:
				_walk_time += delta
				_sprite.position.y = -absf(sin(_walk_time * 16.0)) * 2.2
				_sprite.rotation = sin(_walk_time * 8.0) * 0.09
			else:
				_sprite.position.y = lerpf(_sprite.position.y, 0.0, 16.0 * delta)
				_sprite.rotation = lerpf(_sprite.rotation, 0.0, 16.0 * delta)
		
		_check_enemy_contact()
	
	# 4. 마우스 방향 총기 발사
	if not _is_dashing and Input.is_action_pressed("attack") and _fire_timer <= 0.0:
		shoot_to_mouse()

## [스킬 1: E / 마우스 우클릭] 공포탄 충격파 (Blank Shockwave)
## 화면의 모든 적 탄환을 즉시 소거하고 주변 적에게 충격파 피해와 넉백을 가합니다.
func _try_activate_blank_skill() -> void:
	if _blank_cooldown_timer > 0.0:
		return
	var gm: Node = _get_gm()
	var cd_mult: float = float(gm.get("skill_cooldown_mult")) if gm != null else 1.0
	_blank_cooldown_timer = BASE_BLANK_COOLDOWN * cd_mult
	_invincible_timer = maxf(_invincible_timer, 0.4)
	_shake_strength = 2.5
	
	# 1. 화면의 모든 적 탄환 즉시 소거!
	get_tree().call_group("enemy_bullets", "cancel_bullet")
	
	# 2. 반경 145px 이내 적들에게 충격파 피해 + 넉백
	var shock_dmg: int = 2 + (int(gm.get("bonus_damage")) if gm != null else 0)
	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if enemy_node is Node2D and is_instance_valid(enemy_node):
			var e2d: Node2D = enemy_node as Node2D
			var dist: float = global_position.distance_to(e2d.global_position)
			if dist <= 145.0:
				if e2d.has_method("take_damage"):
					e2d.call("take_damage", shock_dmg)
				var push_dir: Vector2 = global_position.direction_to(e2d.global_position)
				if not push_dir.is_zero_approx() and not e2d.is_in_group("boss"):
					e2d.global_position += push_dir * 26.0
	
	_spawn_blank_shockwave_vfx()
	skills_updated.emit(_blank_cooldown_timer, _storm_cooldown_timer, _overdrive_timer)
	skill_activated.emit("💥 스킬 발동: 공포탄 충격파! (적 탄막 완전 소거)")

func _spawn_blank_shockwave_vfx() -> void:
	if get_tree().current_scene == null:
		return
	# 16방향으로 퍼져나가는 푸른 공포탄 충격파 파편
	for i in range(16):
		var ang: float = (TAU / 16.0) * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var wave_part := ColorRect.new()
		wave_part.size = Vector2(6, 6)
		wave_part.color = Color(0.35, 0.92, 1.0, 0.95)
		get_tree().current_scene.add_child(wave_part)
		wave_part.global_position = global_position + dir * 10.0
		wave_part.rotation = ang
		var tw := wave_part.create_tween()
		tw.tween_property(wave_part, "global_position", global_position + dir * 125.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(wave_part, "modulate:a", 0.0, 0.26)
		tw.tween_callback(wave_part.queue_free)

## [스킬 2: R 키] 전자동 기계 포탑 소환 (Auto-Turret Deployment)
## 플레이어 전방에 9초 동안 가장 가까운 적을 자동 조준·사격하고 적 탄환을 막아주는 3D 기계 포탑을 설치합니다!
func _try_activate_storm_skill() -> void:
	if _storm_cooldown_timer > 0.0 or bullet_scene == null or get_tree().current_scene == null:
		return
	var gm: Node = _get_gm()
	var cd_mult: float = float(gm.get("skill_cooldown_mult")) if gm != null else 1.0
	_storm_cooldown_timer = BASE_STORM_COOLDOWN * cd_mult
	_overdrive_timer = OVERDRIVE_DURATION
	
	var aim_dir: Vector2 = global_position.direction_to(_get_aim_world_position())
	if aim_dir.is_zero_approx():
		aim_dir = Vector2.UP
	var deploy_pos: Vector2 = global_position + aim_dir * 20.0
	deploy_pos.x = clampf(deploy_pos.x, 38.0, 442.0)
	deploy_pos.y = clampf(deploy_pos.y, 38.0, 282.0)
	
	var turret: Node2D = TURRET_SCRIPT.new() as Node2D
	turret.name = "AutoTurret"
	turret.set("bullet_scene", bullet_scene)
	turret.set("bullet_damage", maxi(1, int(gm.get("bullet_damage")) if gm != null else 1))
	turret.set("lifetime", OVERDRIVE_DURATION)
	turret.set("turret_angle", aim_dir.angle())
	get_tree().current_scene.add_child(turret)
	turret.global_position = deploy_pos
	
	skills_updated.emit(_blank_cooldown_timer, _storm_cooldown_timer, _overdrive_timer)
	skill_activated.emit("🤖 스킬 발동: 전자동 기계 포탑 설치! (9초간 자동 사격 & 엄폐)")

func _start_dash(input_dir: Vector2) -> void:
	_is_dashing = true
	var gm: Node = _get_gm()
	var dur: float = float(gm.get("dash_duration")) if gm != null else 0.22
	var cd: float = float(gm.get("dash_cooldown")) if gm != null else 0.82
	_dash_total_duration = maxf(0.22, dur)
	_dash_timer = _dash_total_duration
	_dash_cooldown_timer = cd
	_ghost_spawn_timer = 0.0
	
	if input_dir.is_zero_approx():
		_dash_direction = global_position.direction_to(_get_aim_world_position())
		if _dash_direction.is_zero_approx():
			_dash_direction = Vector2.RIGHT
	else:
		_dash_direction = input_dir.normalized()
	
	if _weapon_pivot != null:
		_weapon_pivot.visible = false
	_spawn_roll_dust()
	dash_updated.emit(_dash_cooldown_timer, cd)

func _end_dash() -> void:
	_is_dashing = false
	_invincible_timer = maxf(_invincible_timer, 0.08)
	if _sprite != null:
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
		_sprite.modulate = Color.WHITE
	if _weapon_pivot != null:
		_weapon_pivot.visible = true
	_spawn_roll_dust()

func _spawn_roll_dust() -> void:
	if get_tree().current_scene == null:
		return
	for i in range(4):
		var puff := ColorRect.new()
		puff.size = Vector2(3, 3)
		puff.color = Color(0.75, 0.78, 0.86, 0.7)
		get_tree().current_scene.add_child(puff)
		puff.global_position = global_position + Vector2(randf_range(-4, 4), 4)
		var offset := Vector2(randf_range(-10, 10), randf_range(-4, 6))
		var tw := puff.create_tween()
		tw.tween_property(puff, "global_position", puff.global_position + offset, 0.2)
		tw.parallel().tween_property(puff, "modulate:a", 0.0, 0.2)
		tw.tween_callback(puff.queue_free)

func _spawn_dash_ghost() -> void:
	if _sprite == null or _sprite.texture == null or get_tree().current_scene == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = _sprite.texture
	ghost.flip_h = _sprite.flip_h
	ghost.modulate = Color(0.45, 0.85, 1.0, 0.45)
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = _sprite.global_position
	ghost.global_rotation = _sprite.global_rotation
	ghost.global_scale = _sprite.global_scale
	
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.14)
	tw.tween_callback(ghost.queue_free)

func _check_enemy_contact() -> void:
	if is_invincible():
		return
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		if col == null:
			continue
		var collider: Object = col.get_collider()
		if collider is Node and (collider as Node).is_in_group("enemies"):
			take_damage(1)
			return

func is_invincible() -> bool:
	return _is_dashing or _invincible_timer > 0.0 or _is_dead

func take_damage(amount: int) -> void:
	if is_invincible() or amount <= 0:
		return
	
	_invincible_timer = invincibility_duration
	_shake_strength = 4.0
	
	if _sprite != null:
		_sprite.self_modulate = Color(3.0, 0.4, 0.4, 1.0)
		var tw := create_tween()
		tw.tween_property(_sprite, "self_modulate", Color.WHITE, 0.15)
	
	var gm: Node = _get_gm()
	var died: bool = false
	if gm != null:
		died = bool(gm.call("damage_player", amount))
	
	if died:
		_die()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if _weapon_pivot != null:
		_weapon_pivot.visible = false
	if _sprite != null:
		_sprite.modulate = Color(0.4, 0.4, 0.4, 0.8)
		_sprite.rotation = PI * 0.5
	player_died.emit()

func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_strength > 0.05:
		_camera.offset = Vector2(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength)
		)
		_shake_strength = lerpf(_shake_strength, 0.0, 12.0 * delta)
	else:
		_shake_strength = 0.0
		_camera.offset = Vector2.ZERO

## 3D 원근 카메라가 활성화된 경우 3D 바닥/총기 평면으로 마우스 레이캐스트하여 정확한 조준 좌표를 반환합니다.
func _get_aim_world_position() -> Vector2:
	var vp: Viewport = get_viewport()
	if vp != null:
		var cam3d: Camera3D = vp.get_camera_3d()
		if cam3d != null:
			var mpos: Vector2 = vp.get_mouse_position()
			var ray_origin: Vector3 = cam3d.project_ray_origin(mpos)
			var ray_dir: Vector3 = cam3d.project_ray_normal(mpos)
			var aim_plane := Plane(Vector3.UP, 0.38)
			var hit: Variant = aim_plane.intersects_ray(ray_origin, ray_dir)
			if hit is Vector3:
				var h3: Vector3 = hit as Vector3
				return Vector2(h3.x * 16.0, h3.z * 16.0)
	return get_global_mouse_position()

func shoot_to_mouse() -> void:
	if bullet_scene == null:
		push_warning("[Player] 인스펙터의 Bullet Scene 칸에 bullet.tscn 파일이 연결되지 않았습니다!")
		return
	
	var gm: Node = _get_gm()
	var cd: float = float(gm.get("fire_cooldown")) if gm != null else 0.25
	_fire_timer = maxf(0.05, cd)
	
	# 총기 반동 + 총구 화염 + 탄피 배출
	_gun_recoil = 3.8
	if _muzzle_flash != null:
		_muzzle_flash.visible = true
		_muzzle_timer = 0.045
	
	var mouse_pos: Vector2 = _get_aim_world_position()
	var base_dir: Vector2 = global_position.direction_to(mouse_pos)
	if base_dir.is_zero_approx():
		base_dir = Vector2.RIGHT
	
	_spawn_shell_casing(base_dir)
	
	var count: int = int(gm.get("multi_shot")) if gm != null else 1
	var spread_deg: float = float(gm.get("weapon_spread_deg")) if gm != null else 6.0
	var spread_step: float = deg_to_rad(maxf(4.0, spread_deg))
	var start_angle: float = -spread_step * float(count - 1) * 0.5
	
	# 단발 총기라도 기관단총 등 탄퍼짐이 있는 경우 미세 산탄 적용
	var random_jitter: float = deg_to_rad(randf_range(-spread_deg * 0.35, spread_deg * 0.35)) if count == 1 else 0.0
	
	for i in range(count):
		var angle_offset: float = start_angle + spread_step * float(i) + random_jitter
		var shoot_dir: Vector2 = base_dir.rotated(angle_offset)
		_spawn_single_bullet(shoot_dir, gm)

func _spawn_single_bullet(shoot_dir: Vector2, gm: Node, scale_bonus: float = 1.0) -> void:
	var bullet: Area2D = bullet_scene.instantiate() as Area2D
	if bullet == null or get_tree().current_scene == null:
		return
	
	bullet.set("direction", shoot_dir)
	if gm != null:
		bullet.set("damage", int(gm.get("bullet_damage")))
		bullet.set("speed", float(gm.get("bullet_speed")))
		bullet.scale = Vector2.ONE * float(gm.get("bullet_scale")) * scale_bonus
		var w_tint: Variant = gm.get("weapon_tint")
		if w_tint is Color:
			bullet.modulate = w_tint as Color
	
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + shoot_dir * 10.0
	bullet.global_rotation = shoot_dir.angle()

func _spawn_shell_casing(shoot_dir: Vector2) -> void:
	if get_tree().current_scene == null:
		return
	var shell := ColorRect.new()
	shell.size = Vector2(3, 2)
	shell.color = Color(0.95, 0.78, 0.28, 0.95)
	get_tree().current_scene.add_child(shell)
	
	var eject_dir: Vector2 = -shoot_dir.rotated(randf_range(0.7, 1.3))
	shell.global_position = global_position + shoot_dir * 3.0
	shell.rotation = randf_range(0.0, TAU)
	
	var land_pos: Vector2 = shell.global_position + eject_dir * randf_range(10.0, 18.0) + Vector2(0, randf_range(2.0, 6.0))
	var tw := shell.create_tween()
	tw.tween_property(shell, "global_position", land_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(shell, "rotation", shell.rotation + randf_range(4.0, 8.0), 0.18)
	tw.tween_interval(3.5)
	tw.tween_property(shell, "modulate:a", 0.0, 0.5)
	tw.tween_callback(shell.queue_free)
