extends Node3D
## First-person weapons built from Rust viewmodels: deploy / idle / ADS / fire / reload / inspect / dry fire,
## melee + throw for the rock, timed sound events (taken from the Rust animation events), muzzle FX, shells.

const BASE_FOV := 75.0

const WEAPONS := [
	{
		"key": "ak47", "name": "Assault Rifle", "scene": "res://assets/weapons/ak47/v_ak47.glb",
		"icon": "res://assets/ui/icons/rifle.ak.png",
		"offset": Vector3(0.085, -1.52, 0.07),
		"muzzle": ["joint8", Vector3(-0.0029, 0.0562, 0.5563)],
		"eject": ["joint8", Vector3(-0.0188, 0.0751, 0.1704)],
		"auto": true, "interval": 0.1333, "mag": 30, "reserve": 120,
		"spread": [1.3, 0.2], "recoil": [1.2, 0.55], "ads_fov": 45.0, "ads_zoom": 1.6667, "ads_fwd": 0.08,
		"ads_eye": ["joint8", Vector3(-0.0012, 0.1109, -0.183)], "ads_target": ["joint8", Vector3(-0.0006, 0.1134, 0.52)],
		"idle": "idle", "idle_ads": "idle_ads", "fire": ["fire-1", "fire-2", "fire-3"], "fire_ads": ["fire_ads"],
		"reload": "reload", "deploy": "deploy", "holster": "holster", "inspect": "admire", "dryfire": "dryfire",
		"deploy_time": 1.0, "reload_fill": 4.47, "reload_end": 4.8,
		"fx": "ak_attack", "fx_eject": "eject_rifle", "shell": "rifle", "eject_delay": 0.05,
		"snd_fire": "ak/attack.ogg", "fire_vol": -3.0,
		"events": {
			"deploy": [[0.004, "ak/deploy.wav"], [0.334, "ak/bolt_back.wav"], [0.844, "ak/bolt_forward.wav"]],
			"reload": [[0.0, "ak/reload_start.ogg"], [1.327, "ak/grab_magazine.wav"], [2.229, "ak/insert_magazine.wav"],
				[3.784, "ak/bolt_back.wav"], [4.471, "ak/bolt_forward.wav"]],
			"holster": [[0.003, "ak/holster.wav"]],
			"dryfire": [[0.001, "semi/dryfire.wav"]],
		},
	},
	{
		"key": "semi", "name": "Semi-Automatic Pistol", "scene": "res://assets/weapons/semi/v_semi.glb",
		"icon": "res://assets/ui/icons/pistol.semiauto.png",
		"offset": Vector3(0.0, -1.48, 0.03),
		"muzzle": ["joint14", Vector3(0.0, 0.0576, 0.2638)],
		"eject": ["joint14", Vector3(0.0002, 0.0603, 0.1038)],
		"auto": false, "interval": 0.15, "mag": 10, "reserve": 60,
		"spread": [1.0, 0.25], "recoil": [2.0, 0.6], "ads_fov": 65.0, "ads_zoom": 1.1538,
		"ads_eye": ["slide", Vector3(-0.3279, 0.0231, 0.0005)], "ads_target": ["slide", Vector3(0.0931, 0.023, 0.0)],
		"idle": "idle", "idle_ads": "idle_ads", "fire": ["fire-1", "fire-2", "fire-3"], "fire_ads": ["fire_ads"],
		"reload": "reload", "deploy": "deploy", "holster": "", "inspect": "admire", "dryfire": "dryfire",
		"deploy_time": 0.6, "reload_fill": 1.6, "reload_end": 2.6,
		"fx": "semi_attack", "fx_eject": "eject_pistol", "shell": "pistol", "eject_delay": 0.04,
		"snd_fire": "semi/attack.wav", "fire_vol": -3.0,
		"events": {
			"deploy": [[0.004, "semi/deploy.wav"]],
			"reload": [[0.0, "semi/deploy.wav"], [0.336, "semi/eject_clip.wav"], [0.682, "semi/grab_clip.wav"],
				[1.461, "semi/insert_clip.wav"]],
			"dryfire": [[0.001, "semi/dryfire.wav"]],
		},
	},
	{
		"key": "revolver", "name": "Revolver", "scene": "res://assets/weapons/revolver/v_revolver.glb",
		"icon": "res://assets/ui/icons/pistol.revolver.png",
		"offset": Vector3(0.0, -0.03, 0.18),
		"muzzle": ["pivot", Vector3(0.0117, 0.0441, 0.1314)],
		"auto": false, "interval": 0.175, "mag": 8, "reserve": 48,
		"spread": [1.2, 0.3], "recoil": [2.8, 0.8], "ads_fov": 65.0, "ads_zoom": 1.1538,
		"ads_eye": ["_ROOT_revolver", Vector3(-0.3027, -0.0738, -0.0008)], "ads_target": ["_ROOT_revolver", Vector3(0.1721, 0.2065, -0.0005)],
		"idle": "idle_idle", "idle_ads": "idle_idle_ADS", "fire": ["attack"], "fire_ads": ["attack_ads"],
		"reload": "reload", "deploy": "deploy", "holster": "holster", "inspect": "admire", "dryfire": "dryfire",
		"deploy_time": 0.7, "reload_fill": 3.03, "reload_end": 3.5, "reload_shells": [1.35, 4],
		"fx": "revolver_attack",
		"snd_fire": "revolver/attack.wav", "fire_vol": -2.0,
		"events": {
			"deploy": [[0.009, "revolver/deploy.wav"]],
			"dryfire": [[0.009, "revolver/prime_striker.wav"]],
			"reload": [[0.537, "revolver/open_cylinder.wav"], [1.315, "revolver/eject_shells.wav"],
				[2.122, "revolver/insert_shells.wav"], [3.026, "revolver/shut_cylinder.wav"]],
		},
	},
	{
		"key": "rock", "name": "Rock", "scene": "res://assets/weapons/rock/v_rock.glb",
		"icon": "res://assets/ui/icons/rock.png",
		"offset": Vector3(0.0, -0.01, 0.13),
		"melee": true, "interval": 1.0, "range": 1.9, "strike": [0.528, 0.533],
		"idle": "idle", "attacks": ["attack_1", "attack_2"], "deploy": "deploy", "holster": "holster", "inspect": "admire",
		"deploy_time": 0.6,
		"events": {
			"deploy": [[0.0, "rock/deploy.wav"]],
			"holster": [[0.0, "rock/holster.wav"]],
			"attack_1": [[0.022, "rock/attack.wav"]],
			"attack_2": [[0.049, "rock/attack.wav"]],
			"throw": [[0.05, "rock/attack.wav"]],
		},
	},
]

var player  # player.gd (CharacterBody3D)
var inventory
var cam: Camera3D
var sway: Node3D
var ads_node: Node3D   # Sway -> Ads (iron-sight alignment) -> Pivot -> weapon
var pivot: Node3D
var weapons: Array = []
var cur: Dictionary = {}
var cur_i := -1
var state := "idle"
var state_t := 0.0
var cooldown := 0.0
var fire_buffer := 0.0
var aiming := false
var aim_toggle := false
var events: Array = []
var ev_t := 0.0
var melee_i := 1
var anim_label := ""
var message := ""
var message_t := 0.0
var bob_t := 0.0
var sprint_f := 0.0
var ads_f := 0.0
var pull_f := 0.0
var land_f := 0.0
var sway_rot := Vector2.ZERO
var rock_mesh: Mesh
var _pose_dirty := false


func _ready() -> void:
	cam = get_parent() as Camera3D
	sway = Node3D.new()
	sway.name = "Sway"
	add_child(sway)
	ads_node = Node3D.new()
	ads_node.name = "Ads"
	sway.add_child(ads_node)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	ads_node.add_child(pivot)
	for i in range(WEAPONS.size()):
		weapons.append(_setup_weapon(WEAPONS[i], i))
	switch_to(0)


# ---------------------------------------------------------------- setup
func _setup_weapon(d: Dictionary, idx: int) -> Dictionary:
	var w := {"def": d, "ammo": int(d.get("mag", 0)), "reserve": int(d.get("reserve", 0)), "show_i": -1, "ap": null}
	var scn = load(d["scene"])
	if not (scn is PackedScene):
		push_error("Weapon scene missing: " + str(d["scene"]))
		w["node"] = Node3D.new()
		pivot.add_child(w["node"])
		return w
	var inst: Node3D = scn.instantiate()
	inst.name = str(d["key"])
	pivot.add_child(inst)
	var off: Vector3 = d["offset"]
	inst.position = Vector3(-off.x, off.y, off.z)
	inst.visible = false
	for gi in inst.find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.extra_cull_margin = 3.0
		if gi is MeshInstance3D and gi.mesh:
			if d["key"] == "rock" and String(gi.name).begins_with("w_rock"):
				rock_mesh = gi.mesh
			for si in range(gi.mesh.get_surface_count()):
				var m = gi.mesh.surface_get_material(si)
				if m is StandardMaterial3D and m.resource_name == "ViewModel_Arms":
					gi.set_surface_override_material(si, _arms_material(m))
	w["node"] = inst
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		for n in [str(d.get("idle", "")), str(d.get("idle_ads", ""))]:
			if n != "" and ap.has_animation(n):
				var a := ap.get_animation(n)
				if a.length < 0.05:
					a.length = 0.1
				a.loop_mode = Animation.LOOP_LINEAR
		ap.animation_finished.connect(_on_anim_finished.bind(idx))
		ap.active = false
		w["ap"] = ap
	else:
		push_warning("No AnimationPlayer in " + str(d["scene"]))
	if d.has("muzzle"):
		w["muzzle"] = _attach(inst, str(d["muzzle"][0]), d["muzzle"][1])
	if d.has("eject"):
		w["eject"] = _attach(inst, str(d["eject"][0]), d["eject"][1])
	if d.has("ads_eye") and w["ap"] != null:
		w["ads_xf"] = _compute_ads(inst, w["ap"], d)
	return w


## Rust IronSights: the viewmodel is moved so that the aim point ("ironsight_default", the eye) sits in the
## camera origin and the line aim point -> target point looks straight down the camera axis.
## Evaluated once on the first frame of the ADS idle pose.
func _compute_ads(inst: Node, ap: AnimationPlayer, d: Dictionary) -> Transform3D:
	var anim := str(d.get("idle_ads", ""))
	if not ap.has_animation(anim):
		return Transform3D.IDENTITY
	var skel: Skeleton3D = null
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		if sk.find_bone(str(d["ads_eye"][0])) >= 0:
			skel = sk
	if skel == null:
		return Transform3D.IDENTITY
	ap.active = true
	ap.play(anim)
	ap.seek(0.0, true)
	var bi_e := skel.find_bone(str(d["ads_eye"][0]))
	var bi_t := skel.find_bone(str(d["ads_target"][0]))
	var to_ads := ads_node.global_transform.affine_inverse() * skel.global_transform
	var eye: Vector3 = to_ads * (skel.get_bone_global_pose(bi_e) * (d["ads_eye"][1] as Vector3))
	var tgt: Vector3 = to_ads * (skel.get_bone_global_pose(bi_t) * (d["ads_target"][1] as Vector3))
	ap.stop()
	ap.active = false
	var fwd := (tgt - eye).normalized()
	if fwd.length() < 0.5:
		return Transform3D.IDENTITY
	# Rust puts the eye right at the butt plate of the AK; nudge it forward along the sight line so the near
	# plane does not slice through the stock (sight alignment is unchanged).
	eye += fwd * float(d.get("ads_fwd", 0.0))
	var b := Basis(Quaternion(fwd, Vector3(0.0, 0.0, -1.0)))
	return Transform3D(b, -(b * eye))


var _arms_mat: StandardMaterial3D
var last_hit := ""  # debug/autotest: "<surface>@<distance>"


## Rust arm textures were not in the downloaded part of the archive -> neutral skin tone instead.
func _arms_material(src: StandardMaterial3D) -> StandardMaterial3D:
	if _arms_mat == null:
		_arms_mat = src.duplicate()
		_arms_mat.albedo_color = load("res://scripts/avatar.gd").skin_color()
		_arms_mat.metallic = 0.0
		_arms_mat.roughness = 0.62
		_arms_mat.metallic_specular = 0.35
	return _arms_mat


## Node that follows bone `bone` (BoneAttachment3D) with a local offset (glTF space of the bone).
func _attach(inst: Node, bone: String, offset: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "attach_" + bone
	n.position = offset
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		if sk.find_bone(bone) >= 0:
			var ba := BoneAttachment3D.new()
			ba.name = "BA_" + bone
			ba.bone_name = bone
			sk.add_child(ba)
			ba.add_child(n)
			return n
	var nd = inst.find_child(bone, true, false)
	if nd is Node3D:
		nd.add_child(n)
	else:
		push_warning("Bone not found: " + bone)
		inst.add_child(n)
	return n


# ---------------------------------------------------------------- animation helpers
func _ap() -> AnimationPlayer:
	return cur.get("ap") as AnimationPlayer


func _play(anim: String, blend: float = 0.1, restart: bool = true) -> void:
	var ap := _ap()
	if ap == null or anim == "" or not ap.has_animation(anim):
		return
	if ap.current_animation == anim and ap.is_playing():
		if restart:
			ap.seek(0.0, true)
	else:
		ap.play(anim, blend)
	anim_label = anim
	events = []
	ev_t = 0.0
	var evs: Dictionary = cur["def"].get("events", {})
	for e in evs.get(anim, []):
		events.append([float(e[0]), e[1]])


func _add_event(t: float, what) -> void:
	events.append([ev_t + t, what])
	events.sort_custom(func(a, b): return a[0] < b[0])


func _update_events(dt: float) -> void:
	ev_t += dt
	while events.size() > 0 and float(events[0][0]) <= ev_t:
		var e: Array = events.pop_front()
		var what = e[1]
		if what is Callable:
			what.call()
		elif what is String:
			FX.play2d(what, -4.0, 0.02)


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0


func _idle_name() -> String:
	var d: Dictionary = cur["def"]
	var ap := _ap()
	if aiming and ap and ap.has_animation(str(d.get("idle_ads", ""))):
		return str(d["idle_ads"])
	return str(d["idle"])


func _go_idle(blend: float = 0.2) -> void:
	_set_state("idle")
	_play(_idle_name(), blend, false)


func _on_anim_finished(_anim: StringName, idx: int) -> void:
	if idx != cur_i:
		return
	match state:
		"throw_hold":
			return
		"throw":
			var d: Dictionary = cur["def"]
			_set_state("deploy")
			_play(str(d["deploy"]), 0.0)
			cooldown = float(d["deploy_time"])
		_:
			_go_idle(0.2)


# ---------------------------------------------------------------- public API (HUD / input)
func switch_to(i: int) -> void:
	if i < 0 or i >= weapons.size() or i == cur_i:
		return
	if not cur.is_empty():
		cur["node"].visible = false
		var oap := _ap()
		if oap:
			oap.stop()
			oap.active = false
	cur_i = i
	cur = weapons[i]
	cur["node"].visible = true
	aiming = false
	aim_toggle = false
	var ap := _ap()
	if ap:
		ap.active = true
	var d: Dictionary = cur["def"]
	_set_state("deploy")
	_play(str(d["deploy"]), 0.0)
	cooldown = 0.0


func select_slot(k: int) -> void:
	if inventory:
		inventory.select(k)
	elif k < weapons.size():
		switch_to(k)


func unequip() -> void:
	if not cur.is_empty():
		cur["node"].visible = false
		var ap := _ap()
		if ap:
			ap.stop()
			ap.active = false
	cur = {}
	cur_i = -1
	aiming = false
	aim_toggle = false
	events.clear()
	_set_state("idle")


func _reserve() -> int:
	if cur.is_empty(): return 0
	if inventory: return inventory.reserve_for(cur_i)
	return int(cur["reserve"])


func show_message(t: String, dur: float = 2.5) -> void:
	message = t
	message_t = dur


func weapon_name() -> String:
	return "" if cur.is_empty() else str(cur["def"]["name"])


func ammo_text() -> String:
	if cur.is_empty() or cur["def"].get("melee", false):
		return ""
	return "%d / %d" % [int(cur["ammo"]), _reserve()]


func blocks_sprint() -> bool:
	return aiming or state in ["fire", "reload", "melee", "throw_hold", "throw"] or Input.is_action_pressed("fire")


func land() -> void:
	land_f = 1.0


# ---------------------------------------------------------------- main loop
func _process(dt: float) -> void:
	if cur.is_empty():
		message_t = maxf(0.0, message_t - dt)
		if player.hud == null or not player.hud.inventory_open:
			for k in range(6):
				if Input.is_action_just_pressed("slot_%d" % (k + 1)): select_slot(k)
		return
	state_t += dt
	cooldown = maxf(0.0, cooldown - dt)
	fire_buffer = maxf(0.0, fire_buffer - dt)
	message_t = maxf(0.0, message_t - dt)
	_update_events(dt)
	_handle_input()
	_update_aim(dt)
	_update_motion(dt)


func _handle_input() -> void:
	if player.hud != null and player.hud.inventory_open:
		fire_buffer = 0.0
		return
	for k in range(6):
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			select_slot(k)
	if Input.is_action_just_pressed("weapon_next"):
		select_slot((inventory.selected_belt + 1) % 6 if inventory else (cur_i + 1) % weapons.size())
	elif Input.is_action_just_pressed("weapon_prev"):
		select_slot((inventory.selected_belt + 5) % 6 if inventory else (cur_i + weapons.size() - 1) % weapons.size())
	var d: Dictionary = cur["def"]
	var melee := bool(d.get("melee", false))
	var deploying := state == "deploy" and state_t < float(d["deploy_time"])
	if Input.is_action_just_pressed("anim_next"):
		_showcase_next()
		return
	if Input.is_action_just_pressed("fire"):
		fire_buffer = 0.2
	if melee:
		_update_rock(deploying)
		return
	if deploying:
		return
	if Input.is_action_just_pressed("inspect") and state in ["idle", "fire", "dry", "show"]:
		_inspect()
		return
	if Input.is_action_just_pressed("reload") and state != "reload":
		_reload()
	if state == "reload":
		return
	var want: bool = Input.is_action_pressed("fire") if bool(d.get("auto", false)) else fire_buffer > 0.0
	if want and cooldown <= 0.0:
		fire_buffer = 0.0
		_fire()


func _update_rock(deploying: bool) -> void:
	var aim_down := Input.is_action_pressed("aim") or aim_toggle
	match state:
		"throw_hold":
			if fire_buffer > 0.0:
				fire_buffer = 0.0
				_throw()
			elif not aim_down:
				_set_state("cancel")
				_play("throw_cancel", 0.1)
			return
		"throw", "cancel":
			return
	if deploying:
		return
	if Input.is_action_just_pressed("inspect") and state in ["idle", "show"]:
		_inspect()
		return
	if aim_down and state in ["idle", "show", "inspect"]:
		_set_state("throw_hold")
		_play("throw_hold", 0.15)
		return
	if Input.is_action_pressed("fire") and cooldown <= 0.0:
		fire_buffer = 0.0
		_melee()


# ---------------------------------------------------------------- actions
func _fire() -> void:
	var d: Dictionary = cur["def"]
	if int(cur["ammo"]) <= 0:
		cooldown = 0.35
		_set_state("dry")
		_play(str(d["dryfire"]), 0.05, true)
		if _reserve() > 0:
			show_message("Магазин пуст — перезарядка (R)", 1.5)
		else:
			show_message("Патроны закончились", 1.5)
		return
	cur["ammo"] = int(cur["ammo"]) - 1
	cooldown = float(d["interval"])
	var list: Array = d["fire_ads"] if aiming else d["fire"]
	_set_state("fire")
	_play(str(list[randi() % list.size()]), 0.02, true)
	FX.play2d(str(d["snd_fire"]), float(d.get("fire_vol", 0.0)), 0.025)
	_muzzle_fx()
	if cur.has("eject") and d.has("fx_eject"):
		_add_event(float(d["eject_delay"]), _eject)
	_shoot()
	var rc: Array = d["recoil"]
	var m := 0.6 if aiming else 1.0
	player.add_recoil(float(rc[0]) * m * randf_range(0.8, 1.15), float(rc[1]) * m)
	player.shake(0.3)


func _shoot() -> void:
	var d: Dictionary = cur["def"]
	var sp: Array = d["spread"]
	var spread := float(sp[1]) if aiming else float(sp[0])
	spread += Vector2(player.velocity.x, player.velocity.z).length() * 0.3
	if not player.is_on_floor():
		spread += 2.0
	var hit := _ray(300.0, spread)
	if hit.is_empty():
		return
	var col = hit["collider"]
	last_hit = "%s@%.1fm" % [_surface(col), cam.global_position.distance_to(hit["position"])]
	FX.bullet_impact(_surface(col), hit["position"], hit["normal"])
	if col is RigidBody3D:
		col.apply_impulse((hit["position"] - cam.global_position).normalized() * 1.5, hit["position"] - col.global_position)


func _ray(dist: float, spread_deg: float) -> Dictionary:
	var b := cam.global_basis
	var fwd := -b.z
	if spread_deg > 0.0:
		var s := deg_to_rad(spread_deg) * 0.5
		fwd = (fwd + b.x * randfn(0.0, s) + b.y * randfn(0.0, s)).normalized()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * dist, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _surface(col) -> String:
	if col is Object and col.has_meta("surface"):
		return str(col.get_meta("surface"))
	return "concrete"


func _muzzle_fx() -> void:
	var m: Node3D = cur.get("muzzle")
	if m == null:
		return
	var fwd := -cam.global_basis.z
	var bz := m.global_basis.z.normalized()
	var dir := bz if bz.dot(fwd) > 0.85 else fwd
	FX.spawn(str(cur["def"]["fx"]), Transform3D(FX.basis_from_z(dir), m.global_position), self, 6)


func _eject() -> void:
	var e: Node3D = cur.get("eject")
	if e == null:
		return
	var d: Dictionary = cur["def"]
	var b := cam.global_basis
	var dir := (b.x + b.y * 0.6 - b.z * 0.1).normalized()
	FX.spawn(str(d["fx_eject"]), Transform3D(FX.basis_from_z(dir), e.global_position), null, 4)
	FX.spawn_shell(str(d["shell"]), e.global_position + dir * 0.02, dir * randf_range(2.0, 3.0) + player.velocity)


func _reload() -> void:
	var d: Dictionary = cur["def"]
	if int(cur["ammo"]) >= int(d["mag"]):
		return
	if _reserve() <= 0:
		show_message("Нет патронов в запасе", 1.5)
		return
	_set_state("reload")
	_play(str(d["reload"]), 0.12, true)
	_add_event(float(d["reload_fill"]), _reload_fill)
	_add_event(float(d["reload_end"]), _reload_done)
	if d.has("reload_shells"):
		var rs: Array = d["reload_shells"]
		_add_event(float(rs[0]), _drop_shells.bind(int(rs[1])))


func _reload_fill() -> void:
	var need := int(cur["def"]["mag"]) - int(cur["ammo"])
	var take := mini(need, _reserve())
	if inventory:
		take = inventory.consume_for(cur_i, take)
	else:
		cur["reserve"] = int(cur["reserve"]) - take
	cur["ammo"] = int(cur["ammo"]) + take


func _reload_done() -> void:
	if state == "reload":
		_set_state("idle")


func _drop_shells(n: int) -> void:
	var m: Node3D = cur.get("muzzle")
	if m == null:
		return
	var b := cam.global_basis
	for i in range(n):
		var p := m.global_position + b.z * 0.12 + b.x * randf_range(-0.02, 0.02)
		FX.spawn_shell("pistol", p, Vector3(randf_range(-0.3, 0.3), -1.0, randf_range(-0.3, 0.3)) + player.velocity)


func _inspect() -> void:
	_set_state("inspect")
	_play(str(cur["def"]["inspect"]), 0.2, true)


func _showcase_next() -> void:
	var ap := _ap()
	if ap == null:
		return
	var list: Array = []
	for n in ap.get_animation_list():
		if n != "RESET":
			list.append(String(n))
	if list.is_empty():
		return
	var i := (int(cur["show_i"]) + 1) % list.size()
	cur["show_i"] = i
	_set_state("show")
	_play(list[i], 0.1, true)
	show_message("Анимация %d/%d: %s" % [i + 1, list.size(), list[i]], 3.0)


func _melee() -> void:
	var d: Dictionary = cur["def"]
	cooldown = float(d["interval"])
	melee_i = 1 - melee_i
	var anims: Array = d["attacks"]
	var strikes: Array = d["strike"]
	_set_state("melee")
	_play(str(anims[melee_i]), 0.05, true)
	_add_event(float(strikes[melee_i]), _melee_strike)


func _melee_strike() -> void:
	var hit := _ray(float(cur["def"]["range"]), 0.0)
	if hit.is_empty():
		return
	FX.blunt_impact(_surface(hit["collider"]), hit["position"], hit["normal"])
	FX.play3d("rock/strike_%d.wav" % randi_range(1, 4), hit["position"], -3.0)
	player.shake(0.6)
	var col = hit["collider"]
	if col is RigidBody3D:
		col.apply_impulse(-cam.global_basis.z * 3.0, hit["position"] - col.global_position)


func _throw() -> void:
	aim_toggle = false
	_set_state("throw")
	_play("throw", 0.05)
	_add_event(0.2, _release_rock)


func _release_rock() -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1
	rb.mass = 1.0
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.07
	cs.shape = sph
	rb.add_child(cs)
	if rock_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.position = -rock_mesh.get_aabb().get_center()
		rb.add_child(mi)
	get_tree().current_scene.add_child(rb)
	var b := cam.global_basis
	rb.global_position = cam.global_position - b.z * 0.6 + b.x * 0.12 - b.y * 0.08
	rb.linear_velocity = -b.z * 15.0 + Vector3.UP * 2.0 + player.velocity
	rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	rb.body_entered.connect(_on_rock_hit.bind(rb))
	get_tree().create_timer(8.0, false).timeout.connect(rb.queue_free)


func _on_rock_hit(body: Node, rb: RigidBody3D) -> void:
	if rb.has_meta("hit"):
		return
	rb.set_meta("hit", true)
	var n := -rb.linear_velocity.normalized() if rb.linear_velocity.length() > 0.1 else Vector3.UP
	FX.blunt_impact(_surface(body), rb.global_position, n)


# ---------------------------------------------------------------- aim / motion
func _update_aim(dt: float) -> void:
	var d: Dictionary = cur["def"]
	var can_aim: bool = not bool(d.get("melee", false)) and state in ["idle", "fire", "dry", "show", "inspect"] and not player.sprinting
	var want: bool = (Input.is_action_pressed("aim") or aim_toggle) and can_aim
	if want != aiming:
		aiming = want
		_pose_dirty = true
	# switch between hip / ADS pose as soon as the current shot kick is over
	if _pose_dirty and (state in ["idle", "show", "inspect"] or (state in ["fire", "dry"] and state_t > 0.12)):
		_pose_dirty = false
		_go_idle(0.15)
	ads_f = move_toward(ads_f, 1.0 if aiming else 0.0, dt * 6.0)
	var fov := lerpf(BASE_FOV, float(d.get("ads_fov", BASE_FOV)), ads_f)
	cam.fov = fov
	# Rust IronSights: world FOV += fieldOfViewOffset, viewmodel FOV /= zoomFactor (both zoom together in ADS).
	var vm_fov := BASE_FOV / lerpf(1.0, float(d.get("ads_zoom", 1.0)), ads_f)
	var k := tan(deg_to_rad(fov) * 0.5) / tan(deg_to_rad(vm_fov) * 0.5)
	sway.scale = Vector3(k, k, 1.0)
	var ax: Transform3D = cur.get("ads_xf", Transform3D.IDENTITY)
	ads_node.transform = Transform3D.IDENTITY.interpolate_with(ax, ease(ads_f, -1.8))


func _update_motion(dt: float) -> void:
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := clampf(hv / 3.0, 0.0, 1.0) if player.is_on_floor() else 0.0
	var lowered: bool = player.sprinting and state in ["idle", "show", "deploy"]
	sprint_f = move_toward(sprint_f, 1.0 if lowered else 0.0, dt * 4.0)
	# Rust ViewmodelBob: walk speed 9 / amount 0.005, run 13 / 0.02, leftOffsetRun 0.04
	var freq := lerpf(9.0, 13.0, sprint_f)
	var amp := lerpf(0.006, 0.02, sprint_f) * (1.0 - 0.85 * ads_f)
	if moving > 0.05:
		bob_t += dt * freq
	var bob := Vector3(sin(bob_t) * amp, -absf(cos(bob_t)) * amp, 0.0) * moving
	var ld: Vector2 = player.consume_look_delta()
	var target := Vector2(clampf(ld.x * 0.6, -0.06, 0.06), clampf(ld.y * 0.6, -0.06, 0.06)) * (1.0 - 0.7 * ads_f)
	sway_rot = sway_rot.lerp(target, clampf(dt * 8.0, 0.0, 1.0))
	# pull the weapon back / down when standing right in front of a wall
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 0.85, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pull_t := 0.0
	if not hit.is_empty():
		pull_t = clampf((0.85 - cam.global_position.distance_to(hit["position"])) / 0.5, 0.0, 1.0)
	pull_f = move_toward(pull_f, pull_t, dt * 4.0)
	land_f = move_toward(land_f, 0.0, dt * 3.0)
	sway.position = bob + Vector3(-0.04 * sprint_f, -0.03 * sprint_f - 0.03 * sin(land_f * PI), 0.22 * pull_f)
	sway.rotation = Vector3(sway_rot.y - 0.22 * sprint_f - 0.5 * pull_f, sway_rot.x + 0.12 * sprint_f, 0.08 * sprint_f)
