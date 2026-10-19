extends Area2D
## 각 던전 방 곳곳에 배치되는 랜덤 보급 상자:
## 플레이어가 접근하면 상자가 열리며 무기(샷건/SMG/리볼버/플라즈마건), 장비 유물, 회복 물약 중 하나가 랜덤 드롭됩니다.

signal chest_opened(loot_info: Dictionary)

@export var open_texture: Texture2D = preload("res://assets/Tiles/tile_0091.png")
const GM_SCRIPT: GDScript = preload("res://scripts/game_manager.gd")

var is_opened: bool = false
var last_loot_info: Dictionary = {}

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label: Label = $HintLabel

func _get_gm() -> Node:
	var root_vp: Window = get_tree().root
	var gm: Node = root_vp.get_node_or_null("GameManager")
	if gm == null:
		gm = GM_SCRIPT.new()
		gm.name = "GameManager"
		root_vp.add_child(gm)
	return gm

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if is_opened:
		return
	if body.is_in_group("player"):
		open_chest()

func open_chest() -> void:
	if is_opened:
		return
	is_opened = true
	
	if _sprite != null and open_texture != null:
		_sprite.texture = open_texture
	
	var gm: Node = _get_gm()
	if gm != null:
		last_loot_info = gm.call("roll_and_apply_chest_loot")
	
	var cat: String = String(last_loot_info.get("category", "보급"))
	var title: String = String(last_loot_info.get("title", "보급품"))
	var col: Color = last_loot_info.get("color", Color(1.0, 0.9, 0.4)) as Color
	
	if _label != null:
		_label.text = "[%s] %s!" % [cat, title]
		_label.modulate = col
	
	_spawn_loot_particles(col)
	chest_opened.emit(last_loot_info)

func _spawn_loot_particles(col: Color) -> void:
	if get_tree().current_scene == null:
		return
	for i in range(10):
		var spark := ColorRect.new()
		spark.size = Vector2(3, 3)
		spark.color = col.lightened(0.2) if i % 2 == 0 else Color(1.0, 0.92, 0.45)
		get_tree().current_scene.add_child(spark)
		spark.global_position = global_position + Vector2(randf_range(-4, 4), -4)
		var angle: float = randf_range(0.0, TAU)
		var dist: float = randf_range(12.0, 28.0)
		var target_pos: Vector2 = spark.global_position + Vector2(cos(angle), sin(angle)) * dist
		var tw := spark.create_tween()
		tw.tween_property(spark, "global_position", target_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(spark, "modulate:a", 0.0, 0.35)
		tw.tween_callback(spark.queue_free)
