extends CharacterBody3D
## First-person player: walking/running/jumping, mouse + touch look, footsteps, recoil, camera shake.

const WALK := 3.0
const RUN := 5.6
const ADS_MUL := 0.6
const ACCEL := 11.0
const AIR_ACCEL := 2.0
const JUMP_V := 4.8
const GRAVITY := 12.5
const EYE := 1.55

var head: Node3D
var cam: Camera3D
var wm  # weapon_manager.gd
var hud  # hud.gd (set by main)
var yaw := 0.0
var pitch := 0.0
var joy := Vector2.ZERO          # virtual joystick (x right, y down = backwards)
var touch_sprint := false        # sprint toggle button on touch UI
var sprinting := false
var mouse_sens := 0.0022
var touch_sens := 0.0050
var _look_delta := Vector2.ZERO
var _recoil := Vector2.ZERO
var _shake := 0.0
var _step := 0.0
var _was_floor := true
var _fall := 0.0
var _spawn := Vector3.ZERO
var crouched := false
var collider: CollisionShape3D
var third_person := false
var avatar
var mouse_look_enabled := true
var last_mouse_position := Vector2.ZERO
var has_mouse_position := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	_spawn = global_position
	var cs := CollisionShape3D.new()
	collider = cs
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 75.0
	cam.near = 0.02
	cam.far = 600.0
	cam.current = true
	head.add_child(cam)
	wm = load("res://scripts/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	wm.player = self
	cam.add_child(wm)
	yaw = rotation.y
	avatar = load("res://scripts/avatar.gd").new()
	add_child(avatar)
	avatar.setup(false)
	avatar.rotation.y = PI
	avatar.visible = false
	avatar.animation_player.active = false


func toggle_view() -> void:
	third_person = not third_person
	avatar.visible = third_person
	avatar.animation_player.active = third_person
	wm.visible = not third_person
	wm.aim_toggle = false
	cam.position = Vector3(0, 0, 3.0) if third_person else Vector3.ZERO


func add_look(rel: Vector2, sens: float) -> void:
	yaw -= rel.x * sens
	pitch = clampf(pitch - rel.y * sens, -1.48, 1.48)
	_look_delta += rel * sens


func consume_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	_recoil += Vector2(deg_to_rad(pitch_deg), deg_to_rad(randf_range(-yaw_deg, yaw_deg)))


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_motion(event, OS.has_feature("android"))


func _mouse_motion(event: InputEventMouseMotion, allow_uncaptured: bool) -> void:
	if not mouse_look_enabled or (hud != null and hud.inventory_open):
		has_mouse_position = false
		return
	var was_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Android may reject capture until an actual mouse event is received.
	# Retry on motion, rather than ignoring movement while uncaptured.
	var delta := event.screen_relative if event.screen_relative.length_squared() > 0.0 else event.relative
	if delta.length_squared() == 0.0 and not was_captured and has_mouse_position:
		delta = event.position - last_mouse_position
	last_mouse_position = event.position
	has_mouse_position = true
	if allow_uncaptured and not was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if was_captured or allow_uncaptured:
		add_look(delta, mouse_sens)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not (hud != null and hud.inventory_open):
		mouse_look_enabled = true
		has_mouse_position = false
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_release_mouse"):
		mouse_look_enabled = false
		has_mouse_position = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(dt: float) -> void:
	var take := _recoil * clampf(dt * 20.0, 0.0, 1.0)
	_recoil -= take
	pitch = clampf(pitch + take.x, -1.48, 1.48)
	yaw += take.y
	rotation.y = yaw
	head.rotation.x = pitch
	if third_person and is_inside_tree():
		var from: Vector3 = head.global_position
		var desired: Vector3 = from + head.global_basis.z * 3.0
		var q := PhysicsRayQueryParameters3D.create(from, desired, collision_mask, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var dist := 3.0
		if not hit.is_empty():
			dist = maxf(0.2, from.distance_to(hit.position) - 0.15)
		cam.position.z = dist
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, dt * 4.0)
		var s := _shake * _shake * 0.012
		cam.rotation = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s) * 0.5)
	else:
		cam.rotation = Vector3.ZERO


func _can_stand() -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.95, 0))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("crouch") and not (hud != null and hud.inventory_open):
		if crouched:
			if _can_stand():
				crouched = false
		else:
			crouched = true
	var capsule: CapsuleShape3D = collider.shape
	capsule.height = 1.2 if crouched else 1.8
	collider.position.y = capsule.height * 0.5
	head.position.y = move_toward(head.position.y, 1.0 if crouched else EYE, dt * 4.0)
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + joy
	if hud != null and hud.inventory_open:
		inp = Vector2.ZERO
	if inp.length() > 1.0:
		inp = inp.normalized()
	var want_sprint := Input.is_action_pressed("sprint") or touch_sprint or joy.length() > 0.93
	sprinting = not crouched and want_sprint and inp.y < -0.3 and not bool(wm.blocks_sprint())
	var speed := 1.5 if crouched else (RUN if sprinting else WALK)
	if bool(wm.aiming):
		speed *= ADS_MUL
	var wish := Basis(Vector3.UP, yaw) * Vector3(inp.x, 0.0, inp.y) * speed
	var a := ACCEL if is_on_floor() else AIR_ACCEL
	var t := clampf(a * dt, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x, t)
	velocity.z = lerpf(velocity.z, wish.z, t)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not crouched and not (hud != null and hud.inventory_open):
			velocity.y = JUMP_V
			FX.play2d("footsteps/grass_jump_start_%d.wav" % randi_range(1, 4), -8.0)
	else:
		velocity.y -= GRAVITY * dt
		_fall = maxf(_fall, -velocity.y)
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_floor and _fall > 2.5:
		FX.play2d("footsteps/grass_jump_land_%d.wav" % randi_range(1, 4), -6.0)
		wm.land()
	if on_floor:
		_fall = 0.0
	_was_floor = on_floor
	var hs := Vector2(velocity.x, velocity.z).length()
	if third_person:
		avatar.animate(dt, hs, crouched, on_floor, inp)
	if on_floor and hs > 0.6:
		_step += hs * dt
		var stride := 2.2 if sprinting else 1.6
		if _step >= stride:
			_step = 0.0
			if sprinting:
				FX.play2d("footsteps/grass_run_%d.wav" % randi_range(1, 8), -9.0, 0.06)
			else:
				FX.play2d("footsteps/grass_walk_%d.wav" % randi_range(1, 8), -12.0, 0.06)
	if global_position.y < -30.0:
		global_position = _spawn
		velocity = Vector3.ZERO
