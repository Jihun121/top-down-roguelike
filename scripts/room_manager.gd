extends Node2D
## 각 던전 방(World)의 루트에 부착되어 잔여 몬스터 추적, 탄막 소거(Bullet Cancel), 문 개방, 보급 상자 알림을 제어하는 매니저

@export var room_number: int = 1
@export var is_rest_room: bool = false
@export var offer_upgrade_on_clear: bool = false

const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const DOOR_SCENE: PackedScene = preload("res://scenes/door.tscn")
const GM_SCRIPT: GDScript = preload("res://scripts/game_manager.gd")
const STAGE_25D_SCRIPT: GDScript = preload("res://scripts/stage_25d_builder.gd")

var _alive_enemies: int = 0
var _room_cleared: bool = false
var _hud: CanvasLayer = null
var _door: Node2D = null
var _stage_3d: Node3D = null

func _get_gm() -> Node:
	var root_vp: Window = get_tree().root
	var gm: Node = root_vp.get_node_or_null("GameManager")
	if gm == null:
		gm = GM_SCRIPT.new()
		gm.name = "GameManager"
		root_vp.add_child(gm)
	return gm

func _ready() -> void:
	var gm: Node = _get_gm()
	gm.set("current_room", room_number)
	
	# 1. HUD 생성 및 연결
	_setup_hud()
	
	# 2. 북쪽 중앙 벽(타일 좌표 14,0 및 15,0)에 출입문(Door) 배치 및 타일 벽 개구부 확보
	_setup_door()
	
	# 3. 2.5D (Node3D + Sprite3D + 실시간 3D 조명/그림자/3D 보급상자) 스테이지 빌더 가동
	_stage_3d = STAGE_25D_SCRIPT.new()
	_stage_3d.name = "Stage25D"
	add_child(_stage_3d)
	_stage_3d.call("setup_from_room", self)
	
	# 4. 플레이어 시그널 연결 (체력/구르기/액티브 스킬/무기 교체)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_signal("player_died"):
			player.connect("player_died", _on_player_died)
		if _hud != null:
			if player.has_signal("dash_updated"):
				player.connect("dash_updated", Callable(_hud, "update_dash_status"))
			if player.has_signal("skills_updated"):
				player.connect("skills_updated", Callable(_hud, "update_skills_status"))
			if player.has_signal("skill_activated"):
				player.connect("skill_activated", _on_player_skill_activated)
	
	# 5. 방 곳곳에 배치된 랜덤 보급 상자(TreasureChest) 연결
	for node in get_children():
		if node.is_in_group("chests") and node.has_signal("chest_opened"):
			node.connect("chest_opened", _on_chest_opened)
	
	# 6. 방 안의 모든 몬스터 탐색 및 사망 시그널(died) 구독
	_alive_enemies = 0
	for node in get_children():
		if node.is_in_group("enemies") or node.has_signal("died"):
			_register_enemy(node)
	
	_update_hud_enemy_count()
	
	# 방 입장 배너 표시
	if _hud != null and gm != null:
		_hud.call("_refresh_all")
		_hud.call("show_banner", "ROOM %d / %d — %s" % [
			room_number,
			int(gm.get("MAX_ROOMS")),
			String(gm.call("get_room_title", room_number))
		], 1.8)
	
	if _alive_enemies == 0:
		_room_cleared = true
		if _door != null and _door.has_method("open"):
			_door.call("open")
		_update_hud_enemy_count()

func _setup_hud() -> void:
	_hud = get_node_or_null("HUD") as CanvasLayer
	if _hud == null and HUD_SCENE != null:
		_hud = HUD_SCENE.instantiate() as CanvasLayer
		add_child(_hud)

func _setup_door() -> void:
	var gm: Node = _get_gm()
	var max_rooms: int = int(gm.get("MAX_ROOMS")) if gm != null else 5
	_door = get_node_or_null("Door") as Node2D
	if room_number >= max_rooms:
		if _door != null:
			_door.visible = false
		return
	
	var wall_layer: TileMapLayer = get_node_or_null("WallLayer") as TileMapLayer
	if wall_layer != null:
		wall_layer.erase_cell(Vector2i(14, 0))
		wall_layer.erase_cell(Vector2i(15, 0))
	
	if _door == null and DOOR_SCENE != null:
		_door = DOOR_SCENE.instantiate() as Node2D
		_door.position = Vector2(240, 8)
		add_child(_door)

func _register_enemy(enemy: Node) -> void:
	_alive_enemies += 1
	if enemy.has_signal("died"):
		enemy.connect("died", _on_enemy_died, CONNECT_ONE_SHOT)
	if enemy.has_signal("boss_hp_changed") and _hud != null:
		enemy.connect("boss_hp_changed", Callable(_hud, "update_boss_hp"))
		var max_hp_val: Variant = enemy.get("max_hp")
		if max_hp_val != null:
			_hud.call("update_boss_hp", int(max_hp_val), int(max_hp_val))

func _on_enemy_died() -> void:
	if _room_cleared:
		return
	_alive_enemies = maxi(0, _alive_enemies - 1)
	_update_hud_enemy_count()
	
	if _alive_enemies == 0:
		_on_room_cleared()

func _on_room_cleared() -> void:
	_room_cleared = true
	var gm: Node = _get_gm()
	var max_rooms: int = int(gm.get("MAX_ROOMS")) if gm != null else 5
	
	# [Bullet Cancel] 화면에 남아 있는 모든 적 탄환 즉시 소거
	get_tree().call_group("enemy_bullets", "cancel_bullet")
	
	# 최종 보스방(5번 방) 클리어 시 승리 처리
	if room_number >= max_rooms:
		if _hud != null:
			_hud.call("update_boss_hp", 0, 1)
			_hud.call("show_banner", "★ 최종 보스 '탄약 대왕' 처치 완료! ★", 1.8)
		var timer := get_tree().create_timer(0.65)
		timer.timeout.connect(func() -> void:
			if _hud != null:
				_hud.call("show_victory")
		)
		return
	
	# 교전 구역 클리어 시 팝업 없이 즉시 북쪽 성문 개방! (아이템은 맵 곳곳의 보급 상자에서 파밍)
	if _door != null and _door.has_method("open"):
		_door.call("open")
	if _hud != null:
		_hud.call("show_banner", "★ 구역 클리어! 보급 상자를 확인하고 ▲ 북쪽 성문으로 이동하세요 ★", 2.4)

func _on_chest_opened(loot_info: Dictionary = {}) -> void:
	if _hud == null:
		return
	var cat: String = String(loot_info.get("category", "보급"))
	var title: String = String(loot_info.get("title", "아이템"))
	var desc: String = String(loot_info.get("desc", ""))
	_hud.call("_refresh_all")
	_hud.call("show_banner", "📦 [%s 획득] %s — %s" % [cat, title, desc], 2.8)

func _on_player_skill_activated(msg: String) -> void:
	if _hud != null:
		_hud.call("_refresh_all")
		_hud.call("show_banner", msg, 1.8)

func _on_player_died() -> void:
	get_tree().call_group("enemy_bullets", "cancel_bullet")
	var timer := get_tree().create_timer(0.45)
	timer.timeout.connect(func() -> void:
		if _hud != null:
			_hud.call("show_game_over")
	)

func _update_hud_enemy_count() -> void:
	if _hud != null:
		_hud.call("update_enemy_count", _alive_enemies, is_rest_room)
