extends CanvasLayer
## Rust-style HUD (belt slots, vitals, crosshair, ammo) + mobile touch controls
## (floating joystick, drag-to-look, fire/aim/reload/inspect/jump/sprint/animation buttons).

const C_SLOT := Color(0.78, 0.78, 0.78, 0.20)
const C_SLOT_SEL := Color(0.25, 0.52, 0.80, 0.78)
const C_COND := Color(0.55, 0.73, 0.24, 0.95)
const C_HEALTH := Color(0.55, 0.71, 0.24, 0.9)
const C_WATER := Color(0.26, 0.55, 0.84, 0.9)
const C_FOOD := Color(0.80, 0.47, 0.17, 0.9)
const SLOT := 66.0
const GAP := 5.0
const JOY_R := 72.0
const FA_HEART := 0xf004
const FA_TINT := 0xf043
const FA_UTENSILS := 0xf2e7
const FA_CROSSHAIRS := 0xf05b
const FA_SYNC := 0xf021
const FA_EYE := 0xf06e
const FA_ARROW_UP := 0xf062
const FA_BULLSEYE := 0xf140
const FA_RUNNING := 0xf70c
const FA_REDO := 0xf01e


class TouchBtn extends Control:
	var action := ""
	var icon := ""
	var caption := ""
	var radius := 40.0
	var toggle := false
	var pressed := false
	var on := false
	var icon_font: Font
	var text_font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(r: float) -> void:
		radius = r
		size = Vector2(r * 2.0, r * 2.0)

	func hit(p: Vector2) -> bool:
		return visible and p.distance_to(global_position + size * 0.5) <= radius * 1.15

	func _draw() -> void:
		var c := size * 0.5
		var active := pressed or on
		draw_circle(c, radius, Color(0.30, 0.56, 0.86, 0.55) if active else Color(0.08, 0.08, 0.08, 0.38))
		draw_arc(c, radius - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45 if active else 0.28), 2.0, true)
		if icon_font and icon != "":
			var fs := int(radius * 0.72)
			var ts := icon_font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var yoff := fs * 0.36 - (radius * 0.12 if caption != "" else 0.0)
			draw_string(icon_font, c + Vector2(-ts.x * 0.5, yoff), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
		if text_font and caption != "":
			var fs2 := int(clampf(radius * 0.3, 10.0, 16.0))
			var ts2 := text_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			draw_string(text_font, c + Vector2(-ts2.x * 0.5, radius * 0.62), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, 0.8))


## Rust-like crosshair: small white dot with a soft dark outline.
class Crosshair extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.2, Color(0, 0, 0, 0.45))
		draw_circle(c, 2.0, Color(1, 1, 1, 0.95))


class JoyPad extends Control:
	var radius := 72.0
	var knob := Vector2.ZERO
	var active := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, radius, Color(0.05, 0.05, 0.05, 0.30 if active else 0.20))
		draw_arc(c, radius - 1.0, 0.0, TAU, 64, Color(1, 1, 1, 0.40 if active else 0.25), 2.5, true)
		draw_circle(c + knob * radius, radius * 0.38, Color(1, 1, 1, 0.50 if active else 0.32))


class InventoryPanel extends Control:
	var hud
	var font: Font
	var icons: Array = []
	var selected := -1
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func slot_rect(i: int) -> Rect2:
		if i < 24: return Rect2(425 + (i % 6) * 100, 158 + int(i / 6) * 89, 90, 80)
		if i < 30: return Rect2(425 + (i - 24) * 100, 565, 90, 80)
		return Rect2(300 + int((i - 30) % 2) * 53, 150 + int((i - 30) / 2) * 67, 48, 60)
	func hit(p: Vector2) -> int:
		for i in range(37):
			if slot_rect(i).has_point(p): return i
		return -1
	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.025, 0.03, 0.025, 0.94))
		var unit := minf(s.x / 1280.0, s.y / 720.0)
		var o := Vector2((s.x - 1280.0 * unit) / 2.0, (s.y - 720.0 * unit) / 2.0)
		draw_set_transform(o, 0.0, Vector2(unit, unit))
		draw_string(font, Vector2(48, 65), "ИНВЕНТАРЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color.WHITE)
		draw_string(font, Vector2(1000, 65), "ЗАКРЫТЬ ✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		draw_rect(Rect2(48, 100, 330, 430), Color(0.16, 0.17, 0.15, 0.75))
		draw_string(font, Vector2(55, 140), "ПЕРСОНАЖ", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
		draw_string(font, Vector2(425, 142), "ПРЕДМЕТЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
		draw_string(font, Vector2(425, 548), "ПОЯС", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
		for i in range(37):
			var r := slot_rect(i)
			draw_rect(r, Color(0.63, 0.62, 0.50, 0.72) if selected == i else Color(0.39,0.4,0.36,0.55))
			var item: Dictionary = hud.inventory.slot_get(i)
			if item.is_empty(): continue
			var tex: Texture2D = hud.item_icon(item)
			if tex: draw_texture_rect(tex, r.grow(-5), false)
			var count: String = hud.item_count(item)
			if count != "": draw_string(font, r.position + Vector2(7, r.size.y - 5), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_string(font, Vector2(48, 685), "Перетащи предмет или нажми сначала на него, затем на нужную ячейку.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8,0.8,0.8))


var player
var wm
var inventory_open := false
var inventory
var inventory_drag := -1
var inventory_pointer := -100
var inventory_panel: InventoryPanel
var portrait: SubViewportContainer
var portrait_view: SubViewport
var portrait_avatar
var touch_mode := false
var touch_switch: TouchBtn
var inventory_had_capture := false
var root: Control
var font_b: Font
var font_r: Font
var font_fa: Font
var crosshair: Control
var slots: Array = []
var vitals: Array = []
var ammo_label: Label
var info_label: Label
var msg_label: Label
var hint_label: Label
var touch_root: Control
var buttons: Array = []
var btn := {}
var joy: JoyPad
var joy_index := -1
var joy_center := Vector2.ZERO
var joy_home := Vector2.ZERO
var look_touches := {}
var btn_touches := {}
var _fps_t := 0.0


func _ready() -> void:
	layer = 5
	font_b = load("res://assets/ui/fonts/robotocondensed-bold.ttf")
	font_r = load("res://assets/ui/fonts/robotocondensed-regular.ttf")
	font_fa = load("res://assets/ui/fonts/fa-solid.ttf")
	root = Control.new()
	root.name = "HUD"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_crosshair()
	_build_belt()
	_build_vitals()
	ammo_label = _label(font_b, 26, Color(1, 1, 1, 0.92))
	info_label = _label(font_r, 15, Color(1, 1, 1, 0.75))
	msg_label = _label(font_b, 20, Color(1, 0.95, 0.85, 0.95))
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _label(font_r, 14, Color(1, 1, 1, 0.6))
	hint_label.text = ""
	_build_touch()
	inventory = load("res://scripts/inventory.gd").new()
	inventory.setup(wm)
	wm.inventory = inventory
	inventory_panel = InventoryPanel.new()
	inventory_panel.hud = self
	inventory_panel.font = font_b
	for path in ["ammo.rifle", "ammo.pistol", "rifle.ak", "pistol.semiauto", "pistol.revolver", "rock", "bandage"]:
		inventory_panel.icons.append(load("res://assets/ui/icons/%s.png" % path))
	inventory_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(inventory_panel)
	inventory_panel.visible = false
	_build_portrait()
	get_viewport().size_changed.connect(_layout)
	set_touch_mode(DisplayServer.is_touchscreen_available())
	_layout()


func _build_portrait() -> void:
	portrait = SubViewportContainer.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.stretch = true
	inventory_panel.add_child(portrait)
	portrait_view = SubViewport.new()
	portrait_view.transparent_bg = true
	portrait_view.own_world_3d = true
	portrait_view.size = Vector2i(260, 360)
	portrait.add_child(portrait_view)
	var scene := Node3D.new()
	portrait_view.add_child(scene)
	portrait_avatar = load("res://scripts/avatar.gd").new()
	scene.add_child(portrait_avatar)
	portrait_avatar.setup(false)
	portrait_avatar._play("preview")
	portrait_avatar.animation_player.active = false
	portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.5
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, 3.3)
	camera.fov = 37
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	camera.current = true


func _label(f: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _tex_rect(path: String, col: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return t


func _build_crosshair() -> void:
	crosshair = Crosshair.new()
	crosshair.size = Vector2(12, 12)
	root.add_child(crosshair)


func _build_belt() -> void:
	var icons := ["res://assets/ui/icons/rifle.ak.png", "res://assets/ui/icons/pistol.semiauto.png",
		"res://assets/ui/icons/pistol.revolver.png", "res://assets/ui/icons/rock.png",
		"res://assets/ui/icons/bandage.png", ""]
	var conds := [0.92, 0.8, 0.86, 1.0, 1.0, 0.0]
	for i in range(6):
		var bg := _tex_rect("res://assets/ui/sprites/ui.rounded.png")
		bg.self_modulate = C_SLOT
		bg.size = Vector2(SLOT, SLOT)
		root.add_child(bg)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(5, 5)
		icon.size = Vector2(SLOT - 10, SLOT - 10)
		bg.add_child(icon)
		var cond := ColorRect.new()
		cond.color = C_COND
		cond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cond.visible = conds[i] > 0.0 and i < 4
		bg.add_child(cond)
		var cnt := Label.new()
		cnt.add_theme_font_override("font", font_b)
		cnt.add_theme_font_size_override("font_size", 15)
		cnt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		cnt.add_theme_constant_override("shadow_offset_x", 1)
		cnt.add_theme_constant_override("shadow_offset_y", 1)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.position = Vector2(0, SLOT - 21)
		cnt.size = Vector2(SLOT - 5, 18)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(cnt)
		if i == 4:
			cnt.text = "x3"
		slots.append({"bg": bg, "icon": icon, "cond": cond, "cnt": cnt, "c": conds[i]})


func _build_vitals() -> void:
	var defs := [[FA_HEART, C_HEALTH, 100.0, 100.0], [FA_TINT, C_WATER, 250.0, 250.0], [FA_UTENSILS, C_FOOD, 412.0, 500.0]]
	for v in defs:
		var bg := ColorRect.new()
		bg.color = Color(0.85, 0.85, 0.85, 0.13)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		var fill := ColorRect.new()
		fill.color = v[1]
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		var ic := Label.new()
		ic.add_theme_font_override("font", font_fa)
		ic.add_theme_font_size_override("font_size", 14)
		ic.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		ic.text = char(v[0])
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(ic)
		var val := Label.new()
		val.add_theme_font_override("font", font_b)
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		val.add_theme_constant_override("shadow_offset_x", 1)
		val.add_theme_constant_override("shadow_offset_y", 1)
		val.text = str(int(v[2]))
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(val)
		vitals.append({"bg": bg, "fill": fill, "icon": ic, "val": val, "f": float(v[2]) / float(v[3])})


func _make_btn(name: String, action: String, icon_code: int, caption: String, r: float, toggle: bool = false) -> TouchBtn:
	var b := TouchBtn.new()
	b.name = name
	b.action = action
	b.icon = char(icon_code)
	b.caption = caption
	b.toggle = toggle
	b.icon_font = font_fa
	b.text_font = font_b
	b.setup(r)
	touch_root.add_child(b)
	buttons.append(b)
	btn[name] = b
	return b


func _build_touch() -> void:
	touch_root = Control.new()
	touch_root.name = "Touch"
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(touch_root)
	joy = JoyPad.new()
	joy.radius = JOY_R
	joy.size = Vector2(JOY_R * 2.0, JOY_R * 2.0)
	touch_root.add_child(joy)
	_make_btn("fire", "fire", FA_CROSSHAIRS, "", 60.0)
	_make_btn("aim", "aim", FA_BULLSEYE, "ПРИЦЕЛ", 40.0, true)
	_make_btn("reload", "reload", FA_SYNC, "R", 34.0)
	_make_btn("inspect", "inspect", FA_EYE, "ОСМОТР", 32.0)
	_make_btn("jump", "jump", FA_ARROW_UP, "", 36.0)
	_make_btn("sprint", "sprint", FA_RUNNING, "", 30.0, true)
	_make_btn("anim", "anim_next", FA_REDO, "АНИМ", 28.0)
	_make_btn("crouch", "crouch", FA_ARROW_UP, "ПРИСЕСТЬ", 32.0)
	_make_btn("inventory", "inventory", FA_EYE, "ИНВЕНТАРЬ", 32.0)
	_make_btn("view", "view_toggle", FA_EYE, "ВИД", 30.0)
	# Independent of touch_root so it remains available to restore controls.
	touch_switch = TouchBtn.new()
	touch_switch.name = "touch_switch"
	touch_switch.icon = char(FA_EYE)
	touch_switch.caption = "КНОПКИ"
	touch_switch.icon_font = font_fa
	touch_switch.text_font = font_b
	touch_switch.setup(27.0)
	root.add_child(touch_switch)


func set_touch_mode(on: bool) -> void:
	_release_all_touches()
	touch_mode = on
	touch_root.visible = on
	touch_switch.visible = on or DisplayServer.is_touchscreen_available() or OS.has_feature("android")
	touch_switch.on = on
	touch_switch.queue_redraw()
	# Physical mouse input must stay available even on touch-capable Android.
	Input.emulate_touch_from_mouse = false
	if player:
		player.touch_sprint = false
	if wm:
		wm.aim_toggle = false
	for name in ["aim", "sprint"]:
		btn[name].on = false
		btn[name].queue_redraw()
	_layout()


func _release_all_touches() -> void:
	for b in buttons:
		if b.pressed and not b.toggle:
			Input.action_release(b.action)
		b.pressed = false
		b.queue_redraw()
	btn_touches.clear()
	look_touches.clear()
	joy_index = -1
	if player:
		player.joy = Vector2.ZERO


func _layout() -> void:
	if root == null:
		return
	var vs := root.get_viewport_rect().size
	crosshair.position = (vs - crosshair.size) * 0.5
	var total := SLOT * 6.0 + GAP * 5.0
	var x0 := (vs.x - total) * 0.5
	var y0 := vs.y - SLOT - 14.0
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		s["bg"].position = Vector2(x0 + i * (SLOT + GAP), y0)
		var c: ColorRect = s["cond"]
		var h := (SLOT - 8.0) * float(s["c"])
		c.position = Vector2(3, SLOT - 4.0 - h)
		c.size = Vector2(4, h)
	ammo_label.position = Vector2(x0 + total + 16.0, y0 + 14.0)
	var vw := 196.0
	var vh := 22.0
	var vx := vs.x - vw - 16.0
	var vy := vs.y - 16.0 - (vh * 3.0 + 8.0)
	if touch_mode:
		vy = 14.0
	for i in range(vitals.size()):
		var v: Dictionary = vitals[i]
		v["bg"].position = Vector2(vx, vy + i * (vh + 4.0))
		v["bg"].size = Vector2(vw, vh)
		v["icon"].position = Vector2(0, 0)
		v["icon"].size = Vector2(vh + 2.0, vh)
		v["fill"].position = Vector2(vh + 4.0, 2.0)
		v["fill"].size = Vector2((vw - vh - 6.0) * float(v["f"]), vh - 4.0)
		v["val"].position = Vector2(vh + 9.0, 0)
		v["val"].size = Vector2(80, vh)
	info_label.position = Vector2(14, 10)
	msg_label.position = Vector2(0, vs.y * 0.22)
	msg_label.size = Vector2(vs.x, 30)
	hint_label.position = Vector2(14, 34)
	hint_label.visible = false
	# touch controls
	joy_home = Vector2(minf(190.0, vs.x * 0.16), vs.y - 190.0)
	if joy_index == -1:
		_set_joy_visual(joy_home, Vector2.ZERO)
	_place("fire", Vector2(vs.x - 130.0, vs.y - 250.0))
	_place("aim", Vector2(vs.x - 255.0, vs.y - 175.0))
	_place("reload", Vector2(vs.x - 70.0, vs.y - 360.0))
	_place("inspect", Vector2(vs.x - 190.0, vs.y - 350.0))
	_place("jump", Vector2(vs.x - 75.0, vs.y - 120.0))
	_place("sprint", Vector2(joy_home.x, joy_home.y - 150.0))
	_place("anim", Vector2(vs.x - 250.0, 130.0))
	_place("crouch", Vector2(vs.x - 180.0, vs.y - 105.0))
	_place("inventory", Vector2(75.0, 75.0))
	_place("view", Vector2(150.0, 75.0))
	touch_switch.position = Vector2(225.0, 75.0) - touch_switch.size * 0.5
	if portrait:
		var u := minf(vs.x / 1280.0, vs.y / 720.0)
		var o := Vector2((vs.x - 1280.0*u)/2.0, (vs.y - 720.0*u)/2.0)
		portrait.position = o + Vector2(55, 150) * u
		portrait.size = Vector2(230, 365) * u


func _place(name: String, center: Vector2) -> void:
	var b: TouchBtn = btn[name]
	b.position = center - b.size * 0.5


func _set_joy_visual(center: Vector2, v: Vector2) -> void:
	joy.position = center - joy.size * 0.5
	joy.knob = v
	joy.active = joy_index != -1
	joy.queue_redraw()


func _slot_at(p: Vector2) -> int:
	for i in range(slots.size()):
		if (slots[i]["bg"] as Control).get_global_rect().has_point(p):
			return i
	return -1


func set_inventory(on: bool) -> void:
	if on == inventory_open: return
	if on:
		inventory_had_capture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if inventory_had_capture else Input.MOUSE_MODE_VISIBLE
	inventory_open = on
	inventory_panel.visible = on
	portrait_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	portrait_avatar.animation_player.active = on
	inventory_pointer = -100
	inventory_drag = -1
	inventory_panel.selected = -1
	if on:
		_release_all_touches()
		if wm:
			wm.aim_toggle = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	inventory_panel.queue_redraw()


func item_icon(item: Dictionary) -> Texture2D:
	if item.is_empty(): return null
	match str(item.get("kind", "")):
		"rifle_ammo": return inventory_panel.icons[0]
		"pistol_ammo": return inventory_panel.icons[1]
		"weapon": return inventory_panel.icons[2 + int(item["weapon"])]
		"bandage": return inventory_panel.icons[6]
	return null


func item_count(item: Dictionary) -> String:
	if item.get("kind", "") == "weapon":
		var w: Dictionary = wm.weapons[int(item["weapon"])]
		return "" if w["def"].get("melee", false) else str(int(w["ammo"]))
	if item.has("count"): return "x%d" % int(item["count"])
	return ""


func _inventory_position(pos: Vector2) -> Vector2:
	var vs := root.get_viewport_rect().size
	var u := minf(vs.x / 1280.0, vs.y / 720.0)
	var o := Vector2((vs.x - 1280.0*u)/2.0, (vs.y - 720.0*u)/2.0)
	return (pos - o) / u


func _inventory_pointer(pos: Vector2, pressed: bool, id: int) -> void:
	var p := _inventory_position(pos)
	if pressed:
		if inventory_pointer != -100: return
		if Rect2(980, 20, 250, 75).has_point(p):
			set_inventory(false)
			return
		var target := inventory_panel.hit(p)
		if target < 0: return
		if inventory_panel.selected >= 0 and target != inventory_panel.selected:
			inventory.move(inventory_panel.selected, target)
			inventory_panel.selected = -1
			return
		inventory_pointer = id
		inventory_drag = target
	else:
		if id != inventory_pointer: return
		var target := inventory_panel.hit(p)
		if target >= 0 and target != inventory_drag:
			inventory.move(inventory_drag, target)
			inventory_panel.selected = -1
		elif target == inventory_drag and not inventory.slot_get(target).is_empty():
			inventory_panel.selected = target
		inventory_pointer = -100
		inventory_drag = -1
	inventory_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("view_toggle") and not inventory_open:
		if player:
			player.toggle_view()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		set_inventory(not inventory_open)
		get_viewport().set_input_as_handled()
		return
	if inventory_open:
		if event is InputEventScreenTouch:
			_inventory_pointer(event.position, event.pressed, event.index)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_inventory_pointer(event.position, event.pressed, -1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_touch"):
		set_touch_mode(not touch_mode)
		get_viewport().set_input_as_handled()
		return
	# Finger can always restore the controls. A visible mouse cursor can use it too.
	if event is InputEventScreenTouch and event.pressed and touch_switch.hit(event.position):
		set_touch_mode(not touch_mode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and touch_switch.hit(event.position):
		Input.action_release("fire")
		set_touch_mode(not touch_mode)
		get_viewport().set_input_as_handled()
		return
	if not touch_mode:
		return
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			for b in buttons:
				if b.hit(event.position):
					if b.name == "view":
						player.toggle_view()
						get_viewport().set_input_as_handled()
						return
					if b.name == "inventory":
						set_inventory(true)
						get_viewport().set_input_as_handled()
						return
					btn_touches[idx] = b
					if b.toggle:
						b.on = not b.on
						_apply_toggle(b)
					else:
						b.pressed = true
						Input.action_press(b.action)
					b.queue_redraw()
					get_viewport().set_input_as_handled()
					return
			var si := _slot_at(event.position)
			if si >= 0:
				if wm:
					wm.select_slot(si)
				get_viewport().set_input_as_handled()
				return
			var vs := root.get_viewport_rect().size
			if event.position.x < vs.x * 0.42 and joy_index == -1:
				joy_index = idx
				joy_center = event.position
				_set_joy_visual(joy_center, Vector2.ZERO)
			else:
				look_touches[idx] = true
			get_viewport().set_input_as_handled()
		else:
			if btn_touches.has(idx):
				var b: TouchBtn = btn_touches[idx]
				if not b.toggle:
					b.pressed = false
					Input.action_release(b.action)
					b.queue_redraw()
				btn_touches.erase(idx)
			elif idx == joy_index:
				joy_index = -1
				if player:
					player.joy = Vector2.ZERO
				_set_joy_visual(joy_home, Vector2.ZERO)
			look_touches.erase(idx)
	elif event is InputEventScreenDrag:
		var idx: int = event.index
		if idx == joy_index:
			var v: Vector2 = (event.position - joy_center) / JOY_R
			if v.length() > 1.0:
				v = v.normalized()
			if player:
				player.joy = v
			_set_joy_visual(joy_center, v)
		elif look_touches.has(idx) or (btn_touches.has(idx) and btn_touches[idx].action == "fire"):
			if player:
				player.add_look(event.relative, player.touch_sens)
		get_viewport().set_input_as_handled()


func _apply_toggle(b: TouchBtn) -> void:
	match b.name:
		"aim":
			if wm:
				wm.aim_toggle = b.on
		"sprint":
			if player:
				player.touch_sprint = b.on


func _process(dt: float) -> void:
	if wm == null:
		return
	if inventory_open:
		inventory_panel.queue_redraw()
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var item: Dictionary = inventory.belt[i]
		slot["bg"].self_modulate = C_SLOT_SEL if i == inventory.selected_belt else C_SLOT
		var icon: TextureRect = slot["icon"]
		icon.texture = item_icon(item)
		slot["cnt"].text = item_count(item)
		slot["cond"].visible = item.get("kind", "") == "weapon"
	ammo_label.text = wm.ammo_text()
	crosshair.visible = not bool(wm.aiming)
	if touch_mode:
		var c: TouchBtn = btn["crouch"]
		if c.on != bool(player.crouched):
			c.on = bool(player.crouched)
			c.queue_redraw()
		var a: TouchBtn = btn["aim"]
		if a.on != bool(wm.aim_toggle):
			a.on = bool(wm.aim_toggle)
			a.queue_redraw()
	_fps_t -= dt
	if _fps_t <= 0.0:
		_fps_t = 0.25
		info_label.text = "%d FPS" % Engine.get_frames_per_second()
	if wm.message_t > 0.0:
		msg_label.text = wm.message
		msg_label.modulate.a = clampf(wm.message_t * 2.0, 0.0, 1.0)
	else:
		msg_label.text = ""
