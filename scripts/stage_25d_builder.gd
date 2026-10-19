extends Node3D
## 눈이 편안한 저대비 다크 슬레이트 색감과 입체 중세 석조 건축 디테일(대형 암석 바닥, 카펫, 기단·기둥·머릿돌,
## 성문 아치, 입체 철창, 벽걸이 횃불 브래킷)로 구현한 리얼 2.5D 지하 던전 렌더러

const SCALE_3D: float = 1.0 / 16.0
const CAMERA_PITCH_DEG: float = -48.0

var _room_root: Node2D = null
var _camera_3d: Camera3D = null
var _entities_root: Node3D = null
var _avatar_map: Dictionary = {} # instance_id -> Dictionary (3D rig data)

# 전용 절차적 3D 던전 재질 캐시 (AtlasTexture의 3D 미지원으로 인한 전체 시트 반복 현상 원천 차단)
var _mat_floor_stone: StandardMaterial3D = null
var _mat_border_stone: StandardMaterial3D = null
var _mat_carpet: StandardMaterial3D = null
var _mat_wall_brick: StandardMaterial3D = null
var _mat_wall_cap: StandardMaterial3D = null
var _mat_pillar_stone: StandardMaterial3D = null
var _mat_iron_dark: StandardMaterial3D = null
var _mat_wood_crate: StandardMaterial3D = null
var _mat_barrel_red: StandardMaterial3D = null
var _mat_door_wood: StandardMaterial3D = null

func setup_from_room(room: Node2D) -> void:
	_room_root = room
	
	# 2D 캔버스 렌더링은 숨기고 물리 연산만 유지 (HUD는 CanvasLayer이므로 정상 표시됨)
	for child in _room_root.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
	
	_init_dungeon_materials()
	_build_environment_and_camera()
	_build_3d_dungeon_architecture()
	_build_3d_torches()
	
	_entities_root = Node3D.new()
	_entities_root.name = "Entities3D"
	add_child(_entities_root)
	
	_sync_all_entities(0.0)

func _process(delta: float) -> void:
	if _room_root == null or not is_instance_valid(_room_root):
		return
	
	for child in _room_root.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			(child as CanvasItem).visible = false
	
	_sync_all_entities(delta)
	_update_camera_3d(delta)

## 눈의 피로를 없애고 탄환/캐릭터 시인성을 극대화하는 저채도·저대비 다크 슬레이트 던전 텍스처 생성
func _init_dungeon_materials() -> void:
	# 1. 대형 지하 암석 바닥 텍스처 (64x64 심리스 석판, 밝기 편차를 5% 이내로 억제해 격자 눈부심 제거)
	var floor_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	floor_img.fill(Color(0.115, 0.132, 0.175)) # 기본 다크 슬레이트 스톤
	
	# 큼직하고 차분한 불규칙 암석 블록과 얕은 줄눈(Mortar) 그리기
	var mortar_col := Color(0.082, 0.095, 0.128)
	var highlight_col := Color(0.135, 0.155, 0.202)
	var shade_col := Color(0.102, 0.118, 0.158)
	
	# 수평 줄눈 (y = 0, 16, 32, 48)
	for y_line in [0, 16, 32, 48]:
		for x in range(64):
			floor_img.set_pixel(x, y_line, mortar_col)
			floor_img.set_pixel(x, (y_line + 1) % 64, highlight_col)
	
	# 수직 줄눈 (단마다 엇갈리게 배치하여 자연스러운 대형 석판 구성)
	var v_splits := [
		[0, 16, [0, 22, 44]],
		[16, 32, [10, 32, 54]],
		[32, 48, [4, 28, 48]],
		[48, 64, [16, 38, 58]],
	]
	for row_info in v_splits:
		var y0: int = row_info[0]
		var y1: int = row_info[1]
		var xs: Array = row_info[2]
		for x_split: int in xs:
			for y in range(y0, y1):
				floor_img.set_pixel(x_split % 64, y, mortar_col)
				floor_img.set_pixel((x_split + 1) % 64, y, highlight_col)
	
	# 석판 내부에 아주 은은한 질감 변화만 부여 (눈이 편안하도록 미세 톤 차이만 사용)
	for y in range(64):
		for x in range(64):
			var h: int = (x * 37 + y * 73 + (x / 8) * 19) % 29
			if h == 0:
				floor_img.set_pixel(x, y, shade_col)
			elif h == 1 and (y % 16 > 2):
				floor_img.set_pixel(x, y, highlight_col)
	
	var floor_tex := ImageTexture.create_from_image(floor_img)
	_mat_floor_stone = StandardMaterial3D.new()
	_mat_floor_stone.albedo_texture = floor_tex
	_mat_floor_stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_floor_stone.uv1_scale = Vector3(7.0, 4.5, 1.0) # 방 전체에 큼직한 석판으로 타일링
	_mat_floor_stone.roughness = 0.95
	
	# 2. 가장자리 석조 연석(Border Walkway) 재질
	_mat_border_stone = StandardMaterial3D.new()
	_mat_border_stone.albedo_texture = floor_tex
	_mat_border_stone.albedo_color = Color(0.82, 0.85, 0.92)
	_mat_border_stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_border_stone.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_mat_border_stone.roughness = 0.92
	
	# 3. 중앙 던전 러너 카펫 재질 (고풍스러운 다크 크림슨 & 뮤트 골드 테두리)
	var carpet_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var room_num: int = int(_room_root.get("room_number")) if _room_root != null else 1
	var carpet_base := Color(0.24, 0.10, 0.13) if room_num == 5 else Color(0.19, 0.11, 0.16)
	var carpet_inner := Color(0.28, 0.12, 0.15) if room_num == 5 else Color(0.22, 0.13, 0.19)
	var carpet_gold := Color(0.46, 0.36, 0.20)
	carpet_img.fill(carpet_base)
	for y in range(32):
		for x in range(32):
			if x == 1 or x == 30 or y == 1 or y == 30:
				carpet_img.set_pixel(x, y, carpet_gold)
			elif x > 3 and x < 28 and y > 3 and y < 28:
				if (x + y) % 4 == 0:
					carpet_img.set_pixel(x, y, carpet_inner)
	var carpet_tex := ImageTexture.create_from_image(carpet_img)
	_mat_carpet = StandardMaterial3D.new()
	_mat_carpet.albedo_texture = carpet_tex
	_mat_carpet.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_carpet.roughness = 0.98
	
	# 4. 외벽 중세 석조 벽돌 텍스처 (32x32)
	var wall_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	wall_img.fill(Color(0.18, 0.21, 0.28))
	var w_mortar := Color(0.10, 0.12, 0.16)
	var w_top := Color(0.23, 0.27, 0.35)
	for row in [0, 8, 16, 24]:
		for x in range(32):
			wall_img.set_pixel(x, row, w_mortar)
			wall_img.set_pixel(x, (row + 1) % 32, w_top)
		var offset: int = 0 if (row / 8) % 2 == 0 else 8
		for col in [offset, offset + 16]:
			for y in range(row, row + 8):
				wall_img.set_pixel(col % 32, y, w_mortar)
				wall_img.set_pixel((col + 1) % 32, y, w_top)
	var wall_tex := ImageTexture.create_from_image(wall_img)
	_mat_wall_brick = StandardMaterial3D.new()
	_mat_wall_brick.albedo_texture = wall_tex
	_mat_wall_brick.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_wall_brick.roughness = 0.9
	
	# 5. 성벽 상단 어두운 덮개(Cornice) 및 기단(Plinth) 재질
	_mat_wall_cap = StandardMaterial3D.new()
	_mat_wall_cap.albedo_color = Color(0.09, 0.11, 0.15)
	_mat_wall_cap.roughness = 0.95
	
	# 6. 내부 입체 석조 기둥 재질
	_mat_pillar_stone = StandardMaterial3D.new()
	_mat_pillar_stone.albedo_texture = wall_tex
	_mat_pillar_stone.albedo_color = Color(0.88, 0.92, 1.0)
	_mat_pillar_stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_pillar_stone.roughness = 0.88
	
	# 7. 어두운 주철(Wrought Iron) 재질 (철창, 횃불 브래킷, 화로 받침대)
	_mat_iron_dark = StandardMaterial3D.new()
	_mat_iron_dark.albedo_color = Color(0.14, 0.16, 0.20)
	_mat_iron_dark.metallic = 0.45
	_mat_iron_dark.roughness = 0.65
	
	# 8. 파괴 가능한 나무 상자 & 폭발 화약통 전용 텍스처
	var crate_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	crate_img.fill(Color(0.42, 0.28, 0.16))
	for i in range(16):
		for b in [0, 1, 14, 15]:
			crate_img.set_pixel(i, b, Color(0.28, 0.18, 0.10))
			crate_img.set_pixel(b, i, Color(0.28, 0.18, 0.10))
		crate_img.set_pixel(i, i, Color(0.35, 0.23, 0.13))
	_mat_wood_crate = StandardMaterial3D.new()
	_mat_wood_crate.albedo_texture = ImageTexture.create_from_image(crate_img)
	_mat_wood_crate.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_wood_crate.roughness = 0.9
	
	var barrel_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	barrel_img.fill(Color(0.58, 0.18, 0.16))
	for y in [3, 4, 11, 12]:
		for x in range(16):
			barrel_img.set_pixel(x, y, Color(0.22, 0.24, 0.28))
	_mat_barrel_red = StandardMaterial3D.new()
	_mat_barrel_red.albedo_texture = ImageTexture.create_from_image(barrel_img)
	_mat_barrel_red.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_barrel_red.roughness = 0.75
	
	# 9. 철제 징이 박힌 참나무 던전 문짝 재질
	var door_img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	door_img.fill(Color(0.32, 0.20, 0.12))
	for y in range(24):
		for x in [0, 5, 10, 15]:
			door_img.set_pixel(x, y, Color(0.20, 0.12, 0.07))
	for y in [4, 19]:
		for x in range(16):
			door_img.set_pixel(x, y, Color(0.18, 0.20, 0.25))
	_mat_door_wood = StandardMaterial3D.new()
	_mat_door_wood.albedo_texture = ImageTexture.create_from_image(door_img)
	_mat_door_wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat_door_wood.roughness = 0.85

func _build_environment_and_camera() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.70)
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 눈부심 방지를 위해 글로우(Bloom)를 은은하게 억제
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_bloom = 0.04
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	# 부드러운 입체 그림자를 드리우는 디렉셔널 라이트
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-55.0, -22.0, 0.0)
	dir_light.light_color = Color(0.92, 0.90, 0.88)
	dir_light.light_energy = 0.68
	dir_light.shadow_enabled = true
	dir_light.shadow_opacity = 0.55
	dir_light.directional_shadow_max_distance = 90.0
	add_child(dir_light)
	
	# 2.5D 쿼터뷰/탑다운 원근 카메라
	_camera_3d = Camera3D.new()
	_camera_3d.current = true
	_camera_3d.fov = 38.0
	_camera_3d.rotation_degrees = Vector3(CAMERA_PITCH_DEG, 0.0, 0.0)
	_camera_3d.position = Vector3(15.0, 12.5, 24.0)
	add_child(_camera_3d)

func _build_3d_dungeon_architecture() -> void:
	var map_root := Node3D.new()
	map_root.name = "DungeonGeometry3D"
	add_child(map_root)
	
	# 1. 성채 바깥의 깊은 심연 배경 평면 (화면 가장자리 잘림 방지를 위해 넉넉한 크기로 생성)
	var abyss_mesh := PlaneMesh.new()
	abyss_mesh.size = Vector2(200.0, 200.0)
	var abyss_inst := MeshInstance3D.new()
	abyss_inst.mesh = abyss_mesh
	var abyss_mat := StandardMaterial3D.new()
	abyss_mat.albedo_color = Color(0.035, 0.04, 0.06)
	abyss_mat.roughness = 1.0
	abyss_inst.material_override = abyss_mat
	abyss_inst.position = Vector3(15.0, -0.08, 10.0)
	map_root.add_child(abyss_inst)
	
	# 2. 눈이 편안한 일체형 대형 암석 바닥 (600개의 쪼개진 타일 대신 심리스 석조 바닥 사용)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(28.4, 18.4)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = _mat_floor_stone
	floor_inst.position = Vector3(15.0, 0.0, 10.0)
	map_root.add_child(floor_inst)
	
	# 3. 방 테두리를 따라 이어지는 석조 보도 연석 (Dungeon Perimeter Curb)
	_spawn_floor_trim_box(map_root, Vector3(15.0, 0.015, 1.5), Vector3(28.0, 0.03, 1.0))  # 북쪽 연석
	_spawn_floor_trim_box(map_root, Vector3(15.0, 0.015, 18.5), Vector3(28.0, 0.03, 1.0)) # 남쪽 연석
	_spawn_floor_trim_box(map_root, Vector3(1.5, 0.015, 10.0), Vector3(1.0, 0.03, 16.0))  # 서쪽 연석
	_spawn_floor_trim_box(map_root, Vector3(28.5, 0.015, 10.0), Vector3(1.0, 0.03, 16.0)) # 동쪽 연석
	
	# 4. 방 중앙을 가로지르는 고풍스러운 던전 러너 카펫 (시선 안정화 & 던전 분위기 연출)
	var room_num: int = int(_room_root.get("room_number")) if _room_root != null else 1
	var carpet_w: float = 6.5 if room_num == 5 else 3.6
	var carpet_mesh := PlaneMesh.new()
	carpet_mesh.size = Vector2(carpet_w, 14.5)
	var carpet_inst := MeshInstance3D.new()
	carpet_inst.mesh = carpet_mesh
	carpet_inst.material_override = _mat_carpet
	carpet_inst.position = Vector3(15.0, 0.008, 9.8)
	map_root.add_child(carpet_inst)
	
	# 바닥 철제 배수구 격자 디테일 (과하지 않게 4곳 배치)
	for grate_pos: Vector3 in [
		Vector3(8.5, 0.006, 6.5),
		Vector3(21.5, 0.006, 6.5),
		Vector3(8.5, 0.006, 13.5),
		Vector3(21.5, 0.006, 13.5),
	]:
		_spawn_floor_grate(map_root, grate_pos)
	
	# 5. WallLayer 타일 데이터를 읽어 3D 성벽·기둥·철창·화로 생성
	var wall_layer: TileMapLayer = _room_root.get_node_or_null("WallLayer") as TileMapLayer
	if wall_layer != null:
		for cell: Vector2i in wall_layer.get_used_cells():
			if room_num < 5 and cell.y == 0 and (cell.x == 14 or cell.x == 15):
				continue
			var ac: Vector2i = wall_layer.get_cell_atlas_coords(cell)
			if ac.x < 0:
				continue
			_spawn_3d_wall_cell(map_root, cell, ac)
	
	# 6. 북쪽 출입구 대형 석조 아치 성문 프레임 (마지막 방 제외)
	if room_num < 5:
		_build_north_gate_archway(map_root)

func _spawn_floor_trim_box(parent_3d: Node3D, pos: Vector3, sz: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _mat_border_stone
	mi.position = pos
	parent_3d.add_child(mi)

func _spawn_floor_grate(parent_3d: Node3D, pos: Vector3) -> void:
	var grate := BoxMesh.new()
	grate.size = Vector3(0.9, 0.012, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = grate
	mi.material_override = _mat_iron_dark
	mi.position = pos
	parent_3d.add_child(mi)

func _build_north_gate_archway(parent_3d: Node3D) -> void:
	# 성문 좌우 대형 설주 기둥(Jambs)과 상단 아치 인방보(Lintel)
	for side_x: float in [13.85, 16.15]:
		var jamb := BoxMesh.new()
		jamb.size = Vector3(0.45, 2.35, 1.25)
		var j_mi := MeshInstance3D.new()
		j_mi.mesh = jamb
		j_mi.material_override = _mat_pillar_stone
		j_mi.position = Vector3(side_x, 1.175, 0.55)
		parent_3d.add_child(j_mi)
	
	var lintel := BoxMesh.new()
	lintel.size = Vector3(2.9, 0.45, 1.32)
	var l_mi := MeshInstance3D.new()
	l_mi.mesh = lintel
	l_mi.material_override = _mat_wall_cap
	l_mi.position = Vector3(15.0, 2.25, 0.55)
	parent_3d.add_child(l_mi)

func _spawn_3d_wall_cell(parent_3d: Node3D, cell: Vector2i, ac: Vector2i) -> void:
	var pos_x: float = float(cell.x) + 0.5
	var pos_z: float = float(cell.y) + 0.5
	var is_outer_wall: bool = (cell.x == 0 or cell.x == 29 or cell.y == 0 or cell.y == 19)
	
	# 1. 성수 화로 (8, 2) 또는 불꽃 화로 (7, 2): 입체 주철 화로대 + 은은한 에메랄드/호박색 불꽃 코어
	if ac == Vector2i(8, 2) or ac == Vector2i(7, 2):
		var base_box := BoxMesh.new()
		base_box.size = Vector3(0.76, 0.55, 0.76)
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_box
		base_mi.material_override = _mat_iron_dark
		base_mi.position = Vector3(pos_x, 0.275, pos_z)
		parent_3d.add_child(base_mi)
		
		var is_emerald: bool = (ac == Vector2i(8, 2))
		var ember_col := Color(0.2, 0.92, 0.58) if is_emerald else Color(1.0, 0.58, 0.2)
		var ember_sphere := SphereMesh.new()
		ember_sphere.radius = 0.24
		ember_sphere.height = 0.36
		var ember_mi := MeshInstance3D.new()
		ember_mi.mesh = ember_sphere
		var ember_mat := StandardMaterial3D.new()
		ember_mat.albedo_color = ember_col
		ember_mat.emission_enabled = true
		ember_mat.emission = ember_col * 1.2
		ember_mi.material_override = ember_mat
		ember_mi.position = Vector3(pos_x, 0.62, pos_z)
		parent_3d.add_child(ember_mi)
		
		var glow := OmniLight3D.new()
		glow.light_color = ember_col
		glow.light_energy = 0.65
		glow.omni_range = 3.6
		glow.position = Vector3(pos_x, 0.9, pos_z)
		parent_3d.add_child(glow)
		return
	
	# 2. 던전 철창 (4,6 / 5,6 / 6,6) 및 석조 난간 (4,5 / 5,5): 실제 3D 입체 철창살 구조물
	if (ac.y == 6 and ac.x in [4, 5, 6]) or (ac.y == 5 and ac.x in [4, 5]):
		# 하단 석조 받침턱
		var curb := BoxMesh.new()
		curb.size = Vector3(1.0, 0.28, 0.32)
		var curb_mi := MeshInstance3D.new()
		curb_mi.mesh = curb
		curb_mi.material_override = _mat_pillar_stone
		curb_mi.position = Vector3(pos_x, 0.14, pos_z)
		parent_3d.add_child(curb_mi)
		
		# 상단 철제 가로대
		var rail := BoxMesh.new()
		rail.size = Vector3(1.0, 0.08, 0.14)
		var rail_mi := MeshInstance3D.new()
		rail_mi.mesh = rail
		rail_mi.material_override = _mat_iron_dark
		rail_mi.position = Vector3(pos_x, 1.05, pos_z)
		parent_3d.add_child(rail_mi)
		
		# 3개의 수직 주철 창살
		for bar_offset: float in [-0.32, 0.0, 0.32]:
			var bar := BoxMesh.new()
			bar.size = Vector3(0.08, 0.82, 0.08)
			var bar_mi := MeshInstance3D.new()
			bar_mi.mesh = bar
			bar_mi.material_override = _mat_iron_dark
			bar_mi.position = Vector3(pos_x + bar_offset, 0.65, pos_z)
			parent_3d.add_child(bar_mi)
		return
	
	# 3. 방 내부의 모든 벽/기둥 타일은 진짜 던전 같은 3단 입체 석조 기둥(기단 + 기둥 몸통 + 상단 머릿돌)으로 건축!
	if not is_outer_wall:
		# (1) 하단 넓은 석조 기단 (Pedestal Base)
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(0.96, 0.28, 0.96)
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_mesh
		base_mi.material_override = _mat_wall_cap
		base_mi.position = Vector3(pos_x, 0.14, pos_z)
		parent_3d.add_child(base_mi)
		
		# (2) 중간 석조 기둥 몸통 (Column Shaft)
		var shaft_h: float = 1.35
		var shaft_mesh := BoxMesh.new()
		shaft_mesh.size = Vector3(0.78, shaft_h, 0.78)
		var shaft_mi := MeshInstance3D.new()
		shaft_mi.mesh = shaft_mesh
		shaft_mi.material_override = _mat_pillar_stone
		shaft_mi.position = Vector3(pos_x, 0.28 + shaft_h * 0.5, pos_z)
		parent_3d.add_child(shaft_mi)
		
		# (3) 상단 머릿돌 (Capital Top)
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(0.94, 0.20, 0.94)
		var cap_mi := MeshInstance3D.new()
		cap_mi.mesh = cap_mesh
		cap_mi.material_override = _mat_wall_cap
		cap_mi.position = Vector3(pos_x, 0.28 + shaft_h + 0.10, pos_z)
		parent_3d.add_child(cap_mi)
		return
	
	# 4. 방 외곽을 둘러싼 중세 지하 성벽 (Outer Dungeon Wall)
	# 남쪽 외벽(cell.y >= 19)은 카메라 시야 확보를 위해 깔끔한 단면 컷어웨이 성벽(0.42m)으로 마감
	var wall_h: float = 0.42 if cell.y >= 19 else 1.85
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(1.0, wall_h, 1.0)
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall_box
	wall_mi.material_override = _mat_wall_brick
	wall_mi.position = Vector3(pos_x, wall_h * 0.5, pos_z)
	parent_3d.add_child(wall_mi)
	
	# 성벽 상단 어두운 석조 덮개(Cornice)
	var top_cap := BoxMesh.new()
	top_cap.size = Vector3(1.04, 0.14, 1.04)
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = top_cap
	top_mi.material_override = _mat_wall_cap
	top_mi.position = Vector3(pos_x, wall_h + 0.07, pos_z)
	parent_3d.add_child(top_mi)
	
	# 성벽 하단 걸레받이 기단(Plinth)
	if wall_h > 1.0:
		var plinth := BoxMesh.new()
		plinth.size = Vector3(1.06, 0.22, 1.06)
		var plinth_mi := MeshInstance3D.new()
		plinth_mi.mesh = plinth
		plinth_mi.material_override = _mat_wall_cap
		plinth_mi.position = Vector3(pos_x, 0.11, pos_z)
		parent_3d.add_child(plinth_mi)

## 벽걸이 철제 횃불 브래킷과 은은하고 따뜻한 난로빛 3D 광원 생성
func _build_3d_torches() -> void:
	for child in _room_root.get_children():
		if child.name.begins_with("Torch") and child is Node2D:
			var p2: Vector2 = (child as Node2D).position
			var tx: float = p2.x * SCALE_3D
			var tz: float = p2.y * SCALE_3D
			
			var sconce_root := Node3D.new()
			sconce_root.position = Vector3(tx, 1.15, tz)
			add_child(sconce_root)
			
			# 철제 브래킷 막대
			var bracket := BoxMesh.new()
			bracket.size = Vector3(0.10, 0.36, 0.10)
			var b_mi := MeshInstance3D.new()
			b_mi.mesh = bracket
			b_mi.material_override = _mat_iron_dark
			b_mi.rotation_degrees.x = 20.0
			sconce_root.add_child(b_mi)
			
			# 불꽃 엠버 구체
			var flame := SphereMesh.new()
			flame.radius = 0.11
			flame.height = 0.20
			var f_mi := MeshInstance3D.new()
			f_mi.mesh = flame
			var f_mat := StandardMaterial3D.new()
			f_mat.albedo_color = Color(1.0, 0.72, 0.32)
			f_mat.emission_enabled = true
			f_mat.emission = Color(1.0, 0.62, 0.22) * 1.4
			f_mi.material_override = f_mat
			f_mi.position = Vector3(0.0, 0.22, 0.05)
			sconce_root.add_child(f_mi)
			
			# 눈이 피로하지 않은 부드러운 호박색 던전 조명
			var torch_3d := OmniLight3D.new()
			torch_3d.light_color = Color(1.0, 0.74, 0.42)
			torch_3d.light_energy = 0.92
			torch_3d.omni_range = 6.2
			torch_3d.shadow_enabled = false
			torch_3d.position = Vector3(0.0, 0.28, 0.15)
			sconce_root.add_child(torch_3d)

func _sync_all_entities(_delta: float) -> void:
	var active_ids: Dictionary = {}
	
	for child in _room_root.get_children():
		if not (child is Node2D or child is ColorRect):
			continue
		if child is TileMapLayer or child.name.begins_with("Torch"):
			continue
		
		var id: int = child.get_instance_id()
		active_ids[id] = true
		
		if not _avatar_map.has(id):
			_create_3d_avatar_for(child as CanvasItem)
		
		if _avatar_map.has(id):
			_update_3d_avatar(child as CanvasItem, _avatar_map[id])
	
	var to_remove: Array[int] = []
	for id: int in _avatar_map.keys():
		if not active_ids.has(id):
			var rig: Dictionary = _avatar_map[id]
			var root_3d: Node3D = rig.get("root") as Node3D
			if root_3d != null and is_instance_valid(root_3d):
				root_3d.queue_free()
			to_remove.append(id)
	for id: int in to_remove:
		_avatar_map.erase(id)

func _create_3d_avatar_for(node: CanvasItem) -> void:
	var id: int = node.get_instance_id()
	var root_3d := Node3D.new()
	_entities_root.add_child(root_3d)
	
	# 1. 북쪽 출입문 (Door) -> 3D 입체 참나무/철제 양문형 성문
	if node.is_in_group("doors"):
		var door_box := BoxMesh.new()
		door_box.size = Vector3(0.95, 1.65, 0.18)
		
		var left_pivot := Node3D.new()
		left_pivot.position = Vector3(-0.95, 0.0, 0.0)
		root_3d.add_child(left_pivot)
		var left_wing := MeshInstance3D.new()
		left_wing.mesh = door_box
		left_wing.material_override = _mat_door_wood
		left_wing.position = Vector3(0.475, 0.825, 0.0)
		left_pivot.add_child(left_wing)
		
		var right_pivot := Node3D.new()
		right_pivot.position = Vector3(0.95, 0.0, 0.0)
		root_3d.add_child(right_pivot)
		var right_wing := MeshInstance3D.new()
		right_wing.mesh = door_box
		right_wing.material_override = _mat_door_wood
		right_wing.position = Vector3(-0.475, 0.825, 0.0)
		right_pivot.add_child(right_wing)
		
		var door_light := OmniLight3D.new()
		door_light.light_color = Color(1.0, 0.38, 0.35)
		door_light.light_energy = 0.85
		door_light.omni_range = 3.2
		door_light.position = Vector3(0.0, 1.2, 0.65)
		root_3d.add_child(door_light)
		
		_avatar_map[id] = {
			"type": "door",
			"root": root_3d,
			"left": left_pivot,
			"right": right_pivot,
			"light": door_light,
		}
		return
	
	# 2. 파괴 가능한 나무 상자 / 화약통 (DestructibleProp) -> 전용 3D 메시 & 텍스처
	if node.is_in_group("destructibles"):
		var is_crate: bool = bool(node.get("is_crate"))
		var mi := MeshInstance3D.new()
		if is_crate:
			var box := BoxMesh.new()
			box.size = Vector3(0.76, 0.76, 0.76)
			mi.mesh = box
			mi.position = Vector3(0.0, 0.38, 0.0)
		else:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.36
			cyl.bottom_radius = 0.36
			cyl.height = 0.82
			cyl.radial_segments = 12
			mi.mesh = cyl
			mi.position = Vector3(0.0, 0.41, 0.0)
		
		var base_mat: StandardMaterial3D = _mat_wood_crate if is_crate else _mat_barrel_red
		var mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
		mi.material_override = mat
		root_3d.add_child(mi)
		_avatar_map[id] = {
			"type": "prop",
			"root": root_3d,
			"mesh": mi,
			"mat": mat,
		}
		return
	
	# 2.5. 랜덤 보급 상자 (TreasureChest) -> 뚜껑이 회전하며 열리고 보석 오브가 떠오르는 3D 입체 보물상자!
	if node.is_in_group("chests"):
		var base_box := BoxMesh.new()
		base_box.size = Vector3(0.92, 0.44, 0.66)
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_box
		base_mi.material_override = _mat_door_wood
		base_mi.position = Vector3(0.0, 0.22, 0.0)
		root_3d.add_child(base_mi)
		
		# 상자 전면 황금 자물쇠 장식
		var lock_box := BoxMesh.new()
		lock_box.size = Vector3(0.18, 0.22, 0.08)
		var lock_mi := MeshInstance3D.new()
		lock_mi.mesh = lock_box
		var gold_mat := StandardMaterial3D.new()
		gold_mat.albedo_color = Color(0.95, 0.78, 0.25)
		gold_mat.metallic = 0.6
		gold_mat.roughness = 0.35
		gold_mat.emission_enabled = true
		gold_mat.emission = Color(0.95, 0.75, 0.2) * 0.35
		lock_mi.material_override = gold_mat
		lock_mi.position = Vector3(0.0, 0.36, 0.34)
		root_3d.add_child(lock_mi)
		
		# 경첩 기준으로 회전하며 열리는 상자 뚜껑 (Lid Pivot)
		var lid_pivot := Node3D.new()
		lid_pivot.position = Vector3(0.0, 0.44, -0.33)
		root_3d.add_child(lid_pivot)
		
		var lid_box := BoxMesh.new()
		lid_box.size = Vector3(0.94, 0.22, 0.68)
		var lid_mi := MeshInstance3D.new()
		lid_mi.mesh = lid_box
		lid_mi.material_override = _mat_door_wood
		lid_mi.position = Vector3(0.0, 0.11, 0.33)
		lid_pivot.add_child(lid_mi)
		
		# 상자 개봉 시 떠오르는 3D 아이템 코어 오브
		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = 0.18
		orb_mesh.height = 0.36
		var orb_mi := MeshInstance3D.new()
		orb_mi.mesh = orb_mesh
		var orb_mat := StandardMaterial3D.new()
		orb_mat.albedo_color = Color(1.0, 0.88, 0.35)
		orb_mat.emission_enabled = true
		orb_mat.emission = Color(1.0, 0.85, 0.3) * 1.4
		orb_mi.material_override = orb_mat
		orb_mi.position = Vector3(0.0, 0.35, 0.0)
		orb_mi.visible = false
		root_3d.add_child(orb_mi)
		
		var chest_light := OmniLight3D.new()
		chest_light.light_color = Color(1.0, 0.82, 0.35)
		chest_light.light_energy = 0.75
		chest_light.omni_range = 3.2
		chest_light.position = Vector3(0.0, 0.75, 0.2)
		root_3d.add_child(chest_light)
		
		_avatar_map[id] = {
			"type": "chest",
			"root": root_3d,
			"lid": lid_pivot,
			"orb": orb_mi,
			"orb_mat": orb_mat,
			"light": chest_light,
		}
		return
	
	# 2.8. [R] 스킬 전자동 기계 포탑 (Auto-Turret) -> 360도 회전 헤드 + 쌍열 기관총신 + 시안 타겟팅 코어!
	if node.is_in_group("turrets"):
		var shadow := _make_ground_shadow(0.48)
		root_3d.add_child(shadow)
		
		# 하단 삼각대 철제 베이스
		var base_cyl := CylinderMesh.new()
		base_cyl.top_radius = 0.34
		base_cyl.bottom_radius = 0.44
		base_cyl.height = 0.22
		base_cyl.radial_segments = 8
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_cyl
		base_mi.material_override = _mat_iron_dark
		base_mi.position = Vector3(0.0, 0.11, 0.0)
		root_3d.add_child(base_mi)
		
		# 360도 회전하는 포탑 헤드 피벗
		var head_pivot := Node3D.new()
		head_pivot.position = Vector3(0.0, 0.42, 0.0)
		root_3d.add_child(head_pivot)
		
		# 황동/강철 장갑 포탑 몸통
		var head_box := BoxMesh.new()
		head_box.size = Vector3(0.50, 0.32, 0.42)
		var head_mi := MeshInstance3D.new()
		head_mi.mesh = head_box
		var brass_mat := StandardMaterial3D.new()
		brass_mat.albedo_color = Color(0.78, 0.62, 0.28)
		brass_mat.metallic = 0.55
		brass_mat.roughness = 0.4
		head_mi.material_override = brass_mat
		head_pivot.add_child(head_mi)
		
		# 상단 시안 타겟팅 센서 코어
		var core_sphere := SphereMesh.new()
		core_sphere.radius = 0.13
		core_sphere.height = 0.22
		var core_mi := MeshInstance3D.new()
		core_mi.mesh = core_sphere
		var core_mat := StandardMaterial3D.new()
		core_mat.albedo_color = Color(0.35, 0.95, 1.0)
		core_mat.emission_enabled = true
		core_mat.emission = Color(0.3, 0.9, 1.0) * 1.5
		core_mi.material_override = core_mat
		core_mi.position = Vector3(-0.04, 0.20, 0.0)
		head_pivot.add_child(core_mi)
		
		# 반동에 따라 앞뒤로 움직이는 쌍열 기관총신 어셈블리
		var barrel_pivot := Node3D.new()
		head_pivot.add_child(barrel_pivot)
		
		for z_off: float in [-0.11, 0.11]:
			var b_box := BoxMesh.new()
			b_box.size = Vector3(0.52, 0.09, 0.09)
			var b_mi := MeshInstance3D.new()
			b_mi.mesh = b_box
			b_mi.material_override = _mat_iron_dark
			b_mi.position = Vector3(0.38, 0.02, z_off)
			barrel_pivot.add_child(b_mi)
		
		var turret_light := OmniLight3D.new()
		turret_light.light_color = Color(0.35, 0.92, 1.0)
		turret_light.light_energy = 0.75
		turret_light.omni_range = 3.0
		turret_light.position = Vector3(0.0, 0.75, 0.0)
		root_3d.add_child(turret_light)
		
		_avatar_map[id] = {
			"type": "turret",
			"root": root_3d,
			"head": head_pivot,
			"barrel": barrel_pivot,
		}
		return
	
	# 3. 플레이어 / 몬스터 / 보스 / 탄환 (Sprite2D 기반)
	var spr2d: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
	if spr2d != null and spr2d.texture != null:
		var is_bullet: bool = node is Area2D and not node.is_in_group("chests")
		var spr3d := _make_sprite3d(spr2d.texture, 0.0625, is_bullet)
		spr3d.rotation_degrees.x = CAMERA_PITCH_DEG if not is_bullet else -62.0
		root_3d.add_child(spr3d)
		
		var rig: Dictionary = {
			"type": "sprite",
			"root": root_3d,
			"spr3d": spr3d,
			"is_bullet": is_bullet,
		}
		
		if not is_bullet:
			var shadow := _make_ground_shadow(0.42 if not node.is_in_group("boss") else 0.78)
			root_3d.add_child(shadow)
			rig["shadow"] = shadow
		
		var wp2d: Node2D = node.get_node_or_null("WeaponPivot") as Node2D
		if wp2d != null:
			var gun2d: Sprite2D = wp2d.get_node_or_null("GunSprite") as Sprite2D
			if gun2d != null and gun2d.texture != null:
				var gun_pivot_3d := Node3D.new()
				gun_pivot_3d.position = Vector3(0.0, 0.38, 0.08)
				root_3d.add_child(gun_pivot_3d)
				
				var gun3d := _make_sprite3d(gun2d.texture, 0.0625, false)
				gun3d.rotation_degrees.x = CAMERA_PITCH_DEG
				gun_pivot_3d.add_child(gun3d)
				rig["gun_pivot_3d"] = gun_pivot_3d
				rig["gun3d"] = gun3d
		
		_avatar_map[id] = rig
		return
	
	# 4. 탄피 / 먼지 / 파편 / 충격파 (ColorRect 이펙트)
	if node is ColorRect:
		var cr: ColorRect = node as ColorRect
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = Vector3(cr.size.x * SCALE_3D, 0.06, cr.size.y * SCALE_3D)
		var mi := MeshInstance3D.new()
		mi.mesh = shard_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cr.color
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.04, 0.0)
		root_3d.add_child(mi)
		_avatar_map[id] = {
			"type": "debris",
			"root": root_3d,
			"mat": mat,
		}

func _make_sprite3d(tex: Texture2D, px_size: float, unshaded_glow: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px_size
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = not unshaded_glow
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unshaded_glow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return s

func _make_ground_shadow(radius: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.01
	cyl.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.position = Vector3(0.0, 0.012, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _update_3d_avatar(node: CanvasItem, rig: Dictionary) -> void:
	var root_3d: Node3D = rig["root"]
	var p2: Vector2 = (node as Node2D).global_position if node is Node2D else (node as Control).global_position
	root_3d.position = Vector3(p2.x * SCALE_3D, 0.0, p2.y * SCALE_3D)
	
	var rtype: String = rig["type"]
	if rtype == "door":
		var is_open: bool = bool(node.get("is_open"))
		var left_w: Node3D = rig["left"]
		var right_w: Node3D = rig["right"]
		var light_w: OmniLight3D = rig["light"]
		left_w.rotation_degrees.y = lerpf(left_w.rotation_degrees.y, -82.0 if is_open else 0.0, 0.14)
		right_w.rotation_degrees.y = lerpf(right_w.rotation_degrees.y, 82.0 if is_open else 0.0, 0.14)
		light_w.light_color = Color(0.35, 0.95, 0.55) if is_open else Color(1.0, 0.35, 0.35)
		return
	
	if rtype == "chest":
		var opened: bool = bool(node.get("is_opened"))
		var lid_w: Node3D = rig["lid"]
		var orb_w: MeshInstance3D = rig["orb"]
		var orb_mat: StandardMaterial3D = rig["orb_mat"]
		var light_w: OmniLight3D = rig["light"]
		lid_w.rotation_degrees.x = lerpf(lid_w.rotation_degrees.x, -105.0 if opened else 0.0, 0.16)
		if opened:
			orb_w.visible = true
			orb_w.position.y = lerpf(orb_w.position.y, 0.85, 0.12)
			var loot_info: Variant = node.get("last_loot_info")
			if loot_info is Dictionary:
				var c: Color = (loot_info as Dictionary).get("color", Color(1.0, 0.88, 0.35))
				orb_mat.albedo_color = c
				orb_mat.emission = c * 1.4
				light_w.light_color = c
		return
	
	if rtype == "turret":
		var head_w: Node3D = rig["head"]
		var barrel_w: Node3D = rig["barrel"]
		var ang: float = float(node.get("turret_angle"))
		var rec: float = float(node.get("barrel_recoil"))
		head_w.rotation.y = -ang
		barrel_w.position.x = -rec * SCALE_3D
		return
	
	if rtype == "prop":
		var spr2d: Sprite2D = node.get_node_or_null("Sprite2D") as Sprite2D
		var mat: StandardMaterial3D = rig["mat"]
		if spr2d != null and mat != null:
			mat.albedo_color = spr2d.self_modulate
		return
	
	if rtype == "debris":
		var rot2d: float = (node as Node2D).rotation if node is Node2D else (node as Control).rotation
		root_3d.rotation.y = -rot2d
		return
	
	if rtype == "sprite" and node is Node2D:
		var n2d: Node2D = node as Node2D
		var spr2d: Sprite2D = n2d.get_node_or_null("Sprite2D") as Sprite2D
		var spr3d: Sprite3D = rig["spr3d"]
		var is_bullet: bool = rig["is_bullet"]
		if spr2d == null or spr3d == null:
			return
		
		spr3d.texture = spr2d.texture
		spr3d.flip_h = spr2d.flip_h
		spr3d.modulate = n2d.modulate * spr2d.modulate * spr2d.self_modulate
		spr3d.scale = Vector3(spr2d.scale.x, spr2d.scale.y, 1.0) * Vector3(n2d.scale.x, n2d.scale.y, 1.0)
		
		if is_bullet:
			spr3d.position = Vector3(0.0, 0.42, 0.0)
			spr3d.rotation.z = -n2d.global_rotation
		else:
			var jump_height: float = maxf(0.0, -spr2d.position.y) * SCALE_3D * 1.4
			var base_h: float = 0.48 * spr2d.scale.y
			spr3d.position = Vector3(0.0, base_h + jump_height, 0.0)
			spr3d.rotation.z = -spr2d.rotation
		
		if rig.has("gun_pivot_3d") and rig.has("gun3d"):
			var wp2d: Node2D = n2d.get_node_or_null("WeaponPivot") as Node2D
			var gun2d: Sprite2D = wp2d.get_node_or_null("GunSprite") as Sprite2D if wp2d != null else null
			var gun_pivot_3d: Node3D = rig["gun_pivot_3d"]
			var gun3d: Sprite3D = rig["gun3d"]
			if wp2d != null and gun2d != null:
				gun_pivot_3d.visible = wp2d.visible
				var ang: float = wp2d.rotation
				var dist_3d: float = gun2d.position.x * SCALE_3D
				gun3d.position = Vector3(cos(ang) * dist_3d, 0.0, sin(ang) * dist_3d)
				gun3d.flip_v = gun2d.flip_v
				gun3d.rotation.z = -ang
				gun3d.modulate = gun2d.self_modulate

func _update_camera_3d(delta: float) -> void:
	if _camera_3d == null:
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var px: float = clampf(player.global_position.x * SCALE_3D, 7.0, 23.0)
	var pz: float = clampf(player.global_position.y * SCALE_3D, 4.5, 16.0)
	var p3 := Vector3(px, 0.0, pz)
	var shake: float = float(player.get("_shake_strength")) * SCALE_3D * 0.5 if player.get("_shake_strength") != null else 0.0
	var shake_vec := Vector3(randf_range(-shake, shake), randf_range(-shake, shake), 0.0)
	
	var target_cam_pos := p3 + Vector3(0.0, 11.2, 9.8) + shake_vec
	_camera_3d.position = _camera_3d.position.lerp(target_cam_pos, minf(1.0, 7.5 * delta))
