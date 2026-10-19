extends CanvasLayer
## 좌측 상단 체력/장착 무기/구르기/액티브 스킬(E, R) HUD, 우측 상단 방 번호/잔여 적 표시,
## 중앙 보급 상자 루팅 알림 배너, 보스 체력바, 클리어/게임오버 UI 통합 관리
## (모든 UI를 MarginContainer / HBoxContainer / CenterContainer + 자동 줄바꿈 구조로 배치하여 화면 잘림 원천 방지)

signal upgrade_completed

const GM_SCRIPT: GDScript = preload("res://scripts/game_manager.gd")

var _hp_label: Label
var _weapon_label: Label
var _dash_label: Label
var _skill_label: Label
var _stats_label: Label
var _room_label: Label
var _enemy_label: Label
var _banner_label: Label

var _boss_box: VBoxContainer
var _boss_name_label: Label
var _boss_bar: ProgressBar

var _result_overlay: ColorRect
var _result_title: Label
var _result_summary: Label
var _restart_btn: Button

func _get_gm() -> Node:
	var root_vp: Window = get_tree().root
	var gm: Node = root_vp.get_node_or_null("GameManager")
	if gm == null:
		gm = GM_SCRIPT.new()
		gm.name = "GameManager"
		root_vp.add_child(gm)
	return gm

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	_refresh_all()
	
	var gm: Node = _get_gm()
	if gm != null:
		if gm.has_signal("hp_changed") and not gm.is_connected("hp_changed", _on_hp_changed):
			gm.connect("hp_changed", _on_hp_changed)
		if gm.has_signal("stats_changed") and not gm.is_connected("stats_changed", _refresh_all):
			gm.connect("stats_changed", _refresh_all)
		if gm.has_signal("weapon_changed") and not gm.is_connected("weapon_changed", _on_weapon_changed):
			gm.connect("weapon_changed", _on_weapon_changed)

func _unhandled_input(event: InputEvent) -> void:
	if _result_overlay != null and _result_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_R or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_on_restart_pressed()

func _build_ui() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# 1. 상단 좌/우 HUD 바 (HBoxContainer로 배치하여 텍스트가 길어져도 화면 오른쪽 밖으로 절대 잘리지 않음)
	var top_margin := MarginContainer.new()
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_theme_constant_override("margin_left", 8)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_right", 8)
	root.add_child(top_margin)
	top_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	
	var top_hbox := HBoxContainer.new()
	top_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top_hbox)
	
	# 1-A. 좌측 상단 패널 (체력, 무기, 구르기, 액티브 스킬, 스탯)
	var top_left := PanelContainer.new()
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_left.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.12, 0.86), Color(0.28, 0.34, 0.45, 0.9)))
	top_hbox.add_child(top_left)
	
	var tl_vbox := VBoxContainer.new()
	tl_vbox.add_theme_constant_override("separation", 2)
	top_left.add_child(tl_vbox)
	
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.45))
	tl_vbox.add_child(_hp_label)
	
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 9)
	_weapon_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	tl_vbox.add_child(_weapon_label)
	
	_dash_label = Label.new()
	_dash_label.add_theme_font_size_override("font_size", 8)
	_dash_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	_dash_label.text = "[SPACE] 닷지 롤: 준비됨"
	tl_vbox.add_child(_dash_label)
	
	_skill_label = Label.new()
	_skill_label.add_theme_font_size_override("font_size", 8)
	_skill_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
	_skill_label.text = "💥[E/우클릭] 공포탄: 준비됨 | 🤖[R] 자동포탑: 준비됨"
	tl_vbox.add_child(_skill_label)
	
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 8)
	_stats_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.90))
	tl_vbox.add_child(_stats_label)
	
	# 좌/우 패널 사이 빈 공간 스페이서
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)
	
	# 1-B. 우측 상단 패널 (방 번호 및 잔여 적 카운트 — 오른쪽 끝에 정확히 정렬되어 잘리지 않음)
	var top_right := PanelContainer.new()
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_right.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.12, 0.86), Color(0.28, 0.34, 0.45, 0.9)))
	top_hbox.add_child(top_right)
	
	var tr_vbox := VBoxContainer.new()
	tr_vbox.add_theme_constant_override("separation", 2)
	top_right.add_child(tr_vbox)
	
	_room_label = Label.new()
	_room_label.add_theme_font_size_override("font_size", 10)
	_room_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_vbox.add_child(_room_label)
	
	_enemy_label = Label.new()
	_enemy_label.add_theme_font_size_override("font_size", 9)
	_enemy_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.75))
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_vbox.add_child(_enemy_label)
	
	# 2. 상단 중앙 알림 배너 (자동 줄바꿈 및 화면 중앙 정렬)
	var banner_margin := MarginContainer.new()
	banner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_margin.add_theme_constant_override("margin_left", 90)
	banner_margin.add_theme_constant_override("margin_right", 90)
	banner_margin.add_theme_constant_override("margin_top", 56)
	root.add_child(banner_margin)
	banner_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	
	_banner_label = Label.new()
	_banner_label.custom_minimum_size = Vector2(360, 0)
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 10)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.45))
	_banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner_label.add_theme_constant_override("outline_size", 4)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_margin.add_child(_banner_label)
	
	# 3. 하단 보스 체력바 & 조작 가이드 (Bottom Wide 컨테이너)
	var bottom_margin := MarginContainer.new()
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_theme_constant_override("margin_left", 8)
	bottom_margin.add_theme_constant_override("margin_right", 8)
	bottom_margin.add_theme_constant_override("margin_bottom", 6)
	root.add_child(bottom_margin)
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	
	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vbox.add_theme_constant_override("separation", 4)
	bottom_margin.add_child(bottom_vbox)
	
	_boss_box = VBoxContainer.new()
	_boss_box.custom_minimum_size = Vector2(280, 28)
	_boss_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vbox.add_child(_boss_box)
	
	_boss_name_label = Label.new()
	_boss_name_label.text = "👑 탄약 대왕 (THE BULLET KING)"
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 10)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_boss_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_name_label.add_theme_constant_override("outline_size", 3)
	_boss_box.add_child(_boss_name_label)
	
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(280, 11)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.15, 0.05, 0.05, 0.9), Color(0.5, 0.2, 0.2), 2))
	_boss_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.9, 0.2, 0.25, 1.0), Color(1.0, 0.5, 0.5), 1))
	_boss_box.add_child(_boss_bar)
	
	var help_label := Label.new()
	help_label.text = "WASD: 이동 | 좌클릭: 사격 | SPACE: 구르기 | Q: 무기교체 | E/우클릭: 공포탄 충격파 | R: 자동포탑 설치"
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 8)
	help_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86, 0.88))
	help_label.add_theme_color_override("font_outline_color", Color.BLACK)
	help_label.add_theme_constant_override("outline_size", 2)
	help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vbox.add_child(help_label)
	
	# 4. 게임오버 / 빅토리 결과 오버레이 (CenterContainer + 자동 줄바꿈으로 아이템이 많아도 절대 잘리지 않음!)
	_result_overlay = ColorRect.new()
	_result_overlay.color = Color(0.02, 0.02, 0.05, 0.86)
	_result_overlay.visible = false
	root.add_child(_result_overlay)
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var center_box := CenterContainer.new()
	_result_overlay.add_child(center_box)
	center_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var res_panel := PanelContainer.new()
	res_panel.custom_minimum_size = Vector2(390, 180)
	res_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.1, 0.12, 0.18, 0.96), Color(0.85, 0.72, 0.3, 1.0), 12))
	center_box.add_child(res_panel)
	
	var res_vbox := VBoxContainer.new()
	res_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	res_vbox.add_theme_constant_override("separation", 10)
	res_panel.add_child(res_vbox)
	
	_result_title = Label.new()
	_result_title.custom_minimum_size = Vector2(360, 0)
	_result_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 14)
	res_vbox.add_child(_result_title)
	
	_result_summary = Label.new()
	_result_summary.custom_minimum_size = Vector2(360, 0)
	_result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_summary.add_theme_font_size_override("font_size", 9)
	_result_summary.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	res_vbox.add_child(_result_summary)
	
	_restart_btn = Button.new()
	_restart_btn.custom_minimum_size = Vector2(180, 30)
	_restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_btn.text = "처음부터 다시 도전 (R / SPACE)"
	_restart_btn.add_theme_font_size_override("font_size", 10)
	_restart_btn.pressed.connect(_on_restart_pressed)
	res_vbox.add_child(_restart_btn)

func _make_panel_style(bg: Color, border: Color, margin: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(margin)
	return sb

func _on_weapon_changed(_w_info: Dictionary) -> void:
	_refresh_all()

func _refresh_all() -> void:
	var gm: Node = _get_gm()
	if gm == null:
		return
	_on_hp_changed(int(gm.get("current_hp")), int(gm.get("max_hp")))
	if _weapon_label != null:
		var w_name: String = String(gm.call("get_current_weapon_name"))
		var owned: Array = gm.get("owned_weapons")
		var switch_hint: String = " ([Q] 교체 %d종)" % owned.size() if owned.size() > 1 else ""
		_weapon_label.text = "🔫 %s%s" % [w_name, switch_hint]
	if _stats_label != null:
		_stats_label.text = "화력 %d | 탄수 %d발 | 이동속도 %d" % [
			int(gm.get("bullet_damage")),
			int(gm.get("multi_shot")),
			int(float(gm.get("move_speed")))
		]
	if _room_label != null:
		_room_label.text = "ROOM %d / %d — %s" % [
			int(gm.get("current_room")),
			int(gm.get("MAX_ROOMS")),
			String(gm.call("get_room_title"))
		]

func _on_hp_changed(cur: int, maximum: int) -> void:
	if _hp_label == null:
		return
	var hearts: String = ""
	for i in range(maximum):
		hearts += "♥ " if i < cur else "♡ "
	_hp_label.text = "HP: %s(%d/%d)" % [hearts, cur, maximum]

func update_dash_status(remaining: float, _total: float) -> void:
	if _dash_label == null:
		return
	if remaining <= 0.01:
		_dash_label.text = "[SPACE] 닷지 롤: 준비됨"
		_dash_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	else:
		_dash_label.text = "[SPACE] 닷지 롤: %.1f초" % remaining
		_dash_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))

func update_skills_status(blank_rem: float, storm_rem: float, overdrive_rem: float) -> void:
	if _skill_label == null:
		return
	var b_str: String = "준비됨" if blank_rem <= 0.05 else "%.1f초" % blank_rem
	var s_str: String = ""
	if overdrive_rem > 0.05:
		s_str = "⚙️가동중(%.1fs)" % overdrive_rem
	elif storm_rem <= 0.05:
		s_str = "준비됨"
	else:
		s_str = "%.1f초" % storm_rem
	_skill_label.text = "💥[E/우클릭] 공포탄: %s | 🤖[R] 자동포탑: %s" % [b_str, s_str]
	if overdrive_rem > 0.05:
		_skill_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	elif blank_rem <= 0.05 or storm_rem <= 0.05:
		_skill_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
	else:
		_skill_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8))

func update_enemy_count(alive_count: int, is_rest_room: bool = false) -> void:
	if _enemy_label == null:
		return
	if is_rest_room:
		_enemy_label.text = "보급 구역 (상자 확인)"
		_enemy_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	elif alive_count > 0:
		_enemy_label.text = "잔여 몬스터: %d마리 (📦보급상자 파밍)" % alive_count
		_enemy_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.68))
	else:
		_enemy_label.text = "클리어! ▲ 북쪽 성문 개방됨"
		_enemy_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))

func update_boss_hp(cur: int, maximum: int) -> void:
	if _boss_box == null or _boss_bar == null:
		return
	_boss_box.visible = cur > 0
	_boss_bar.max_value = maximum
	_boss_bar.value = cur

func show_banner(text: String, duration: float = 2.2) -> void:
	if _banner_label == null:
		return
	_banner_label.text = text
	_banner_label.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_property(_banner_label, "modulate:a", 0.0, 0.4)

func show_upgrade_choices() -> void:
	upgrade_completed.emit()

func show_game_over() -> void:
	var gm: Node = _get_gm()
	if _result_overlay == null or gm == null:
		return
	_result_title.text = "☠ GAME OVER — 던전에서 쓰러졌습니다"
	_result_title.add_theme_color_override("font_color", Color(1.0, 0.38, 0.38))
	var ups: Array = gm.get("acquired_upgrades")
	var up_str: String = ", ".join(ups) if not ups.is_empty() else "기본 장비"
	_result_summary.text = "도달 구역: ROOM %d / %d (%s)\n처치한 몬스터: %d마리  |  생존 시간: %.1f초\n획득 무장/아이템: %s" % [
		int(gm.get("current_room")),
		int(gm.get("MAX_ROOMS")),
		String(gm.call("get_room_title")),
		int(gm.get("total_kills")),
		float(gm.get("run_time_sec")),
		up_str
	]
	_result_overlay.visible = true
	get_tree().paused = true

func show_victory() -> void:
	var gm: Node = _get_gm()
	if _result_overlay == null or gm == null:
		return
	gm.set("is_run_active", false)
	_result_title.text = "👑 VICTORY! — 모든 던전 방을 정복했습니다!"
	_result_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	var ups: Array = gm.get("acquired_upgrades")
	var up_str: String = ", ".join(ups) if not ups.is_empty() else "기본 장비"
	_result_summary.text = "최종 보스 '탄약 대왕 (Bullet King)' 처치 완료!\n총 처치 몬스터: %d마리  |  클리어 기록: %.1f초\n최종 무장/아이템: %s" % [
		int(gm.get("total_kills")),
		float(gm.get("run_time_sec")),
		up_str
	]
	_result_overlay.visible = true
	get_tree().paused = true

func _on_restart_pressed() -> void:
	if _result_overlay != null:
		_result_overlay.visible = false
	get_tree().paused = false
	var gm: Node = _get_gm()
	if gm != null:
		gm.call("restart_game")
