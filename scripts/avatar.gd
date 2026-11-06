extends Node3D
## Player character (third person, inventory portrait) and the legs-only body seen when looking down in first person.
## Animation clips come from the converted Humanoid curves; on top of them a SkeletonModifier3D raises the arms
## for the held weapon and tilts the torso with the camera pitch.

## One skin colour shared by the character body and the first-person arms, so hands never differ from the body.
const SKIN_TINT := Color(1.0, 0.86, 0.77)
const BODY_MEAN := Color(0.695, 0.693, 0.686)  # mean colour of the body texture
const SKIN_PARTS := ["Torso", "Hands", "Head", "Feet", "Underwear_Legs"]

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var current := ""
var legs_only := false

# upper body state (set by the player every frame)
var hold_kind := ""        # "", "rifle", "pistol", "melee", "tool"
var aim_amount := 0.0
var ready_t := 0.0
var kick := 0.0
var reload_t := 0.0
var look_pitch := 0.0
var gun: Node3D
var _gun_key := ""
var _attach: BoneAttachment3D
var _mod: SkeletonModifier3D
var _bones := {}


static func skin_color() -> Color:
	return Color(BODY_MEAN.r * SKIN_TINT.r, BODY_MEAN.g * SKIN_TINT.g, BODY_MEAN.b * SKIN_TINT.b)


class PoseMod extends SkeletonModifier3D:
	var owner_avatar
	func _process_modification() -> void:
		owner_avatar._apply_pose()


func setup(only_legs: bool = false) -> void:
	legs_only = only_legs
	var path := "res://assets/character/legs.glb" if only_legs else "res://assets/character/player.glb"
	var model: Node = load(path).instantiate()
	add_child(model)
	skeleton = _find_node(model, "Skeleton3D")
	animation_player = _find_node(model, "AnimationPlayer")
	_apply_skin(model)
	if animation_player:
		for n in animation_player.get_animation_list():
			if n.begins_with("jump") or n == "RESET": continue
			if animation_player.has_animation(n):
				animation_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play("idle")
	if skeleton and not only_legs:
		for b in ["r_upperarm", "r_forearm", "l_upperarm", "l_forearm", "spine2", "spine3", "spine4", "neck", "r_hand"]:
			_bones[b] = skeleton.find_bone(b)
		_mod = PoseMod.new()
		_mod.owner_avatar = self
		skeleton.add_child(_mod)
		_attach = BoneAttachment3D.new()
		_attach.bone_name = "r_hand"
		skeleton.add_child(_attach)


func _apply_skin(model: Node) -> void:
	var skin := Color(SKIN_TINT)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var matched := false
		for part in SKIN_PARTS:
			if String(mi.name).contains(part):
				matched = true
		if not matched:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var m = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D:
				var d: StandardMaterial3D = m.duplicate()
				d.albedo_color = skin
				mi.set_surface_override_material(si, d)


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


func animate(dt: float, speed: float, crouch: bool, grounded: bool, motion: Vector2 = Vector2.ZERO) -> void:
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
	# smooth upper-body weights
	var want := 0.0 if hold_kind == "" else 1.0
	ready_t = move_toward(ready_t, want, dt * 5.0)
	kick = move_toward(kick, 0.0, dt * 6.0)


# ---------------------------------------------------------------- held weapon
const GUNS := {
	# key: [scene, mesh-name prefix to keep, offset that centres the viewmodel mesh, euler degrees in hand space]
	"ak47": ["res://assets/weapons/ak47/v_ak47.glb", "ak47_", Vector3(0.085, -1.52, 0.07), Vector3(0, 180, 0)],
	"semi": ["res://assets/weapons/semi/v_semi.glb", "semi_pistol_mesh", Vector3(0.0, -1.48, 0.03), Vector3(0, 180, 0)],
	"revolver": ["res://assets/weapons/revolver/v_revolver.glb", "v_revolver_mesh", Vector3(0.0, -0.03, 0.18), Vector3(0, 180, 0)],
	"rock": ["res://assets/weapons/rock/v_rock.glb", "w_rock", Vector3(0.0, 0.0, 0.0), Vector3(0, 180, 0)],
}


func hold(key: String, kind: String) -> void:
	hold_kind = kind
	if _attach == null or key == _gun_key:
		return
	_gun_key = key
	if gun:
		gun.queue_free()
		gun = null
	if key == "" or not GUNS.has(key):
		return
	var g: Array = GUNS[key]
	var inst: Node3D = load(g[0]).instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).begins_with(String(g[1])):
			mi.visible = false
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	var holder := Node3D.new()
	inst.position = g[2]
	holder.rotation_degrees = g[3]
	holder.add_child(inst)
	_attach.add_child(holder)
	gun = holder


# ---------------------------------------------------------------- procedural upper body
func _rot(bone: String, q: Quaternion) -> void:
	var i: int = _bones.get(bone, -1)
	if i >= 0:
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * q)


## Pose tables: [bone, axis, degrees]. Axis X raises the upper arm forward; the forearm hinge is tuned per rig.
var pose_rifle := [["r_upperarm", Vector3.RIGHT, 62.0], ["r_forearm", Vector3.BACK, -40.0],
	["l_upperarm", Vector3.RIGHT, 58.0], ["l_forearm", Vector3.BACK, 55.0]]
var pose_pistol := [["r_upperarm", Vector3.RIGHT, 72.0], ["r_forearm", Vector3.BACK, -15.0]]
var pose_tool := [["r_upperarm", Vector3.RIGHT, 38.0], ["r_forearm", Vector3.BACK, -45.0]]


func _apply_table(table: Array, w: float) -> void:
	for e in table:
		_rot(e[0], Quaternion(e[1], deg_to_rad(float(e[2]) * w)))


func _apply_pose() -> void:
	var rd := ready_t
	if rd > 0.01:
		match hold_kind:
			"rifle": _apply_table(pose_rifle, rd * (1.0 + 0.12 * aim_amount))
			"pistol": _apply_table(pose_pistol, rd * (1.0 + 0.1 * aim_amount))
			_: _apply_table(pose_tool, rd)
	if reload_t > 0.0:
		# bring the weapon in front of the chest while reloading
		var w := sin(clampf(reload_t, 0.0, 1.0) * PI)
		_rot("r_upperarm", Quaternion(Vector3.RIGHT, deg_to_rad(-14.0 * w)))
		_rot("l_forearm", Quaternion(Vector3.BACK, deg_to_rad(20.0 * w)))
	# look up / down with the torso and head, plus a little recoil kick
	var lp := clampf(look_pitch, -1.2, 1.2)
	for b in ["spine2", "spine3", "spine4"]:
		_rot(b, Quaternion(Vector3.RIGHT, -lp * 0.17 - kick * 0.03))
	_rot("neck", Quaternion(Vector3.RIGHT, -lp * 0.3))
