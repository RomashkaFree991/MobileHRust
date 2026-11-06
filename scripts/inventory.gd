extends RefCounted
## Shared inventory for the demo. Slots hold item dictionaries; empty slot is {}.
var grid: Array = []
var belt: Array = []
var wear: Array = []
var selected_belt := 0
var wm

func setup(manager) -> void:
	wm = manager
	grid.resize(24)
	belt.resize(6)
	wear.resize(7)
	for i in range(grid.size()): grid[i] = {}
	for i in range(belt.size()): belt[i] = {}
	for i in range(wear.size()): wear[i] = {}
	for i in range(4): belt[i] = {"kind": "weapon", "weapon": i}
	belt[4] = {"kind": "bandage", "count": 3}
	grid[0] = {"kind": "rifle_ammo", "count": 120}
	grid[1] = {"kind": "pistol_ammo", "count": 108}

func slot_get(index: int) -> Dictionary:
	if index >= 0 and index < 24: return grid[index]
	if index >= 24 and index < 30: return belt[index - 24]
	if index >= 30 and index < 37: return wear[index - 30]
	return {}

func _slot_set(index: int, item: Dictionary) -> void:
	if index >= 0 and index < 24: grid[index] = item
	elif index >= 24 and index < 30: belt[index - 24] = item
	elif index >= 30 and index < 37: wear[index - 30] = item

func move(src: int, dst: int) -> bool:
	if src < 0 or dst < 0 or src == dst: return false
	var a := slot_get(src)
	var b := slot_get(dst)
	if a.is_empty(): return false
	# This demo does not contain wearable items. Never place incompatible items in clothing slots.
	if dst >= 30 and a.get("kind", "") != "wearable": return false
	if src >= 30 and not b.is_empty() and b.get("kind", "") != "wearable": return false
	if a.get("kind", "") in ["rifle_ammo", "pistol_ammo", "bandage"] and a.get("kind") == b.get("kind"):
		var max_stack := 3 if a["kind"] == "bandage" else 128
		var n := mini(int(a["count"]), max_stack - int(b["count"]))
		if n > 0:
			b["count"] = int(b["count"]) + n
			a["count"] = int(a["count"]) - n
			if int(a["count"]) == 0: _slot_set(src, {})
	else:
		_slot_set(src, b)
		_slot_set(dst, a)
	if src == 24 + selected_belt or dst == 24 + selected_belt:
		select(selected_belt)
	return true

func select(index: int) -> void:
	if index < 0 or index >= belt.size(): return
	selected_belt = index
	var item: Dictionary = belt[index]
	if item.get("kind", "") == "weapon":
		wm.switch_to(int(item["weapon"]))
	else:
		wm.unequip()
		if item.get("kind", "") == "bandage": wm.show_message("Бинт: лечение пока не реализовано")

func reserve_for(weapon_index: int) -> int:
	var kind := "rifle_ammo" if weapon_index == 0 else "pistol_ammo"
	if weapon_index < 0 or weapon_index > 2: return 0
	var total := 0
	for item in grid + belt:
		if item.get("kind", "") == kind: total += int(item.get("count", 0))
	return total

func consume_for(weapon_index: int, amount: int) -> int:
	var kind := "rifle_ammo" if weapon_index == 0 else "pistol_ammo"
	if weapon_index < 0 or weapon_index > 2: return 0
	var remaining := amount
	for index in range(30):
		var item := slot_get(index)
		if item.get("kind", "") != kind: continue
		var take := mini(remaining, int(item["count"]))
		item["count"] = int(item["count"]) - take
		remaining -= take
		if int(item["count"]) <= 0: _slot_set(index, {})
		if remaining == 0: break
	return amount - remaining
