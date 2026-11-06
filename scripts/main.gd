extends Node3D
## Builds the demo level at runtime: sky/sun/fog, grass field (Rust texture + grass blades), Rust props
## with colliders, ambience, player with weapons and the HUD.

const PROPS := [
	# model, position, yaw (deg), surface for impacts
	["shipping_container", Vector3(9.0, 0.0, -11.0), 18.0, "metal"],
	["shipping_container", Vector3(-13.0, 0.0, -17.0), -62.0, "metal"],
	["fuel_tank", Vector3(-9.5, 0.0, -5.0), 84.0, "metal"],
	["hesco_barrier", Vector3(-2.2, 0.0, -21.0), 0.0, "dirt"],
	["hesco_barrier", Vector3(0.0, 0.0, -21.0), 0.0, "dirt"],
	["hesco_barrier", Vector3(2.2, 0.0, -21.0), 0.0, "dirt"],
	["hesco_barrier", Vector3(4.25, 0.0, -20.4), -25.0, "dirt"],
	["metal_crate_b", Vector3(4.2, 0.0, -6.5), 8.0, "metal"],
	["metal_crate_e", Vector3(4.2, 0.75, -6.5), -4.0, "metal"],
	["metal_crate_e", Vector3(5.9, 0.0, -7.3), 31.0, "metal"],
	["wood_box_large", Vector3(-3.2, 0.0, -6.0), 12.0, "wood"],
	["wood_box_large", Vector3(-3.1, 0.79, -6.05), -7.0, "wood"],
	["cardboard_boxes", Vector3(-5.8, 0.14, -9.5), 40.0, "wood"],
	["road_cone", Vector3(1.2, 0.0, -4.5), 0.0, "concrete"],
	["road_cone", Vector3(2.4, 0.0, -4.8), 15.0, "concrete"],
	["road_cone", Vector3(3.6, 0.0, -5.0), 40.0, "concrete"],
	["road_cone", Vector3(-1.0, 0.0, -14.0), 0.0, "concrete"],
]
const LOD_RANGES := [0.0, 30.0, 60.0, 100.0, 160.0, 0.0]
const STINGS := ["ambience/sting_1.wav", "ambience/sting_2.wav", "ambience/sting_3.ogg", "ambience/sting_4.ogg", "ambience/sting_5.ogg"]

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float tile = 0.22;
uniform vec3 tint_a : source_color = vec3(0.90, 0.97, 0.78);
uniform vec3 tint_b : source_color = vec3(0.72, 0.74, 0.55);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	vec3 c1 = texture(albedo_tex, uv).rgb;
	vec3 c2 = texture(albedo_tex, uv * 0.29 + vec2(0.37, 0.71)).rgb;
	float n = texture(noise_tex, wpos.xz * 0.011).r;
	vec3 col = mix(c1, c2, 0.35) * mix(tint_b, tint_a, smoothstep(0.25, 0.75, n));
	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.9;
	ROUGHNESS = 0.93;
	SPECULAR = 0.25;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind = 0.07;
uniform float fade_end = 38.0;

void vertex() {
	float h = 1.0 - UV.y;
	float s = sin(TIME * 1.6 + VERTEX.x * 0.45 + VERTEX.z * 0.3) + 0.4 * sin(TIME * 3.1 + VERTEX.x * 1.3 + VERTEX.z * 0.7);
	VERTEX.x += s * wind * h * h;
	VERTEX.z += s * wind * 0.6 * h * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * mix(0.55, 1.0, 1.0 - UV.y);
	float d = length(VERTEX);
	ALPHA = t.a * clamp((fade_end - d) / 8.0, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	// double-sided quads: keep the "up" normal on back faces too (otherwise they render almost black)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
"""

var player
var hud
var sun: DirectionalLight3D
var amb: AudioStreamPlayer
var sting_t := 6.0


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	randomize()
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.85
	_build_environment()
	_build_ground()
	var rects := _build_props()
	_build_grass(rects)
	_spawn_player()
	_build_audio()
	# compile particle shaders early (effects are spawned under the ground in front of the camera)
	FX.prewarm.call_deferred(Transform3D(Basis(), Vector3(0.0, -2.0, -3.0)))
	if "--autotest" in OS.get_cmdline_user_args():
		var t = load("res://scripts/autotest.gd").new()
		t.name = "AutoTest"
		add_child(t)


# ---------------------------------------------------------------- input map
func _key(k) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func _mb(b) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


func _add_action(name: String, evs: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for e in evs:
		InputMap.action_add_event(name, e)
		# Some Android keyboards report logical keycodes without a physical code.
		if e is InputEventKey and e.physical_keycode != KEY_NONE:
			var logical := InputEventKey.new()
			logical.keycode = e.physical_keycode
			InputMap.action_add_event(name, logical)


func _setup_input() -> void:
	_add_action("move_forward", [_key(KEY_W), _key(KEY_UP)])
	_add_action("move_back", [_key(KEY_S), _key(KEY_DOWN)])
	_add_action("move_left", [_key(KEY_A), _key(KEY_LEFT)])
	_add_action("move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_add_action("jump", [_key(KEY_SPACE)])
	_add_action("crouch", [_key(KEY_CTRL)])
	_add_action("inventory", [_key(KEY_TAB)])
	_add_action("view_toggle", [_key(KEY_V)])
	_add_action("sprint", [_key(KEY_SHIFT)])
	_add_action("fire", [_mb(MOUSE_BUTTON_LEFT)])
	_add_action("aim", [_mb(MOUSE_BUTTON_RIGHT), _key(KEY_Q)])
	_add_action("reload", [_key(KEY_R)])
	_add_action("inspect", [_key(KEY_F)])
	_add_action("anim_next", [_key(KEY_N)])
	_add_action("weapon_next", [_mb(MOUSE_BUTTON_WHEEL_DOWN)])
	_add_action("weapon_prev", [_mb(MOUSE_BUTTON_WHEEL_UP)])
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
	for i in range(6):
		_add_action("slot_%d" % (i + 1), [_key(keys[i])])
	_add_action("toggle_touch", [_key(KEY_T)])
	_add_action("build_piece", [_key(KEY_E)])
	_add_action("build_tier", [_key(KEY_G)])
	_add_action("ui_release_mouse", [_key(KEY_ESCAPE)])


# ---------------------------------------------------------------- world
func _build_environment() -> void:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.29, 0.45, 0.68)
	sm.sky_horizon_color = Color(0.68, 0.73, 0.79)
	sm.ground_horizon_color = Color(0.62, 0.66, 0.69)
	sm.ground_bottom_color = Color(0.22, 0.20, 0.17)
	sm.sun_angle_max = 25.0
	sm.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = not OS.has_feature("mobile")
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.67, 0.72, 0.78)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-47.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if OS.has_feature("mobile") else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0 if OS.has_feature("mobile") else 45.0
	sun.shadow_blur = 1.0
	add_child(sun)


func _build_ground() -> void:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	mat.shader = sh
	mat.set_shader_parameter("albedo_tex", load("res://assets/env/ground_albedo.jpg"))
	mat.set_shader_parameter("normal_tex", load("res://assets/env/ground_normal.png"))
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.02
	nt.noise = fnl
	mat.set_shader_parameter("noise_tex", nt)
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	pm.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.set_meta("surface", "grass")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	cs.shape = box
	cs.position.y = -1.0
	body.add_child(cs)
	add_child(body)


func _build_props() -> Array:
	var rects: Array = []
	for p in PROPS:
		var scn = load("res://assets/props/%s.glb" % p[0])
		if not (scn is PackedScene):
			push_warning("missing prop " + str(p[0]))
			continue
		var inst: Node3D = scn.instantiate()
		add_child(inst)
		inst.position = p[1]
		inst.rotation_degrees.y = p[2]
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		var n_lods := 0
		for mi in mis:
			if String(mi.name).to_lower().rfind("_lod") >= 0:
				n_lods += 1
		for mi in mis:
			var nm := String(mi.name).to_lower()
			var k := nm.rfind("_lod")
			var lod := nm.substr(k + 4).to_int() if k >= 0 else 0
			if n_lods > 1:
				mi.visibility_range_begin = LOD_RANGES[lod]
				mi.visibility_range_end = LOD_RANGES[lod + 1] if lod < n_lods - 1 else 0.0
			if lod == 0:
				mi.create_trimesh_collision()
				for c in mi.get_children():
					if c is StaticBody3D:
						c.set_meta("surface", p[3])
				var ab: AABB = mi.global_transform * mi.get_aabb()
				rects.append(Rect2(ab.position.x - 0.3, ab.position.z - 0.3, ab.size.x + 0.6, ab.size.z + 0.6))
	return rects


func _grass_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var w := 0.32
	var h := 0.5
	var quads := 2 if OS.has_feature("mobile") else 3
	for q in range(quads):
		var a := q * PI / float(quads)
		var dx := cos(a) * w
		var dz := sin(a) * w
		var b := verts.size()
		verts.append(Vector3(-dx, 0.0, -dz))
		verts.append(Vector3(dx, 0.0, dz))
		verts.append(Vector3(dx, h, dz))
		verts.append(Vector3(-dx, h, -dz))
		uvs.append(Vector2(0, 1))
		uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0, 0))
		for k in [0, 1, 2, 0, 2, 3]:
			idx.append(b + k)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_grass(rects: Array) -> void:
	var mesh := _grass_mesh()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	mat.shader = sh
	mat.set_shader_parameter("tex", load("res://assets/env/grass_blades.png"))
	mat.set_shader_parameter("fade_end", 36.0 if OS.has_feature("mobile") else 38.0)
	mesh.surface_set_material(0, mat)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var chunk := 10.0
	var half := 4  # 8x8 chunks = 80 x 80 m
	var per_chunk := 80 if OS.has_feature("mobile") else 140
	for cx in range(-half, half):
		for cz in range(-half, half):
			var xforms: Array = []
			var center := Vector3((cx + 0.5) * chunk, 0.0, (cz + 0.5) * chunk)
			var cols: Array = []
			for i in range(per_chunk):
				var x := (cx + rng.randf()) * chunk
				var z := (cz + rng.randf()) * chunk
				var blocked := false
				for r in rects:
					if (r as Rect2).has_point(Vector2(x, z)):
						blocked = true
						break
				if blocked:
					continue
				var s := rng.randf_range(0.7, 1.35)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
				xforms.append(Transform3D(b, Vector3(x, 0.0, z) - center))
				var g := rng.randf()
				cols.append(Color(0.50 + 0.12 * g, 0.62 + 0.10 * g, 0.26 + 0.06 * g))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in range(xforms.size()):
				mm.set_instance_transform(i, xforms[i])
				mm.set_instance_color(i, cols[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 36.0 if OS.has_feature("mobile") else 46.0
			add_child(mmi)


func _spawn_player() -> void:
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0.0, 0.05, 2.0)
	hud = load("res://scripts/hud.gd").new()
	hud.name = "HUDLayer"
	hud.player = player
	hud.wm = player.wm
	player.hud = hud
	add_child(hud)
	var building = load("res://scripts/building.gd").new()
	building.player = player
	building.hud = hud
	building.inventory = hud.inventory
	hud.build = building
	hud.inventory.build = building
	add_child(building)


func _build_audio() -> void:
	amb = AudioStreamPlayer.new()
	var s = load("res://assets/sounds/ambience/field_breeze.ogg")
	if s is AudioStreamOggVorbis:
		s.loop = true
	amb.stream = s
	amb.volume_db = -10.0
	add_child(amb)
	amb.play()


func _process(dt: float) -> void:
	sting_t -= dt
	if sting_t <= 0.0 and player:
		sting_t = randf_range(8.0, 18.0)
		var a := randf() * TAU
		var p: Vector3 = player.global_position + Vector3(cos(a), 0.4, sin(a)) * randf_range(15.0, 35.0)
		FX.play3d(STINGS[randi() % STINGS.size()], p, -6.0, 0.05, 150.0)
