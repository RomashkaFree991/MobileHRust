extends Node
## Autoload "FX": Rust particle effects (from assets/fx/*.json), sounds, bullet holes, shells.

const FX_DIR := "res://assets/fx/"
const SND := "res://assets/sounds/"
const SKIP_EMITTERS := ["ejection_rifle_cartridge", "ejection_pistolshells"]

const BULLET_FX := {"grass": "impact_bullet_grass", "dirt": "impact_bullet_dirt", "wood": "impact_bullet_wood",
	"metal": "impact_bullet_metal", "concrete": "impact_bullet_concrete"}
const BULLET_SND := {"grass": ["bullet_dirt", 3], "dirt": ["bullet_dirt", 3], "wood": ["bullet_wood", 4],
	"metal": ["bullet_metal", 4], "concrete": ["bullet_concrete", 4]}
const BLUNT_FX := {"grass": "impact_blunt_grass", "dirt": "impact_blunt_dirt", "wood": "impact_blunt_wood",
	"metal": "impact_blunt_metal", "concrete": "impact_blunt_concrete"}
const MAX_DECALS := 48
const MIN_LIFETIME := 0.1
## Rust "VertexLit" particles are lit by the sun; ours are unshaded -> approx. daylight multiplier.
const LIT_MUL := 1.5

# One shader for all Rust particle materials. mode 0 = camera billboard (with rotation),
# mode 1 = stretched billboard (quad Y axis follows particle velocity, head at particle position).
const PARTICLE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, __BLEND__;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform int mode = 0;
uniform float stretch = 1.0;
uniform int h_frames = 1;
uniform int v_frames = 1;
uniform bool anim_loop = false;
uniform float light_mul = 1.0;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 p = MODEL_MATRIX[3].xyz;
	mat4 world;
	if (mode == 1) {
		vec3 axis = MODEL_MATRIX[1].xyz / max(sy, 0.00001);
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - p);
		vec3 side = cross(axis, to_cam);
		if (length(side) < 0.0001) {
			side = INV_VIEW_MATRIX[0].xyz;
		}
		side = normalize(side);
		vec3 nrm = normalize(cross(side, axis));
		world = mat4(vec4(side * sx, 0.0), vec4(axis * sy * stretch, 0.0), vec4(nrm, 0.0), vec4(p, 1.0));
	} else {
		float a = INSTANCE_CUSTOM.x;
		vec3 r = INV_VIEW_MATRIX[0].xyz;
		vec3 u = INV_VIEW_MATRIX[1].xyz;
		vec3 rr = r * cos(a) - u * sin(a);
		vec3 uu = r * sin(a) + u * cos(a);
		world = mat4(vec4(rr * sx, 0.0), vec4(uu * sy, 0.0), vec4(INV_VIEW_MATRIX[2].xyz, 0.0), vec4(p, 1.0));
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float hf = float(h_frames);
	float vf = float(v_frames);
	float total = hf * vf;
	float frame = floor(INSTANCE_CUSTOM.z * total);
	if (anim_loop) {
		frame = mod(frame, total);
	} else {
		frame = clamp(frame, 0.0, total - 1.0);
	}
	UV /= vec2(hf, vf);
	UV += vec2(mod(frame, hf) / hf, floor((frame + 0.5) / hf) / vf);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * light_mul;
	ALPHA = clamp(t.a * COLOR.a, 0.0, 1.0);
}
"""

var _defs := {}
var _pools := {}
var _pool_idx := {}
var _shader_add: Shader
var _shader_mix: Shader
var _mat_cache := {}
var _mesh_cache := {}
var _shell_cache := {}
var _streams := {}
var _p2d: Array = []
var _p2d_i := 0
var _p3d: Array = []
var _p3d_i := 0
var _decals: Array = []
var _decal_i := 0
var _decal_mats := {}
var _white_tex: Texture2D


func _ready() -> void:
	_shader_add = Shader.new()
	_shader_add.code = PARTICLE_SHADER.replace("__BLEND__", "blend_add, fog_disabled")
	_shader_mix = Shader.new()
	_shader_mix.code = PARTICLE_SHADER.replace("__BLEND__", "blend_mix")
	_white_tex = load("res://assets/ui/sprites/ui.circlegradient.png")
	for i in range(16):
		var p := AudioStreamPlayer.new()
		p.max_polyphony = 2
		add_child(p)
		_p2d.append(p)
	for i in range(24):
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_p3d.append(p3)


# ---------------------------------------------------------------- helpers
static func v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Basis whose +Z points along `z` (Rust muzzle/eject effects: +Z = forward).
static func basis_from_z(z: Vector3) -> Basis:
	z = z.normalized()
	var up := Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


## Basis whose +Y points along `n` (Rust impact effects are authored Y-up = surface normal).
static func basis_from_y(n: Vector3) -> Basis:
	n = n.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.98 else Vector3.RIGHT
	var x := n.cross(ref).normalized()
	var z := x.cross(n)
	return Basis(x, n, z)


func _scene_root() -> Node:
	var s := get_tree().current_scene
	return s if s != null else get_tree().root


# ---------------------------------------------------------------- effect definitions
func _def(name: String) -> Dictionary:
	if _defs.has(name):
		return _defs[name]
	var path := FX_DIR + name + ".json"
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt) if txt != "" else null
	if d == null:
		var res = load(path)
		if res is JSON:
			d = res.data
	if not (d is Dictionary):
		push_error("FX: cannot load " + path)
		d = {"emitters": [], "lights": [], "duration": 1.0}
	_defs[name] = d
	return d


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	var mx := 1.0
	for pt in points:
		mx = maxf(mx, float(pt[1]))
	c.max_value = mx
	for pt in points:
		c.add_point(Vector2(clampf(float(pt[0]), 0.0, 1.0), float(pt[1])))
	return c


func _gradient(points: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for pt in points:
		offs.append(clampf(float(pt[0]), 0.0, 1.0))
		cols.append(Color(float(pt[1]), float(pt[2]), float(pt[3]), float(pt[4])))
	g.offsets = offs
	g.colors = cols
	return g


func _mesh_from_glb(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var mesh: Mesh = null
	var scn = load(path)
	if scn is PackedScene:
		var inst: Node = scn.instantiate()
		var best: MeshInstance3D = null
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if best == null or String(mi.name).to_lower().ends_with("lod0"):
				best = mi
		if best:
			mesh = best.mesh
		inst.free()
	_mesh_cache[path] = mesh
	return mesh


func _particle_material(e: Dictionary, h: int, v: int, loop: bool, stretch: float) -> Material:
	var tex_path = e["texture"]
	var add: bool = str(e["blend"]) == "add"
	var mode := 1 if str(e["mode"]) == "stretch" else 0
	var key := "%s|%s|%d|%d|%s|%d|%.3f" % [str(tex_path), add, h, v, loop, mode, stretch]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader_add if add else _shader_mix
	var tex: Texture2D = _white_tex
	if tex_path != null and ResourceLoader.exists(str(tex_path)):
		tex = load(str(tex_path))
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("stretch", stretch)
	m.set_shader_parameter("h_frames", h)
	m.set_shader_parameter("v_frames", v)
	m.set_shader_parameter("anim_loop", loop)
	m.set_shader_parameter("light_mul", 1.0 if add else LIT_MUL)
	_mat_cache[key] = m
	return m


func _build_emitter(e: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = str(e["name"]).strip_edges().replace(" ", "_")
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(1, int(e["amount"]))
	var lt: Array = e["lifetime"]
	var lmax := maxf(0.01, float(lt[1]))
	p.lifetime = lmax
	p.lifetime_randomness = clampf(1.0 - float(lt[0]) / lmax, 0.0, 1.0)
	p.explosiveness = clampf(float(e["explosiveness"]), 0.0, 1.0)
	p.local_coords = bool(e["local"])
	p.position = v3(e["pos"])
	var q: Array = e["rot"]
	p.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
	p.direction = v3(e["direction"])
	p.spread = clampf(float(e["spread"]), 0.0, 180.0)
	var sp: Array = e["speed"]
	# Rust flashes/sparks live 0.02-0.07 s. CPUParticles3D draws a new particle at age 0 first
	# (size curve = 0) and kills it on the next step, so at 30 FPS it would never be seen.
	# -> min. lifetime 0.1 s (same travel distance) + preprocess: visible in the very frame of the shot.
	var k := 1.0
	if lmax < MIN_LIFETIME:
		k = MIN_LIFETIME / lmax
		p.lifetime = MIN_LIFETIME
		p.preprocess = 0.001
	p.initial_velocity_min = float(sp[0]) / k
	p.initial_velocity_max = float(sp[1]) / k
	p.gravity = Vector3(0.0, -9.81 * float(e["gravity"]), 0.0) + v3(e["force"])
	var avg_speed := 0.5 * (float(sp[0]) + float(sp[1]))
	var drag := float(e["drag"])
	if drag > 0.0:
		p.damping_min = drag * avg_speed * 0.6
		p.damping_max = drag * avg_speed * 0.9
	var sh: Dictionary = e["shape"]
	match str(sh.get("type", "point")):
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = maxf(0.0005, float(sh.get("radius", 0.01)))
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = v3(sh.get("extents", [0, 0, 0]))
		_:
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	var sz: Array = e["size"]
	p.scale_amount_min = float(sz[0])
	p.scale_amount_max = float(sz[1])
	var sc = e["size_curve"]
	if sc is Array and sc.size() > 0:
		p.scale_amount_curve = _curve(sc)
	var ang: Array = e["angle"]
	p.angle_min = float(ang[0])
	p.angle_max = float(ang[1])
	var av: Array = e["angular_velocity"]
	p.angular_velocity_min = float(av[0])
	p.angular_velocity_max = float(av[1])
	var c0: Array = e["color_min"]
	var c1: Array = e["color_max"]
	var g0 := Gradient.new()
	g0.set_color(0, Color(float(c0[0]), float(c0[1]), float(c0[2]), float(c0[3])))
	g0.set_color(1, Color(float(c1[0]), float(c1[1]), float(c1[2]), float(c1[3])))
	p.color_initial_ramp = g0
	var cr = e["color_ramp"]
	if cr is Array and cr.size() > 0:
		p.color_ramp = _gradient(cr)
	var tiles: Array = e["tiles"]
	var h := maxi(1, int(tiles[0]))
	var v := maxi(1, int(tiles[1]))
	var loop := false
	match str(e["anim"]):
		"over_life":
			p.anim_speed_min = 1.0
			p.anim_speed_max = 1.0
		"over_life_random_start":
			p.anim_speed_min = 1.0
			p.anim_speed_max = 1.0
			p.anim_offset_min = 0.0
			p.anim_offset_max = 1.0
			loop = true
		"random_frame":
			p.anim_speed_min = 0.0
			p.anim_speed_max = 0.0
			p.anim_offset_min = 0.0
			p.anim_offset_max = 0.999
	var mode := str(e["mode"])
	if mode == "mesh":
		var mesh := _mesh_from_glb(str(e["mesh"]))
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		if e["texture"] != null and ResourceLoader.exists(str(e["texture"])):
			mat.albedo_texture = load(str(e["texture"]))
		p.mesh = mesh
		p.material_override = mat
		p.particle_flag_rotate_y = true
		p.scale_amount_min = clampf(float(sz[0]), 0.3, 3.0)
		p.scale_amount_max = clampf(float(sz[1]), 0.3, 3.0)
	else:
		var qm := QuadMesh.new()
		var aspect := maxf(0.05, float(e["aspect"]))
		var stretch := 1.0
		if mode == "stretch":
			var size_avg := maxf(0.001, 0.5 * (float(sz[0]) + float(sz[1])))
			stretch = maxf(0.2, float(e["length_scale"]) + float(e["velocity_scale"]) * avg_speed / size_avg)
			qm.size = Vector2(1.0, aspect)
			qm.center_offset = Vector3(0.0, -0.5 * aspect, 0.0)
			p.particle_flag_align_y = true
		else:
			qm.size = Vector2(1.0, aspect)
		qm.material = _particle_material(e, h, v, loop, stretch)
		p.mesh = qm
	return p


func _make_effect(name: String) -> Node3D:
	var d := _def(name)
	var root := Node3D.new()
	root.name = "fx_" + name
	var parts: Array = []
	for e in d.get("emitters", []):
		if str(e["name"]) in SKIP_EMITTERS:
			continue
		if str(e["mode"]) == "mesh" and e["mesh"] == null:
			continue
		var p := _build_emitter(e)
		root.add_child(p)
		parts.append([p, float(e["delay"])])
	var lights: Array = []
	for l in d.get("lights", []):
		var o := OmniLight3D.new()
		o.position = v3(l["pos"]) * 0.5
		var lc: Array = l["color"]
		o.light_color = Color(float(lc[0]), float(lc[1]), float(lc[2]))
		o.omni_range = float(l["range"])
		o.light_energy = 0.0
		o.shadow_enabled = false
		o.visible = false
		root.add_child(o)
		lights.append([o, float(l.get("intensity", 1.0))])
	root.set_meta("parts", parts)
	root.set_meta("lights", lights)
	return root


func _play(fx: Node3D) -> void:
	for pd in fx.get_meta("parts"):
		var p: CPUParticles3D = pd[0]
		var delay: float = pd[1]
		if delay > 0.001:
			p.emitting = false
			get_tree().create_timer(delay, false).timeout.connect(p.restart)
		else:
			p.restart()
	for ld in fx.get_meta("lights"):
		var o: OmniLight3D = ld[0]
		if o.has_meta("tw"):
			var old = o.get_meta("tw")
			if old is Tween and old.is_valid():
				old.kill()
		o.visible = true
		o.light_energy = 3.0 * float(ld[1])
		var tw := create_tween()
		tw.tween_property(o, "light_energy", 0.0, 0.07)
		tw.tween_callback(o.hide)
		o.set_meta("tw", tw)


## Spawns (pooled) effect `name` with global transform `xf`. `parent` keeps local-space emitters attached.
func spawn(name: String, xf: Transform3D, parent: Node = null, pool_size: int = 4) -> Node3D:
	if not _pools.has(name):
		_pools[name] = []
		_pool_idx[name] = 0
	var pool: Array = _pools[name]
	var fx: Node3D
	if pool.size() < pool_size:
		fx = _make_effect(name)
		pool.append(fx)
	else:
		var i: int = _pool_idx[name] % pool.size()
		fx = pool[i]
		_pool_idx[name] = i + 1
	var want: Node = parent if parent != null else _scene_root()
	if fx.get_parent() != want:
		if fx.get_parent() != null:
			fx.get_parent().remove_child(fx)
		want.add_child(fx)
	fx.global_transform = xf
	_play(fx)
	return fx


## Builds every effect once (hidden under the ground in front of the camera) so shaders compile early.
func prewarm(at: Transform3D) -> void:
	for f in DirAccess.get_files_at(FX_DIR):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".json"):
			spawn(n.get_basename(), at, null, 1)


# ---------------------------------------------------------------- sounds
func stream(path: String) -> AudioStream:
	if not path.begins_with("res://"):
		path = SND + path
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
		if _streams[path] == null:
			push_warning("FX: missing sound " + path)
	return _streams[path]


func play2d(path: String, vol_db: float = 0.0, pitch_var: float = 0.04) -> void:
	var s := stream(path)
	if s == null:
		return
	var pl: AudioStreamPlayer = _p2d[_p2d_i]
	_p2d_i = (_p2d_i + 1) % _p2d.size()
	pl.stream = s
	pl.volume_db = vol_db
	pl.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	pl.play()


func play3d(path: String, pos: Vector3, vol_db: float = 0.0, pitch_var: float = 0.06, max_dist: float = 90.0) -> void:
	var s := stream(path)
	if s == null:
		return
	var pl: AudioStreamPlayer3D = _p3d[_p3d_i]
	_p3d_i = (_p3d_i + 1) % _p3d.size()
	pl.stream = s
	pl.volume_db = vol_db
	pl.max_distance = max_dist
	pl.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	pl.global_position = pos
	pl.play()


# ---------------------------------------------------------------- impacts
func bullet_impact(surface: String, pos: Vector3, normal: Vector3) -> void:
	var s := surface if BULLET_FX.has(surface) else "concrete"
	spawn(BULLET_FX[s], Transform3D(basis_from_y(normal), pos), null, 6)
	var sd: Array = BULLET_SND[s]
	play3d("impacts/%s_%d.wav" % [sd[0], randi_range(1, int(sd[1]))], pos, -3.0)
	if s == "metal" and randf() < 0.35:
		play3d("impacts/bullet_ricochet_%d.wav" % randi_range(1, 4), pos, -6.0)
	add_decal(s, pos, normal, randf_range(0.09, 0.13))


func blunt_impact(surface: String, pos: Vector3, normal: Vector3) -> void:
	var s := surface if BLUNT_FX.has(surface) else "concrete"
	spawn(BLUNT_FX[s], Transform3D(basis_from_y(normal), pos), null, 3)
	play3d("impacts/blunt_%s_%d.wav" % [s, randi_range(1, 4)], pos, 0.0)


# ---------------------------------------------------------------- bullet holes (lit quads: cheap on mobile)
func _decal_mat(surface: String) -> Material:
	if _decal_mats.has(surface):
		return _decal_mats[surface]
	var m: StandardMaterial3D = null
	var a := "res://assets/decals/bullet_%s_albedo.png" % surface
	if ResourceLoader.exists(a):
		m = StandardMaterial3D.new()
		m.albedo_texture = load(a)
		var n := "res://assets/decals/bullet_%s_normal.png" % surface
		if ResourceLoader.exists(n):
			m.normal_enabled = true
			m.normal_texture = load(n)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.render_priority = -1
	_decal_mats[surface] = m
	return m


func add_decal(surface: String, pos: Vector3, normal: Vector3, size: float = 0.11) -> void:
	var mat := _decal_mat(surface)
	if mat == null:
		return
	var mi: MeshInstance3D
	if _decals.size() < MAX_DECALS:
		mi = MeshInstance3D.new()
		var qm := QuadMesh.new()
		mi.mesh = qm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_scene_root().add_child(mi)
		_decals.append(mi)
	else:
		mi = _decals[_decal_i]
		_decal_i = (_decal_i + 1) % MAX_DECALS
	mi.material_override = mat
	var b := basis_from_z(normal)
	var a := randf() * TAU
	var x := b.x * cos(a) + b.y * sin(a)
	var y := b.z.cross(x)
	mi.global_transform = Transform3D(Basis(x * size, y * size, b.z), pos + b.z * 0.006)
	mi.visible = true


# ---------------------------------------------------------------- shells
func _shell_info(kind: String) -> Array:
	if _shell_cache.has(kind):
		return _shell_cache[kind]
	var info: Array = []
	var scn = load("res://assets/fx/meshes/shell_%s.glb" % kind)
	if scn is PackedScene:
		var inst: Node = scn.instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).to_lower().ends_with("lod0"):
				var xf: Transform3D = mi.transform
				var aabb: AABB = xf * mi.mesh.get_aabb()
				info = [mi.mesh, xf.translated(-aabb.get_center()), aabb.size]
				break
		inst.free()
	_shell_cache[kind] = info
	return info


func spawn_shell(kind: String, pos: Vector3, vel: Vector3) -> void:
	var info := _shell_info(kind)
	if info.is_empty():
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1
	rb.mass = 0.02
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var bsz: Vector3 = info[2]
	bs.size = Vector3(maxf(bsz.x, 0.008), maxf(bsz.y, 0.008), maxf(bsz.z, 0.008))
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = info[0]
	mi.transform = info[1]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	_scene_root().add_child(rb)
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-25, 25), randf_range(-25, 25), randf_range(-25, 25))
	rb.body_entered.connect(_on_shell_hit.bind(rb))
	get_tree().create_timer(4.0, false).timeout.connect(rb.queue_free)


func _on_shell_hit(_body: Node, rb: RigidBody3D) -> void:
	if rb.has_meta("hit"):
		return
	rb.set_meta("hit", true)
	play3d("shells/shell_drop_%d.wav" % randi_range(1, 3), rb.global_position, -8.0, 0.12, 25.0)
