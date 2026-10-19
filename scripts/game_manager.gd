extends Node
## 게임 전역 상태, 무기 인벤토리, 보급 상자 랜덤 루팅(무기/장비/물약), 스킬 쿨타임 및 방 전환을 관리하는 싱글톤

signal stats_changed
signal hp_changed(current_hp: int, max_hp: int)
signal weapon_changed(weapon_info: Dictionary)
signal skills_reset_requested

const MAX_ROOMS: int = 5
const ROOM_SCENES: Array[String] = [
	"res://world.tscn",
	"res://scenes/room_2.tscn",
	"res://scenes/room_3.tscn",
	"res://scenes/room_4.tscn",
	"res://scenes/room_5.tscn",
]

const ROOM_TITLES: Array[String] = [
	"시작의 방 — 지하 성채 입구",
	"교전 구역 I — 탄약 회랑",
	"교전 구역 II — 십자 포화실",
	"교전 구역 III — 성채 무기고",
	"심연의 보스방 — 탄약 대왕의 알현실",
]

# 5종 총기 데이터베이스
const WEAPON_DB: Dictionary = {
	"pistol": {
		"id": "pistol",
		"name": "러스트 사이드암",
		"desc": "신뢰성 높은 건저니어 기본 반자동 권총",
		"base_damage": 1,
		"cooldown": 0.25,
		"pellets": 1,
		"spread_deg": 3.0,
		"speed": 275.0,
		"scale": 1.0,
		"tint": Color(1.0, 1.0, 1.0),
	},
	"shotgun": {
		"id": "shotgun",
		"name": "건전 헌터 산탄총",
		"desc": "5발의 산탄을 부채꼴로 동시 발사하는 근중거리 제압용 샷건",
		"base_damage": 1,
		"cooldown": 0.48,
		"pellets": 5,
		"spread_deg": 8.0,
		"speed": 255.0,
		"scale": 0.95,
		"tint": Color(1.0, 0.72, 0.38),
	},
	"smg": {
		"id": "smg",
		"name": "황동 기관단총",
		"desc": "압도적인 연사 속도로 탄막을 퍼붓는 속사형 기관단총",
		"base_damage": 1,
		"cooldown": 0.11,
		"pellets": 1,
		"spread_deg": 6.5,
		"speed": 300.0,
		"scale": 0.88,
		"tint": Color(1.0, 0.92, 0.42),
	},
	"revolver": {
		"id": "revolver",
		"name": "헤비 매그넘 리볼버",
		"desc": "단발 파괴력과 탄속이 극대화된 대구경 결전 리볼버",
		"base_damage": 3,
		"cooldown": 0.40,
		"pellets": 1,
		"spread_deg": 1.0,
		"speed": 380.0,
		"scale": 1.35,
		"tint": Color(1.0, 0.52, 0.52),
	},
	"plasma": {
		"id": "plasma",
		"name": "아케인 플라즈마 건",
		"desc": "푸른 고에너지 마력탄 2발을 동시에 고속 사격하는 마도 총기",
		"base_damage": 2,
		"cooldown": 0.23,
		"pellets": 2,
		"spread_deg": 4.5,
		"speed": 330.0,
		"scale": 1.15,
		"tint": Color(0.45, 0.92, 1.0),
	},
}

# 보급 상자 랜덤 드롭 아이템 풀 (무기 / 장비 / 물약)
const LOOT_POOL: Array[Dictionary] = [
	# --- 무기 (Weapons) ---
	{
		"id": "weapon_shotgun",
		"category": "무기",
		"weapon_id": "shotgun",
		"title": "건전 헌터 산탄총",
		"desc": "5발 산탄 동시 발사! ([Q] 키로 보유 무기 교체 가능)",
		"color": Color(1.0, 0.72, 0.32),
	},
	{
		"id": "weapon_smg",
		"category": "무기",
		"weapon_id": "smg",
		"title": "황동 기관단총",
		"desc": "초고속 연사 기관단총! ([Q] 키로 보유 무기 교체 가능)",
		"color": Color(1.0, 0.88, 0.35),
	},
	{
		"id": "weapon_revolver",
		"category": "무기",
		"weapon_id": "revolver",
		"title": "헤비 매그넘 리볼버",
		"desc": "고화력 대구경 리볼버! ([Q] 키로 보유 무기 교체 가능)",
		"color": Color(1.0, 0.48, 0.48),
	},
	{
		"id": "weapon_plasma",
		"category": "무기",
		"weapon_id": "plasma",
		"title": "아케인 플라즈마 건",
		"desc": "2연발 고에너지 마력탄! ([Q] 키로 보유 무기 교체 가능)",
		"color": Color(0.42, 0.92, 1.0),
	},
	# --- 장비 / 패시브 유물 (Equipment) ---
	{
		"id": "equip_armor",
		"category": "장비",
		"title": "납탄 방탄복",
		"desc": "최대 체력 +1 증가 및 체력 ♥ +2 즉시 회복",
		"color": Color(0.55, 0.85, 1.0),
	},
	{
		"id": "equip_boots",
		"category": "장비",
		"title": "신속의 박차 부츠",
		"desc": "이동 속도 +18% 증가 & 구르기 쿨타임 -20% 감소",
		"color": Color(0.5, 1.0, 0.65),
	},
	{
		"id": "equip_powder",
		"category": "장비",
		"title": "대구경 화약통",
		"desc": "모든 무기의 탄환 공격력 +1 영구 증가",
		"color": Color(1.0, 0.55, 0.4),
	},
	{
		"id": "equip_splitter",
		"category": "장비",
		"title": "프리즘 총열 분열기",
		"desc": "모든 무기의 동시 발사 탄환 수 +1발 추가",
		"color": Color(0.85, 0.6, 1.0),
	},
	{
		"id": "equip_crest",
		"category": "장비",
		"title": "고대 총잡이의 인장",
		"desc": "액티브 스킬(E/R) 쿨타임 -25% 감소 & 연사력 +15% 증가",
		"color": Color(0.45, 0.95, 0.9),
	},
	# --- 회복 물약 & 전술 보급품 (Potions) ---
	{
		"id": "potion_heal",
		"category": "물약",
		"title": "선홍빛 회복 물약",
		"desc": "즉시 체력 ♥ +2 회복 & 스킬 쿨타임 50% 충전",
		"color": Color(0.4, 1.0, 0.55),
	},
	{
		"id": "potion_elixir",
		"category": "물약",
		"title": "황금 성배 엘릭서",
		"desc": "체력 ♥ +3 대량 회복 & 모든 액티브 스킬 즉시 충전!",
		"color": Color(1.0, 0.92, 0.4),
	},
]

# 현재 진행 방 번호 (1 ~ 5)
var current_room: int = 1
var total_kills: int = 0
var run_time_sec: float = 0.0
var is_run_active: bool = true

# 플레이어 누적 스탯 & 무기 인벤토리 (방 전환 시에도 유지)
var max_hp: int = 6
var current_hp: int = 6
var move_speed: float = 98.0

var owned_weapons: Array[String] = ["pistol"]
var current_weapon_id: String = "pistol"

var bonus_damage: int = 0
var bonus_multi_shot: int = 0
var fire_rate_mult: float = 1.0
var bullet_speed_mult: float = 1.0
var bullet_scale_mult: float = 1.0

var dash_cooldown: float = 0.82
var dash_duration: float = 0.22
var skill_cooldown_mult: float = 1.0

# 기존 스크립트 호환용 계산 프로퍼티 (현재 무기 + 장비 보너스 합산)
var bullet_damage: int:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return int(w["base_damage"]) + bonus_damage

var fire_cooldown: float:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return maxf(0.06, float(w["cooldown"]) * fire_rate_mult)

var bullet_speed: float:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return float(w["speed"]) * bullet_speed_mult

var bullet_scale: float:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return float(w["scale"]) * bullet_scale_mult

var multi_shot: int:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return mini(8, int(w["pellets"]) + bonus_multi_shot)

var weapon_spread_deg: float:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return float(w["spread_deg"])

var weapon_tint: Color:
	get:
		var w: Dictionary = WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])
		return w["tint"] as Color

# 획득한 아이템 기록
var acquired_upgrades: Array[String] = []
var _is_changing_scene: bool = false

func _process(delta: float) -> void:
	if is_run_active and not get_tree().paused:
		run_time_sec += delta

## 새 게임(런) 시작 시 모든 스탯과 인벤토리를 초기화합니다.
func reset_run() -> void:
	current_room = 1
	total_kills = 0
	run_time_sec = 0.0
	is_run_active = true
	_is_changing_scene = false
	
	max_hp = 6
	current_hp = 6
	move_speed = 98.0
	
	owned_weapons = ["pistol"]
	current_weapon_id = "pistol"
	bonus_damage = 0
	bonus_multi_shot = 0
	fire_rate_mult = 1.0
	bullet_speed_mult = 1.0
	bullet_scale_mult = 1.0
	dash_cooldown = 0.82
	dash_duration = 0.22
	skill_cooldown_mult = 1.0
	
	acquired_upgrades.clear()
	stats_changed.emit()
	hp_changed.emit(current_hp, max_hp)
	weapon_changed.emit(get_current_weapon_info())

func get_room_title(room_idx: int = -1) -> String:
	var idx: int = room_idx if room_idx > 0 else current_room
	if idx >= 1 and idx <= ROOM_TITLES.size():
		return ROOM_TITLES[idx - 1]
	return "던전 구역"

func get_current_weapon_info() -> Dictionary:
	return WEAPON_DB.get(current_weapon_id, WEAPON_DB["pistol"])

func get_current_weapon_name() -> String:
	var w: Dictionary = get_current_weapon_info()
	return String(w.get("name", "러스트 사이드암"))

## [Q] 키로 보유한 다음 무기로 교체합니다.
func cycle_weapon() -> Dictionary:
	if owned_weapons.size() <= 1:
		return get_current_weapon_info()
	var idx: int = owned_weapons.find(current_weapon_id)
	var next_idx: int = (idx + 1) % owned_weapons.size()
	current_weapon_id = owned_weapons[next_idx]
	var info: Dictionary = get_current_weapon_info()
	weapon_changed.emit(info)
	stats_changed.emit()
	return info

func heal_player(amount: int) -> void:
	if amount <= 0:
		return
	current_hp = clampi(current_hp + amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	stats_changed.emit()

func damage_player(amount: int) -> bool:
	if amount <= 0 or current_hp <= 0:
		return false
	current_hp = clampi(current_hp - amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		is_run_active = false
	return current_hp <= 0

## 보급 상자 개봉 시 무작위 아이템(무기, 장비, 회복물약)을 뽑아 즉시 적용하고 결과를 반환합니다.
func roll_and_apply_chest_loot() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for item: Dictionary in LOOT_POOL:
		# 체력이 가득 차 있을 때는 단순 물약 대신 무기/장비 비중을 높임
		if item["category"] == "물약" and current_hp >= max_hp and randf() < 0.65:
			continue
		candidates.append(item)
	
	# 만약 체력이 절반 이하라면 물약 등장 확률 가중치 추가
	if current_hp <= max_hp / 2:
		for item: Dictionary in LOOT_POOL:
			if item["category"] == "물약":
				candidates.append(item)
	
	if candidates.is_empty():
		candidates = LOOT_POOL.duplicate()
	
	candidates.shuffle()
	var chosen: Dictionary = candidates[0].duplicate()
	
	var id_str: String = String(chosen["id"])
	match id_str:
		"weapon_shotgun", "weapon_smg", "weapon_revolver", "weapon_plasma":
			var wid: String = String(chosen["weapon_id"])
			if not owned_weapons.has(wid):
				owned_weapons.append(wid)
				current_weapon_id = wid
				acquired_upgrades.append(String(chosen["title"]))
			else:
				# 이미 보유한 무기가 나오면 무기 화력 개조(+1 공격력 & 연사력 상승)!
				current_weapon_id = wid
				bonus_damage += 1
				fire_rate_mult = maxf(0.45, fire_rate_mult * 0.90)
				chosen["title"] = "%s [강화 +1]" % chosen["title"]
				chosen["desc"] = "이미 보유한 총기 개조! 공격력 +1 & 연사력 +10% 상승"
				acquired_upgrades.append(String(chosen["title"]))
			weapon_changed.emit(get_current_weapon_info())
		"equip_armor":
			max_hp += 1
			current_hp = mini(max_hp, current_hp + 2)
			acquired_upgrades.append("납탄 방탄복")
		"equip_boots":
			move_speed = minf(185.0, move_speed * 1.18)
			dash_cooldown = maxf(0.32, dash_cooldown * 0.80)
			acquired_upgrades.append("신속의 박차")
		"equip_powder":
			bonus_damage += 1
			bullet_scale_mult = minf(1.8, bullet_scale_mult * 1.12)
			acquired_upgrades.append("대구경 화약통")
		"equip_splitter":
			bonus_multi_shot = mini(4, bonus_multi_shot + 1)
			acquired_upgrades.append("총열 분열기")
		"equip_crest":
			skill_cooldown_mult = maxf(0.4, skill_cooldown_mult * 0.75)
			fire_rate_mult = maxf(0.45, fire_rate_mult * 0.85)
			acquired_upgrades.append("총잡이의 인장")
		"potion_heal":
			current_hp = mini(max_hp, current_hp + 2)
			skills_reset_requested.emit()
		"potion_elixir":
			current_hp = mini(max_hp, current_hp + 3)
			skills_reset_requested.emit()
			acquired_upgrades.append("황금 엘릭서")
	
	hp_changed.emit(current_hp, max_hp)
	stats_changed.emit()
	return chosen

## 하위 호환용 메서드
func get_random_upgrades(count: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = LOOT_POOL.duplicate()
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

func apply_upgrade(_upgrade_id: String) -> void:
	roll_and_apply_chest_loot()

## 다음 방으로 전환합니다.
func go_to_next_room() -> void:
	if _is_changing_scene:
		return
	if current_room >= MAX_ROOMS:
		return
	
	_is_changing_scene = true
	current_room += 1
	var next_scene_path: String = ROOM_SCENES[current_room - 1]
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", next_scene_path)
	call_deferred("_reset_scene_lock")

## 처음 방(1번 방)부터 게임을 재시작합니다.
func restart_game() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true
	reset_run()
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", ROOM_SCENES[0])
	call_deferred("_reset_scene_lock")

func _reset_scene_lock() -> void:
	_is_changing_scene = false
