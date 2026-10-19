extends Node2D
## [R] 스킬로 소환되는 전자동 기계 포탑 (Auto-Turret):
## 일정 시간(9초) 동안 필드에 유지되며 가장 가까운 적을 360도 자동 추적해 기관총 탄환을 연사하고,
## 포탑에 닿는 적 탄환을 요격해 엄폐물 역할도 수행합니다.

var bullet_scene: PackedScene = null
var bullet_damage: int = 1
var bullet_speed: float = 320.0
var lifetime: float = 9.0
var max_lifetime: float = 9.0
var fire_interval: float = 0.28

var turret_angle: float = 0.0
var barrel_recoil: float = 0.0
var _fire_timer: float = 0.15

func _ready() -> void:
	add_to_group("turrets")
	max_lifetime = lifetime
	_spawn_deploy_sparks()

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		_spawn_deploy_sparks()
		queue_free()
		return
	
	if barrel_recoil > 0.01:
		barrel_recoil = lerpf(barrel_recoil, 0.0, 20.0 * delta)
	else:
		barrel_recoil = 0.0
	
	# 포탑 주변(반경 11px)을 지나가는 적 탄환 요격(엄폐물 기능)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b is Node2D and is_instance_valid(b):
			var b2d: Node2D = b as Node2D
			if global_position.distance_to(b2d.global_position) <= 11.0:
				if b2d.has_method("cancel_bullet"):
					b2d.call("cancel_bullet")
				else:
					b2d.queue_free()
	
	# 가장 가까운 생존 몬스터 탐색 및 360도 포신 회전 조준
	var target: Node2D = _find_nearest_enemy()
	if target != null:
		var dir: Vector2 = global_position.direction_to(target.global_position)
		if not dir.is_zero_approx():
			var desired_angle: float = dir.angle()
			turret_angle = lerp_angle(turret_angle, desired_angle, minf(1.0, 14.0 * delta))
		
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = fire_interval
			_shoot_at_target(Vector2(cos(turret_angle), sin(turret_angle)))
	else:
		# 적이 없을 때는 천천히 주변 경계 회전
		turret_angle += 1.2 * delta

func _find_nearest_enemy() -> Node2D:
	var best_enemy: Node2D = null
	var best_dist_sq: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and is_instance_valid(node):
			var e2d: Node2D = node as Node2D
			var d2: float = global_position.distance_squared_to(e2d.global_position)
			if d2 < best_dist_sq:
				best_dist_sq = d2
				best_enemy = e2d
	return best_enemy

func _shoot_at_target(shoot_dir: Vector2) -> void:
	if bullet_scene == null or get_tree().current_scene == null:
		return
	barrel_recoil = 3.5
	
	var bullet: Area2D = bullet_scene.instantiate() as Area2D
	if bullet == null:
		return
	bullet.set("direction", shoot_dir)
	bullet.set("damage", bullet_damage)
	bullet.set("speed", bullet_speed)
	bullet.scale = Vector2.ONE * 0.92
	bullet.modulate = Color(0.45, 0.95, 1.0) # 포탑 전용 시안 트레이서 탄환
	
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + shoot_dir * 11.0
	bullet.global_rotation = shoot_dir.angle()

func _spawn_deploy_sparks() -> void:
	if get_tree().current_scene == null:
		return
	for i in range(8):
		var ang: float = (TAU / 8.0) * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var spark := ColorRect.new()
		spark.size = Vector2(3, 3)
		spark.color = Color(0.45, 0.95, 1.0, 0.9)
		get_tree().current_scene.add_child(spark)
		spark.global_position = global_position + dir * 4.0
		var tw := spark.create_tween()
		tw.tween_property(spark, "global_position", global_position + dir * 18.0, 0.22)
		tw.parallel().tween_property(spark, "modulate:a", 0.0, 0.22)
		tw.tween_callback(spark.queue_free)
