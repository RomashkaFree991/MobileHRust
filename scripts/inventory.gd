extends RefCounted
## Shared inventory. Slots hold item dictionaries; an empty slot is {}.
## Slot indices: 0-23 main grid, 24-29 belt, 30-36 clothing, 37-42 extra row (above the grid).
const GRID := 24
const BELT_START := 24
const WEAR_START := 30
const EXTRA_START := 37
const SLOTS := 43

## Stackable items: name, stack size, tint (for items without a dedicated icon), short label.
const ITEMS := {
	"rifle_ammo": {"name": "5.56 патроны", "stack": 128},
	"pistol_ammo": {"name": "Пистолетные патроны", "stack": 128},
	"bandage": {"name": "Бинт", "stack": 10},
	"wood": {"name": "Дерево", "stack": 1000, "color": Color(0.55, 0.38, 0.2), "tag": "ДЕР"},
	"stone": {"name": "Камень", "stack": 1000, "color": Color(0.5, 0.5, 0.48), "tag": "КАМ"},
	"metal": {"name": "Металл", "stack": 1000, "color": Color(0.45, 0.5, 0.58), "tag": "МЕТ"},
	"hqm": {"name": "МВК", "stack": 100, "color": Color(0.32, 0.36, 0.42), "tag": "МВК"},
	"plan": {"name": "План постройки", "stack": 1, "color": Color(0.2, 0.55, 0.78), "tag": "ПЛАН"},
	"hammer": {"name": "Молоток", "stack": 1, "color": Color(0.7, 0.55, 0.25), "tag": "МОЛ"},
}

var slots: Array = []
var selected_belt := 0
var wm
var build  # building.gd, set by main

var grid: Array:
	get: return slots.slice(0, GRID)
var belt: Array:
	get: return slots.slice(BELT_START, BELT_START + 6)


func setup(manager) -> void:
	wm = manager
	slots.resize(SLOTS)
	for i in range(SLOTS):
		slots[i] = {}
	for i in range(4):
		slots[BELT_START + i] = {"kind": "weapon", "weapon": i}
	slots[BELT_START + 4] = {"kind": "plan", "count": 1}
	slots[BELT_START + 5] = {"kind": "hammer", "count": 1}
	slots[0] = {"kind": "rifle_ammo", "count": 120}
	slots[1] = {"kind": "pistol_ammo", "count": 108}
	slots[2] = {"kind": "bandage", "count": 3}
	slots[EXTRA_START] = {"kind": "wood", "count": 1000}
	slots[EXTRA_START + 1] = {"kind": "stone", "count": 500}
	slots[EXTRA_START + 2] = {"kind": "metal", "count": 300}
	slots[EXTRA_START + 3] = {"kind": "hqm", "count": 50}


func belt_item(i: int) -> Dictionary:
	return slots[BELT_START + i]


func slot_get(index: int) -> Dictionary:
	if index >= 0 and index < SLOTS:
		return slots[index]
	return {}


func _slot_set(index: int, item: Dictionary) -> void:
	if index >= 0 and index < SLOTS:
		slots[index] = item


func stack_max(kind: String) -> int:
	return int(ITEMS.get(kind, {}).get("stack", 1))


func move(src: int, dst: int) -> bool:
	if src < 0 or dst < 0 or src == dst:
		return false
	var a := slot_get(src)
	var b := slot_get(dst)
	if a.is_empty():
		return false
	# No wearable items yet: never place anything else into clothing slots.
	if dst >= WEAR_START and dst < EXTRA_START and a.get("kind", "") != "wearable":
		return false
	if src >= WEAR_START and src < EXTRA_START and not b.is_empty() and b.get("kind", "") != "wearable":
		return false
	var kind: String = a.get("kind", "")
	if ITEMS.has(kind) and kind == b.get("kind", "") and a.has("count"):
		var n := mini(int(a["count"]), stack_max(kind) - int(b["count"]))
		if n > 0:
			b["count"] = int(b["count"]) + n
			a["count"] = int(a["count"]) - n
			if int(a["count"]) == 0:
				_slot_set(src, {})
	else:
		_slot_set(src, b)
		_slot_set(dst, a)
	if src == BELT_START + selected_belt or dst == BELT_START + selected_belt:
		select(selected_belt)
	return true


func select(index: int) -> void:
	if index < 0 or index >= 6:
		return
	selected_belt = index
	var item: Dictionary = belt_item(index)
	var kind: String = item.get("kind", "")
	if kind == "weapon":
		if build:
			build.set_mode("")
		wm.switch_to(int(item["weapon"]))
		return
	wm.unequip()
	if kind == "plan" and build:
		build.set_mode("plan")
	elif kind == "hammer" and build:
		build.set_mode("hammer")
	else:
		if build:
			build.set_mode("")
		if kind == "bandage":
			wm.show_message("Бинт: лечение пока не реализовано")


func _ammo_kind(weapon_index: int) -> String:
	return "rifle_ammo" if weapon_index == 0 else "pistol_ammo"


func reserve_for(weapon_index: int) -> int:
	if weapon_index < 0 or weapon_index > 2:
		return 0
	return count_of(_ammo_kind(weapon_index))


func consume_for(weapon_index: int, amount: int) -> int:
	if weapon_index < 0 or weapon_index > 2:
		return 0
	return take(_ammo_kind(weapon_index), amount)


func count_of(kind: String) -> int:
	var total := 0
	for item in slots:
		if item.get("kind", "") == kind:
			total += int(item.get("count", 0))
	return total


## Removes up to `amount` of an item kind, returns how many were removed.
func take(kind: String, amount: int) -> int:
	var remaining := amount
	for index in range(SLOTS):
		if index >= WEAR_START and index < EXTRA_START:
			continue
		var item: Dictionary = slots[index]
		if item.get("kind", "") != kind:
			continue
		var n := mini(remaining, int(item["count"]))
		item["count"] = int(item["count"]) - n
		remaining -= n
		if int(item["count"]) <= 0:
			slots[index] = {}
		if remaining == 0:
			break
	return amount - remaining
