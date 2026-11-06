extends Node
## Automated smoke test: `godot -- --autotest [--shots=/abs/dir]`. Drives the input actions, prints the
## weapon state machine and (when rendering is available) saves screenshots.

var t := 0.0
var i := 0
var shot_dir := ""
var player
var wm
var hud
var steps: Array = []
var steps_full := [
	[0.3, "info"],
	[1.5, "shot", "01_ak_idle"],
	[1.6, "press", "fire"], [1.7, "shot", "02_ak_fire"], [2.5, "release", "fire"], [2.6, "shot", "03_ak_after_burst"],
	[2.9, "press", "aim"], [3.4, "shot", "04_ak_ads"], [3.45, "tap", "fire"], [3.5, "shot", "05_ak_ads_fire"], [3.9, "release", "aim"],
	[4.2, "tap", "reload"], [6.4, "shot", "06_ak_reload"],
	[9.6, "tap", "inspect"], [11.2, "shot", "07_ak_inspect"],
	[12.0, "tap", "slot_2"], [13.0, "shot", "08_semi_idle"], [13.1, "tap", "fire"], [13.15, "shot", "09_semi_fire"],
	[13.6, "tap", "reload"], [14.3, "shot", "10_semi_reload"],
	[17.0, "tap", "slot_3"], [18.0, "shot", "11_revolver_idle"], [18.1, "tap", "fire"], [18.14, "shot", "12_revolver_fire"],
	[18.8, "tap", "reload"], [20.3, "shot", "13_revolver_reload"],
	[23.5, "tap", "slot_4"], [24.4, "shot", "14_rock_idle"], [24.5, "tap", "fire"], [24.95, "shot", "15_rock_swing"],
	[26.2, "press", "aim"], [27.4, "shot", "16_rock_throw_hold"], [27.5, "tap", "fire"], [27.75, "shot", "17_rock_throw"], [27.8, "release", "aim"],
	[29.5, "tap", "slot_1"], [30.8, "touch_on"], [31.0, "shot", "18_touch_ui"], [31.1, "touch_off"],
	[31.3, "look", -0.55, 0.0], [31.6, "press", "fire"], [31.85, "shot", "19_ground_impacts"], [32.4, "release", "fire"],
	[33.4, "shot", "20_ground_decals"],
	[33.6, "look", -0.05, -0.605], [33.8, "tap", "reload"], [39.0, "press", "fire"], [39.3, "shot", "21_container_impacts"],
	[39.9, "release", "fire"], [40.6, "shot", "22_container_decals"],
	[40.8, "look", 0.0, 0.6], [41.6, "shot", "23_view_left"],
	[41.8, "look", 0.05, 3.14], [42.6, "shot", "24_view_back"],
	[42.8, "anim_cycle"], [44.0, "quit"],
]


# effects close-up scenario (run with --fixed-fps 30 so single frames of muzzle flashes can be captured)
var steps_promo := [
	[0.2, "info"], [0.3, "touch_on"],
	[1.6, "look", -0.08, -0.25], [1.7, "touch_joy", 0.0, -62.0],
	[2.2, "tap", "fire"], [2.234, "shot", "promo1_touch_fire"], [2.4, "touch_joy_release"],
	[2.5, "tap", "inspect"], [3.5, "shot", "promo2_inspect"],
	# ADS alignment check (Rust IronSights eye/target points) for each gun
	[3.6, "touch_off"], [3.6, "look", -0.04, -0.25], [3.7, "press", "aim"], [4.5, "shot", "ads1_ak"],
	[4.55, "tap", "fire"], [4.584, "shot", "ads2_ak_fire"], [4.9, "release", "aim"],
	[5.0, "tap", "slot_2"], [6.2, "press", "aim"], [6.9, "shot", "ads3_semi"], [7.0, "release", "aim"],
	[7.1, "tap", "slot_3"], [8.4, "press", "aim"], [9.1, "shot", "ads4_revolver"], [9.2, "release", "aim"],
	[9.3, "quit"],
]
var steps_fx := [
	[0.2, "info"],
	[2.0, "look", -0.12, 0.0], [2.1, "tap", "fire"], [2.134, "shot", "fx01_ak_flash"], [2.167, "shot", "fx02_ak_flash2"],
	[2.25, "shot", "fx03_ak_smoke_shell"], [2.6, "shot", "fx04_ak_after"],
	[2.8, "look", -0.10, -0.46], [2.9, "tap", "fire"], [2.934, "shot", "fx05_metal_sparks"], [3.0, "shot", "fx06_metal_sparks2"], [3.3, "shot", "fx07_metal_after"],
	[3.5, "look", -0.55, 0.25], [3.6, "tap", "fire"], [3.634, "shot", "fx08_grass_impact"], [3.75, "shot", "fx09_grass_impact2"], [4.2, "shot", "fx10_grass_after"],
	[4.4, "look", -0.05, 0.38], [4.5, "tap", "fire"], [4.534, "shot", "fx11_wood_impact"], [4.7, "shot", "fx12_wood_after"],
	[4.9, "look", -0.12, 0.0], [5.0, "press", "aim"], [5.6, "shot", "fx13_ak_ads"], [5.7, "tap", "fire"], [5.734, "shot", "fx14_ak_ads_flash"], [6.0, "release", "aim"],
	[6.2, "tap", "slot_2"], [7.3, "tap", "fire"], [7.334, "shot", "fx15_semi_flash"], [7.42, "shot", "fx16_semi_shell"],
	[7.8, "tap", "slot_3"], [8.9, "tap", "fire"], [8.934, "shot", "fx17_revolver_flash"],
	[9.3, "tap", "slot_4"], [10.1, "look", -0.75, 0.0], [10.2, "tap", "fire"], [10.76, "shot", "fx18_rock_hit"], [11.0, "shot", "fx19_rock_hit_after"],
	[11.2, "touch_on"], [11.4, "shot", "fx20_touch_ui"],
	[11.5, "quit"],
]


func _ready() -> void:
	# Run before the game nodes so actions pressed here are "just pressed" for them in the same frame.
	process_priority = -1000
	player = get_parent().player
	wm = player.wm
	hud = get_parent().hud
	steps = steps_full
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
		if a == "--scenario=fx":
			steps = steps_fx
		if a == "--scenario=promo":
			steps = steps_promo
	print("[autotest] start, shots=", shot_dir)


func _process(dt: float) -> void:
	t += dt
	while i < steps.size() and t >= float(steps[i][0]):
		_do(steps[i])
		i += 1


## Queue the action like a real input event so `is_action_just_pressed` sees it on the next frame.
## Game code reads actions via Input.is_action_* -> press/release the action state directly.
## (Godot 4.3: Input.parse_input_event(InputEventAction) for one action releases other held actions.)
func _act(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _status() -> String:
	var ap: AnimationPlayer = wm.cur.get("ap")
	return "t=%.2f weapon=%s state=%s anim=%s ap=%s ammo=%s fov=%.1f aim=%s ads=%.2f hit=%s" % [t, wm.weapon_name(), wm.state, wm.anim_label,
		ap.current_animation if ap else "-", wm.ammo_text(), player.cam.fov, wm.aiming, wm.ads_f, wm.last_hit]


func _do(s: Array) -> void:
	var cmd: String = s[1]
	match cmd:
		"info":
			for w in wm.weapons:
				var ap: AnimationPlayer = w["ap"]
				var m: Node3D = w.get("muzzle")
				print("[autotest] ", w["def"]["key"], " anims=", ap.get_animation_list() if ap else [], " muzzle=",
					m.global_position if m else null, " muzzle_parent=", m.get_parent().get_class() if m else "-",
					" ads=", w.get("ads_xf", "-"))
			print("[autotest] ", _status())
		"press":
			_act(s[2], true)
			print("[autotest] press ", s[2], " | ", _status())
		"release":
			_act(s[2], false)
			print("[autotest] release ", s[2], " | ", _status())
		"tap":
			_act(s[2], true)
			get_tree().create_timer(0.07).timeout.connect(_act.bind(s[2], false))
			print("[autotest] tap ", s[2], " | ", _status())
		"look":
			player.pitch = float(s[2])
			player.yaw = float(s[3])
		"touch_on":
			hud.set_touch_mode(true)
		"touch_joy":
			var t0 := InputEventScreenTouch.new()
			t0.index = 5
			t0.pressed = true
			t0.position = hud.joy_home
			Input.parse_input_event(t0)
			var dr := InputEventScreenDrag.new()
			dr.index = 5
			dr.position = hud.joy_home + Vector2(float(s[2]), float(s[3]))
			dr.relative = Vector2(float(s[2]), float(s[3]))
			Input.parse_input_event(dr)
		"touch_joy_release":
			var t1 := InputEventScreenTouch.new()
			t1.index = 5
			t1.pressed = false
			t1.position = hud.joy_home
			Input.parse_input_event(t1)
		"touch_off":
			hud.set_touch_mode(false)
		"anim_cycle":
			for k in range(3):
				_act("anim_next", true)
				await get_tree().process_frame
				await get_tree().process_frame
				_act("anim_next", false)
				await get_tree().process_frame
				print("[autotest] anim_next | ", _status())
		"shot":
			print("[autotest] ", s[2], " | ", _status())
			if shot_dir != "":
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				if img and not img.is_empty():
					img.save_png(shot_dir.path_join(str(s[2]) + ".png"))
		"quit":
			print("[autotest] done | ", _status(), " | fx pools=", FX._pools.size(), " decals=", FX._decals.size())
			get_tree().quit()
