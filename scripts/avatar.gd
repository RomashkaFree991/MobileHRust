extends Node3D
## Original Rust Humanoid muscle curves, approximately retargeted to the extracted mesh.
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var current := ""

func setup(legs_only: bool = false) -> void:
	var path := "res://assets/character/legs.glb" if legs_only else "res://assets/character/player.glb"
	var model: Node = load(path).instantiate()
	add_child(model)
	skeleton = _find_node(model, "Skeleton3D")
	animation_player = _find_node(model, "AnimationPlayer")
	if animation_player:
		for n in animation_player.get_animation_list():
			if n.begins_with("jump") or n == "RESET": continue
			if animation_player.has_animation(n):
				animation_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play("idle")

func _find_node(n: Node, kind: String):
	if n.is_class(kind): return n
	for child in n.get_children():
		var result = _find_node(child, kind)
		if result: return result
	return null

func _play(n: String) -> void:
	if animation_player and animation_player.has_animation(n) and n != current:
		animation_player.play(n, 0.12)
		current = n

func _direction(v: Vector2) -> String:
	# Input is relative to the camera, with negative Y = forward.
	if v.length_squared() < 0.04: return "N"
	var sector := posmod(int(round(atan2(v.x, -v.y) / (PI / 4.0))), 8)
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][sector]

func animate(_dt: float, speed: float, crouch: bool, grounded: bool, motion: Vector2 = Vector2.ZERO) -> void:
	var direction := _direction(motion)
	if not grounded:
		var j := "jump"
		if speed > 0.8:
			if direction == "N" or direction == "NE" or direction == "NW": j = "jump_forward"
			elif direction == "S" or direction == "SE" or direction == "SW": j = "jump_backward"
			elif direction == "E": j = "jump_right"
			else: j = "jump_left"
		_play(j)
	elif crouch:
		_play(("crouch_walk" if direction == "N" else "crouch_" + direction) if speed > 0.4 else "crouch_idle")
	elif speed > 4.0:
		_play("run")
	elif speed > 0.4:
		_play("walk" if direction == "N" else "walk_" + direction)
	else:
		_play("idle")
