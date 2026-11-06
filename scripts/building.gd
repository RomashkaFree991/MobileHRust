extends Node3D
## Base building: foundations, walls, doorways, windows and floors/ceilings on a 3 m grid, with four
## upgrade tiers (wood -> stone -> metal -> armored). Uses the building plan (place) and the hammer (upgrade).
##
## Grid: cell (ix, iz) has its centre at (ix*3, iz*3). An edge belongs to the cell it leaves to +x ("x" edge)
## or +z ("z" edge). Level 0 stands on foundations, level L >= 1 stands on floors at height 0.4 + 3 L.

const CELL := 3.0
const LVL := 3.0                # height of one storey
const TOP0 := 0.4               # walkable height of the foundation
const SLAB := 0.2
const WALL_H := 2.8             # LVL - SLAB
const REACH := 9.0

const PIECES := ["foundation", "wall", "doorway", "window", "floor"]
const PIECE_NAMES := {"foundation": "ФУНДАМЕНТ", "wall": "СТЕНА", "doorway": "ДВЕРЬ", "window": "ОКНО", "floor": "ПОЛ"}
const TIERS := ["wood", "stone", "metal", "hqm"]
const TIER_NAMES := {"wood": "ДЕРЕВО", "stone": "КАМЕНЬ", "metal": "МЕТАЛЛ", "hqm": "МВК"}
const TIER_COLOR := {"wood": Color(0.62, 0.43, 0.24), "stone": Color(0.6, 0.6, 0.57), "metal": Color(0.52, 0.58, 0.66), "hqm": Color(0.36, 0.4, 0.46)}
const TIER_SURFACE := {"wood": "wood", "stone": "concrete", "metal": "metal", "hqm": "metal"}
const BASE_COST := {"foundation": 200, "wall": 100, "doorway": 100, "window": 100, "floor": 100}
const TIER_MUL := {"wood": 1.0, "stone": 1.5, "metal": 0.5, "hqm": 0.12}
const TIER_HEALTH := {"wood": 250, "stone": 500, "metal": 1000, "hqm": 2000}

var player
var hud
var inventory
var mode := ""              # "", "plan", "hammer"
var piece_i := 0
var tier_i := 0
var demolish := false
var pieces := {}            # key -> {"type","tier","node","ix","iz","edge","level"}
var ghost: Node3D
var ghost_mats := {}
var _valid := false
var _target := {}
var _mat_cache := {}
var _mesh_cache := {}
var status := ""


func _ready() -> void:
	name = "Building"
	ghost = Node3D.new()
	ghost.visible = false
	add_child(ghost)
	for ok in [true, false]:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.2, 0.9, 0.3, 0.42) if ok else Color(0.95, 0.2, 0.15, 0.42)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ghost_mats[ok] = m


# ---------------------------------------------------------------- public API
func set_mode(m: String) -> void:
	mode = m
	ghost.visible = false
	_clear_ghost()
	if hud:
		hud.on_build_mode(m)


func cycle_piece(d: int = 1) -> void:
	piece_i = posmod(piece_i + d, PIECES.size())
	_clear_ghost()


func cycle_tier(d: int = 1) -> void:
	tier_i = posmod(tier_i + d, TIERS.size() + (1 if mode == "hammer" else 0))
	demolish = mode == "hammer" and tier_i == TIERS.size()
	_clear_ghost()


func set_piece(i: int) -> void:
	piece_i = clampi(i, 0, PIECES.size() - 1)
	_clear_ghost()


func set_tier(i: int) -> void:
	tier_i = clampi(i, 0, TIERS.size() + (1 if mode == "hammer" else 0) - 1)
	demolish = mode == "hammer" and tier_i == TIERS.size()
	_clear_ghost()


func tier() -> String:
	return TIERS[mini(tier_i, TIERS.size() - 1)]


func piece() -> String:
	return PIECES[piece_i]


func cost_of(type: String, t: String) -> int:
	return int(ceil(float(BASE_COST[type]) * float(TIER_MUL[t])))


func _clear_ghost() -> void:
	for c in ghost.get_children():
		c.queue_free()
	_ghost_key = ""


var _ghost_key := ""


# ---------------------------------------------------------------- per-frame
func _process(_dt: float) -> void:
	if mode == "" or player == null or hud == null or hud.inventory_open:
		ghost.visible = false
		return
	if Input.is_action_just_pressed("build_piece"):
		cycle_piece()
	if Input.is_action_just_pressed("build_tier"):
		cycle_tier()
	if mode == "plan":
		_update_plan()
		if Input.is_action_just_pressed("fire") and not hud.build_ui_blocks_fire:
			_place()
	else:
		ghost.visible = false
		_update_hammer()
		if Input.is_action_just_pressed("fire") and not hud.build_ui_blocks_fire:
			_hammer()


func _aim() -> Dictionary:
	var cam: Camera3D = player.cam
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * REACH, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))


func _level_surface(l: int) -> float:
	return TOP0 + LVL * float(l)


func _update_plan() -> void:
	_valid = false
	_target = {}
	var hit := _aim()
	if hit.is_empty():
		status = "Наведись на землю или постройку"
		ghost.visible = false
		return
	_target = _compute_target(piece(), hit)
	if _target.is_empty():
		ghost.visible = false
		status = "Нельзя разместить здесь"
		return
	_valid = _target["valid"]
	status = str(_target.get("why", ""))
	var key := "%s:%s" % [piece(), tier()]
	if key != _ghost_key:
		_clear_ghost()
		var mi := MeshInstance3D.new()
		mi.mesh = _piece_mesh(piece(), tier())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(mi)
		_ghost_key = key
	for c in ghost.get_children():
		if c is MeshInstance3D:
			c.material_override = ghost_mats[_valid]
	ghost.global_transform = _target["xf"]
	ghost.visible = true


func _edge_xf(ix: int, iz: int, edge: String, y: float) -> Transform3D:
	if edge == "x":
		return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3((ix + 0.5) * CELL, y, iz * CELL))
	return Transform3D(Basis.IDENTITY, Vector3(ix * CELL, y, (iz + 0.5) * CELL))


func _key(type: String, ix: int, iz: int, edge: String, level: int) -> String:
	match type:
		"foundation": return "f:%d,%d" % [ix, iz]
		"floor": return "c:%d,%d,%d" % [ix, iz, level]
	return "w:%d,%d,%s,%d" % [ix, iz, edge, level]


func _is_wallish(t: String) -> bool:
	return t == "wall" or t == "doorway" or t == "window"


func _has(key: String) -> bool:
	return pieces.has(key)


func _wall_at(ix: int, iz: int, edge: String, level: int) -> bool:
	return _has("w:%d,%d,%s,%d" % [ix, iz, edge, level])


func _compute_target(type: String, hit: Dictionary) -> Dictionary:
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var res := {}
	if type == "foundation":
		var c := _cell_of(p)
		var hv := Vector3(n.x, 0.0, n.z)
		if hv.length() > 0.5:
			c = _cell_of(p + hv.normalized() * (CELL * 0.5))
		var d := Vector2(p.x - c.x * CELL, p.z - c.y * CELL)
		# aimed at the top of an existing foundation: move to the neighbour cell nearest to the aim point
		if _has("f:%d,%d" % [c.x, c.y]):
			if absf(d.x) > absf(d.y):
				c.x += 1 if d.x > 0.0 else -1
			else:
				c.y += 1 if d.y > 0.0 else -1
		res["xf"] = Transform3D(Basis.IDENTITY, Vector3(c.x * CELL, TOP0, c.y * CELL))
		res["ix"] = c.x
		res["iz"] = c.y
		res["edge"] = ""
		res["level"] = 0
		var ok := not _has("f:%d,%d" % [c.x, c.y])
		var why := ""
		if not ok:
			why = "Здесь уже есть фундамент"
		elif p.y > 1.2 and not _has_foundation_near(p):
			ok = false
			why = "Фундамент ставится на землю"
		elif _overlaps_world(Vector3(c.x * CELL, TOP0 - 0.35 + 0.35, c.y * CELL), Vector3(CELL - 0.2, 0.5, CELL - 0.2)):
			ok = false
			why = "Место занято"
		res["valid"] = ok
		res["why"] = why
		return res
	if type == "floor":
		var level := maxi(1, roundi((p.y - TOP0) / LVL))
		var c := _cell_of(p)
		res["ix"] = c.x
		res["iz"] = c.y
		res["edge"] = ""
		res["level"] = level
		res["xf"] = Transform3D(Basis.IDENTITY, Vector3(c.x * CELL, _level_surface(level), c.y * CELL))
		var ok := not _has("c:%d,%d,%d" % [c.x, c.y, level])
		var why := "" if ok else "Здесь уже есть перекрытие"
		if ok:
			ok = _floor_supported(c.x, c.y, level)
			why = "" if ok else "Нужна стена или перекрытие рядом"
		res["valid"] = ok
		res["why"] = why
		return res
	# wall-like pieces: nearest edge of the aimed cell
	var level := maxi(0, floori((p.y - TOP0 + 0.25) / LVL))
	var c := _cell_of(p)
	var best_d := 1e9
	var best := Vector3i(c.x, c.y, 0)
	var cands := [
		[Vector3i(c.x, c.y, 0), "x", absf(p.x - (c.x + 0.5) * CELL)],       # east edge
		[Vector3i(c.x - 1, c.y, 0), "x", absf(p.x - (c.x - 0.5) * CELL)],   # west edge
		[Vector3i(c.x, c.y, 0), "z", absf(p.z - (c.y + 0.5) * CELL)],       # south edge
		[Vector3i(c.x, c.y - 1, 0), "z", absf(p.z - (c.y - 0.5) * CELL)],   # north edge
	]
	var edge := "x"
	for cd in cands:
		if cd[2] < best_d:
			best_d = cd[2]
			best = cd[0]
			edge = cd[1]
	res["ix"] = best.x
	res["iz"] = best.y
	res["edge"] = edge
	res["level"] = level
	res["xf"] = _edge_xf(best.x, best.y, edge, _level_surface(level))
	var occupied := _wall_at(best.x, best.y, edge, level)
	var ok := not occupied
	var why := "" if ok else "Здесь уже есть стена"
	if ok:
		ok = _wall_supported(best.x, best.y, edge, level)
		why = "" if ok else "Нужен фундамент или перекрытие"
	res["valid"] = ok
	res["why"] = why
	return res


func _has_foundation_near(p: Vector3) -> bool:
	var c := _cell_of(p)
	return _has("f:%d,%d" % [c.x, c.y])


func _adjacent_cells(ix: int, iz: int, edge: String) -> Array:
	if edge == "x":
		return [Vector2i(ix, iz), Vector2i(ix + 1, iz)]
	return [Vector2i(ix, iz), Vector2i(ix, iz + 1)]


func _wall_supported(ix: int, iz: int, edge: String, level: int) -> bool:
	for c in _adjacent_cells(ix, iz, edge):
		if level == 0:
			if _has("f:%d,%d" % [c.x, c.y]):
				return true
		elif _has("c:%d,%d,%d" % [c.x, c.y, level]):
			return true
	if level > 0 and _wall_at(ix, iz, edge, level - 1):
		return true
	return false


func _floor_supported(ix: int, iz: int, level: int) -> bool:
	# a wall of the storey below along any edge of the cell, or an existing neighbouring floor
	for e in [["x", ix, iz], ["x", ix - 1, iz], ["z", ix, iz], ["z", ix, iz - 1]]:
		if _wall_at(e[1], e[2], e[0], level - 1):
			return true
	for nb in [Vector2i(ix + 1, iz), Vector2i(ix - 1, iz), Vector2i(ix, iz + 1), Vector2i(ix, iz - 1)]:
		if _has("c:%d,%d,%d" % [nb.x, nb.y, level]):
			return true
	return false


func _overlaps_world(center: Vector3, size: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center + Vector3(0, 0.9, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col = r["collider"]
		if col is Node and col.name == "GroundBody":
			continue
		if col is Node and col.has_meta("piece_key"):
			continue
		return true
	return false


# ---------------------------------------------------------------- placing
func _place() -> void:
	if _target.is_empty() or not _valid:
		hud.show_build_message(status if status != "" else "Нельзя разместить здесь")
		return
	var t := tier()
	var type := piece()
	var cost := cost_of(type, t)
	if inventory.count_of(t) < cost:
		hud.show_build_message("Не хватает: %s (нужно %d)" % [TIER_NAMES[t], cost])
		return
	# do not trap the player inside new geometry
	var xf: Transform3D = _target["xf"]
	if _player_inside(type, xf):
		hud.show_build_message("Ты стоишь на месте постройки")
		return
	inventory.take(t, cost)
	add_piece(type, t, int(_target["ix"]), int(_target["iz"]), str(_target["edge"]), int(_target["level"]), true)
	FX.play3d("impacts/blunt_wood_%d.wav" % randi_range(1, 4), xf.origin, -2.0)
	hud.show_build_message("Построено: %s (%s)" % [PIECE_NAMES[type], TIER_NAMES[t]])


func _player_inside(type: String, xf: Transform3D) -> bool:
	if type == "floor" or type == "foundation":
		var d: Vector3 = player.global_position - xf.origin
		return absf(d.x) < CELL * 0.5 + 0.35 and absf(d.z) < CELL * 0.5 + 0.35 and d.y > -0.1 and d.y < 0.0 and type == "floor"
	var local: Vector3 = xf.affine_inverse() * player.global_position
	return absf(local.x) < CELL * 0.5 and absf(local.z) < 0.55 and local.y > -0.2 and local.y < WALL_H


func add_piece(type: String, t: String, ix: int, iz: int, edge: String, level: int, fx: bool = false) -> Dictionary:
	var key := _key(type, ix, iz, edge, level)
	if pieces.has(key):
		return pieces[key]
	var xf: Transform3D
	if type == "foundation":
		xf = Transform3D(Basis.IDENTITY, Vector3(ix * CELL, TOP0, iz * CELL))
	elif type == "floor":
		xf = Transform3D(Basis.IDENTITY, Vector3(ix * CELL, _level_surface(level), iz * CELL))
	else:
		xf = _edge_xf(ix, iz, edge, _level_surface(level))
	var body := StaticBody3D.new()
	body.name = key.replace(":", "_").replace(",", "_")
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", TIER_SURFACE[t])
	body.set_meta("piece_key", key)
	add_child(body)
	body.global_transform = xf
	var mi := MeshInstance3D.new()
	mi.mesh = _piece_mesh(type, t)
	body.add_child(mi)
	for b in _boxes(type):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		body.add_child(cs)
	var data := {"type": type, "tier": t, "node": body, "mesh": mi, "ix": ix, "iz": iz, "edge": edge, "level": level, "key": key,
		"hp": TIER_HEALTH[t]}
	pieces[key] = data
	if fx:
		_effect(t, xf.origin + Vector3(0, 1.2 if type != "foundation" and type != "floor" else 0.3, 0))
	return data


func _effect(t: String, pos: Vector3) -> void:
	FX.blunt_impact(TIER_SURFACE[t], pos, Vector3.UP)
	if t == "stone" or t == "metal" or t == "hqm":
		FX.bullet_impact(TIER_SURFACE[t], pos + Vector3(0.3, 0.1, 0.0), Vector3.UP)


# ---------------------------------------------------------------- hammer
func _piece_from_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var col = hit["collider"]
	if col is Node and col.has_meta("piece_key"):
		return pieces.get(str(col.get_meta("piece_key")), {})
	return {}


func _update_hammer() -> void:
	var d := _piece_from_hit(_aim())
	if d.is_empty():
		status = "Наведи молоток на постройку"
		return
	if demolish:
		status = "%s — снести" % PIECE_NAMES[d["type"]]
		return
	var want := tier()
	var cur: int = TIERS.find(d["tier"])
	var nxt: int = TIERS.find(want)
	if nxt <= cur:
		status = "%s: уже %s или лучше" % [PIECE_NAMES[d["type"]], TIER_NAMES[d["tier"]]]
	else:
		status = "%s: %s → %s (%d)" % [PIECE_NAMES[d["type"]], TIER_NAMES[d["tier"]], TIER_NAMES[want], cost_of(d["type"], want)]


func _hammer() -> void:
	var d := _piece_from_hit(_aim())
	if d.is_empty():
		hud.show_build_message("Наведи молоток на постройку")
		return
	if demolish:
		_remove(d)
		hud.show_build_message("Снесено: %s" % PIECE_NAMES[d["type"]])
		return
	var want := tier()
	if TIERS.find(want) <= TIERS.find(d["tier"]):
		hud.show_build_message("Улучшение невозможно: уже %s" % TIER_NAMES[d["tier"]])
		return
	var cost := cost_of(d["type"], want)
	if inventory.count_of(want) < cost:
		hud.show_build_message("Не хватает: %s (нужно %d)" % [TIER_NAMES[want], cost])
		return
	inventory.take(want, cost)
	d["tier"] = want
	d["hp"] = TIER_HEALTH[want]
	d["mesh"].mesh = _piece_mesh(d["type"], want)
	d["node"].set_meta("surface", TIER_SURFACE[want])
	var pos: Vector3 = d["node"].global_position + Vector3(0, 1.2 if d["type"] != "foundation" and d["type"] != "floor" else 0.3, 0)
	_effect(want, pos)
	FX.play3d("impacts/blunt_%s_%d.wav" % [TIER_SURFACE[want], randi_range(1, 4)], pos, 0.0)
	hud.show_build_message("%s улучшено до: %s" % [PIECE_NAMES[d["type"]], TIER_NAMES[want]])


func _remove(d: Dictionary) -> void:
	pieces.erase(d["key"])
	d["node"].queue_free()
	# anything that lost its support falls too
	var again := true
	while again:
		again = false
		for k in pieces.keys():
			var p: Dictionary = pieces[k]
			var ok := true
			match p["type"]:
				"foundation": ok = true
				"floor": ok = _floor_supported(p["ix"], p["iz"], p["level"])
				_: ok = _wall_supported(p["ix"], p["iz"], p["edge"], p["level"])
			if not ok:
				pieces.erase(k)
				p["node"].queue_free()
				again = true


# ---------------------------------------------------------------- geometry
func _boxes(type: String) -> Array:
	## [[center, size], ...] in the piece's local frame (origin = walking surface / wall base, along local x).
	var w := CELL + 0.2
	match type:
		"foundation":
			return [[Vector3(0, -0.35, 0), Vector3(CELL, 0.7, CELL)]]
		"floor":
			return [[Vector3(0, -SLAB * 0.5, 0), Vector3(CELL, SLAB, CELL)]]
		"wall":
			return [[Vector3(0, WALL_H * 0.5, 0), Vector3(w, WALL_H, 0.2)]]
		"doorway":
			var ow := 1.2
			var oh := 2.1
			var sw := (w - ow) * 0.5
			return [
				[Vector3(-(ow * 0.5 + sw * 0.5), WALL_H * 0.5, 0), Vector3(sw, WALL_H, 0.2)],
				[Vector3(ow * 0.5 + sw * 0.5, WALL_H * 0.5, 0), Vector3(sw, WALL_H, 0.2)],
				[Vector3(0, oh + (WALL_H - oh) * 0.5, 0), Vector3(ow, WALL_H - oh, 0.2)],
			]
		"window":
			var ow2 := 1.4
			var y0 := 0.95
			var y1 := 1.95
			var sw2 := (w - ow2) * 0.5
			return [
				[Vector3(-(ow2 * 0.5 + sw2 * 0.5), WALL_H * 0.5, 0), Vector3(sw2, WALL_H, 0.2)],
				[Vector3(ow2 * 0.5 + sw2 * 0.5, WALL_H * 0.5, 0), Vector3(sw2, WALL_H, 0.2)],
				[Vector3(0, y0 * 0.5, 0), Vector3(ow2, y0, 0.2)],
				[Vector3(0, y1 + (WALL_H - y1) * 0.5, 0), Vector3(ow2, WALL_H - y1, 0.2)],
			]
	return []


func _piece_mesh(type: String, t: String) -> Mesh:
	var key := type + ":" + t
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in _boxes(type):
		_add_box(st, b[0], b[1])
	var mesh := st.commit()
	mesh.surface_set_material(0, _tier_material(t))
	_mesh_cache[key] = mesh
	return mesh


func _add_box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(0, 1, 0), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3(0, -1, 0), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3(0, 0, 1), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3(0, 0, -1), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
		[Vector3(1, 0, 0), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3(-1, 0, 0), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		# planar UVs in metres, picked per face axis, so the texture scale is the same on every piece
		var uvs := []
		for i in range(1, 5):
			var v: Vector3 = f[i] + c
			var uv: Vector2
			if absf(n.y) > 0.5:
				uv = Vector2(v.x, v.z)
			elif absf(n.z) > 0.5:
				uv = Vector2(v.x, -v.y)
			else:
				uv = Vector2(v.z, -v.y)
			uvs.append(uv * 0.5)
		for tri in [[1, 2, 3], [1, 3, 4]]:
			for k in tri:
				st.set_normal(n)
				st.set_uv(uvs[k - 1])
				st.add_vertex(f[k] + c)


# ---------------------------------------------------------------- procedural textures (tileable)
func _tier_material(t: String) -> Material:
	if _mat_cache.has(t):
		return _mat_cache[t]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _make_texture(t)
	m.roughness = 0.9 if t == "wood" or t == "stone" else 0.55
	m.metallic = 0.0 if t == "wood" or t == "stone" else (0.6 if t == "metal" else 0.8)
	m.metallic_specular = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_mat_cache[t] = m
	return m


func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func _make_texture(t: String) -> Texture2D:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var base: Color = TIER_COLOR[t]
	for y in range(sz):
		for x in range(sz):
			var c := base
			match t:
				"wood":
					var plank := y / 32
					var tone := 0.82 + 0.3 * _hash(plank, 0, 7)
					var grain := 0.5 + 0.5 * sin(float(x) * 0.18 + _hash(plank, 3, 1) * 20.0 + sin(float(y) * 0.35) * 1.6)
					var edge := 0.55 if (y % 32) < 2 else 1.0
					c = base * tone * (0.78 + 0.22 * grain) * edge
				"stone":
					var bh := 32
					var row := y / bh
					var off := (row % 2) * 32
					var bx := (x + off) % 64
					var brick := (x + off) / 64
					var tone2 := 0.82 + 0.28 * _hash(brick, row, 11)
					var mortar := 0.6 if (bx < 2 or (y % bh) < 2) else 1.0
					var noise := 0.9 + 0.1 * _hash(x, y, 5)
					c = base * tone2 * mortar * noise
				"metal":
					var ridge := 0.88 + 0.12 * sin(float(x) / float(sz) * TAU * 8.0)
					var rust := 0.85 + 0.15 * _hash(x / 4, y / 4, 9)
					var seam := 0.55 if (y % 64) < 2 else 1.0
					var rivet := 1.0
					if (x % 32) < 3 and (y % 64) > 6 and (y % 64) < 10:
						rivet = 1.3
					c = base * ridge * rust * seam * rivet
				_:
					var panel := 0.55 if ((x % 64) < 2 or (y % 64) < 2) else 1.0
					var d1 := Vector2((x % 64) - 32, (y % 64) - 32).length()
					var bolt := 1.25 if d1 > 27.0 and d1 < 30.0 else 1.0
					var grit := 0.92 + 0.08 * _hash(x, y, 13)
					c = base * panel * bolt * grit
			c.a = 1.0
			img.set_pixel(x, y, c.clamp())
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
