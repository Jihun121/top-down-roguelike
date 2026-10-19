extends StaticBody2D
## 엔터 더 건전 스타일 파괴 가능한 던전 오브젝트 (나무통 / 탄약 상자)
## 총알에 맞으면 흔들리며 점멸하고, 파괴 시 나무 파편이 사방으로 튀며 확률적으로 하트를 드롭합니다.

@export var max_hp: int = 2
@export var is_crate: bool = false

var _hp: int = 2
var _is_broken: bool = false

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	_hp = max_hp
	if is_crate and _sprite != null:
		_sprite.texture = preload("res://assets/Tiles/tile_0063.png")

func take_damage(amount: int) -> void:
	if _is_broken or amount <= 0:
		return
	_hp -= amount
	if _sprite != null:
		_sprite.self_modulate = Color(3.0, 3.0, 3.0, 1.0)
		_sprite.position.x = randf_range(-2.0, 2.0)
		var tw := create_tween()
		tw.tween_property(_sprite, "self_modulate", Color.WHITE, 0.07)
		tw.parallel().tween_property(_sprite, "position:x", 0.0, 0.07)
	
	if _hp <= 0:
		_shatter()

func _shatter() -> void:
	if _is_broken:
		return
	_is_broken = true
	
	# 파편 7개 사방으로 튀기는 연출
	var parent_node: Node = get_parent()
	if parent_node != null:
		for i in range(7):
			var shard := ColorRect.new()
			shard.size = Vector2(3, 2)
			shard.color = Color(0.68, 0.44, 0.24, 1.0) if i % 2 == 0 else Color(0.45, 0.48, 0.55, 1.0)
			parent_node.add_child(shard)
			shard.global_position = global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
			shard.rotation = randf_range(0.0, TAU)
			
			var offset := Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(10.0, 24.0)
			var tw := shard.create_tween()
			tw.tween_property(shard, "global_position", shard.global_position + offset, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_interval(2.5)
			tw.tween_property(shard, "modulate:a", 0.0, 0.5)
			tw.tween_callback(shard.queue_free)
	
	queue_free()
