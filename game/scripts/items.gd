class_name Items
extends Node3D
## The blessings: glowing boxes on the road, the spinning pick, and what each blessing does.
## Like the Wii U game, every blessing helps you AND another racer (no weapons).

signal used(kart: Kart, id: String)
signal picked(kart: Kart)

const BLESSINGS := {
	"manna": {"name": "Manna", "verse": "Exodus 16:4", "line": "Bread from heaven!"},
	"loaves": {"name": "Loaves and Fishes", "verse": "Matthew 14:19", "line": "Everyone is fed!"},
	"samaritan": {"name": "Good Samaritan", "verse": "Luke 10:33", "line": "The last racer is carried!"},
	"shield": {"name": "Shield of Faith", "verse": "Ephesians 6:16", "line": "Shielded, with the one behind you!"},
	"parting": {"name": "Parting of the Sea", "verse": "Exodus 14:21", "line": "Smooth ground for everyone!"},
	"jubilee": {"name": "Jubilee Trumpet", "verse": "Leviticus 25:10", "line": "Freedom! Everyone far behind is lifted!"},
	"fire": {"name": "Chariot of Fire", "verse": "2 Kings 2:11", "line": "Blazing speed, a fire trail for others!"},
	"water": {"name": "Living Water", "verse": "John 4:14", "line": "Refreshed, with the two racers nearest you!"},
}
# which blessings you can get: the front of the race gets small ones, the back gets the big helps
const BY_PLACE := [
	["manna", "manna", "shield", "water", "loaves"],                 # 1st - 2nd
	["manna", "shield", "water", "loaves", "parting", "manna"],      # 3rd - 5th
	["fire", "samaritan", "jubilee", "parting", "manna", "water"],   # 6th - 8th
]
const BOX_RESPAWN := 3.0

var track: Track
var karts: Array[Kart] = []
var _boxes: Array = []       # [Node3D, Vector3 pos, respawn timer]
var _trails: Array = []      # manna pieces and fire on the road: [Node3D, Vector3 pos, life, kind, owner]
var _box_mat: StandardMaterial3D
var _gold: StandardMaterial3D


func setup(t: Track, all: Array[Kart]) -> void:
	track = t
	karts = all
	_box_mat = StandardMaterial3D.new()
	_box_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.45)
	_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mat.emission_enabled = true
	_box_mat.emission = Color(0.35, 0.65, 1.0)
	_box_mat.emission_energy_multiplier = 1.6
	_box_mat.metallic = 0.3
	_box_mat.roughness = 0.05
	_gold = StandardMaterial3D.new()
	_gold.albedo_color = Color(1.0, 0.82, 0.35)
	_gold.metallic = 0.9
	_gold.roughness = 0.2
	_gold.emission_enabled = true
	_gold.emission = Color(1.0, 0.7, 0.25)
	_gold.emission_energy_multiplier = 1.5
	# four rows of boxes round the lap, across the whole road
	for frac in [0.12, 0.36, 0.6, 0.83]:
		var i := int(track.n * frac)
		var w := track.half(i) - 1.6
		for k in 4:
			var lat := lerpf(-w, w, k / 3.0)
			var at := track.point_at(i, lat) + Vector3.UP * 1.1
			_boxes.append([_make_box(at), at, 0.0])


func _make_box(at: Vector3) -> Node3D:
	# a glowing glass cube with a golden cross turning inside it
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var cube := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3.ONE * 1.3
	cube.mesh = bm
	cube.material_override = _box_mat
	cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cube)
	var cross := Node3D.new()
	root.add_child(cross)
	for sz in [Vector3(0.18, 0.85, 0.18), Vector3(0.55, 0.18, 0.18)]:
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new(); b.size = sz
		bar.mesh = b
		bar.material_override = _gold
		bar.position = Vector3(0, 0.12 if sz.x > 0.3 else 0.0, 0)
		cross.add_child(bar)
	return root


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for b in _boxes:
		var node: Node3D = b[0]
		if b[2] > 0.0:
			b[2] -= dt
			if b[2] <= 0.0:
				node.visible = true
				node.scale = Vector3.ONE * 0.1
		if node.visible:
			node.scale = node.scale.lerp(Vector3.ONE, clampf(dt * 6.0, 0.0, 1.0))
			node.rotation = Vector3(0.35, t * 1.4, 0.2)
			node.position.y = b[1].y + sin(t * 2.0 + b[1].x) * 0.15
			(node.get_child(1) as Node3D).rotation.y = -t * 3.0


func step(dt: float, place_of: Callable) -> void:
	# pick up boxes
	for b in _boxes:
		var node: Node3D = b[0]
		if not node.visible:
			continue
		for k in karts:
			if k.position.distance_squared_to(b[1]) < 2.6 * 2.6:
				node.visible = false
				b[2] = BOX_RESPAWN
				if k.item == "":
					var place: int = place_of.call(k)
					var pool: Array = BY_PLACE[0 if place <= 2 else (1 if place <= 5 else 2)]
					k.item = pool[randi() % pool.size()]
					k.item_hold = 0.0
					picked.emit(k)
				break
	# manna on the road and the fire trail: a little boost for whoever drives through
	for tr in _trails.duplicate():
		tr[2] -= dt
		var node: Node3D = tr[0]
		if tr[2] <= 0.0:
			node.queue_free()
			_trails.erase(tr)
			continue
		for k in karts:
			if k != tr[4] and k.position.distance_squared_to(tr[1]) < 2.2 * 2.2:
				k.give_boost(0.8, 1.25)
				if tr[3] == "manna":
					node.queue_free()
					_trails.erase(tr)
					break
	# the computer racers use their blessing after holding it a moment
	for k in karts:
		if k.item != "" and (not k.is_player) and k.item_hold > 1.5 + float(k.char_index % 3):
			use(k, place_of)


## Use the blessing a kart is holding.
func use(k: Kart, place_of: Callable) -> void:
	var id := k.item
	if id == "":
		return
	k.item = ""
	k.item_hold = 0.0
	var order := karts.duplicate()
	order.sort_custom(func(x, y): return x.race_progress > y.race_progress)
	var mine := order.find(k)
	match id:
		"manna":
			k.give_boost(1.7, 1.45)
			for n in 3:
				_drop(k, "manna", 3.0 + n * 4.5, 14.0)
		"loaves":
			for o in karts:
				if o == k:
					o.give_boost(1.6, 1.35)
				else:
					o.give_boost(0.8, 1.15)
		"samaritan":
			var last: Kart = order[order.size() - 1]
			last.carried_t = 3.5
			last.shield_t = maxf(last.shield_t, 4.0)
			if last != k:
				k.give_boost(1.0, 1.25)
		"shield":
			k.shield_t = maxf(k.shield_t, 8.0)
			if mine + 1 < order.size():
				var behind: Kart = order[mine + 1]
				behind.shield_t = maxf(behind.shield_t, 8.0)
		"parting":
			for o in karts:
				o.parting_t = 10.0
			k.give_boost(1.2, 1.3)
		"jubilee":
			var lead: float = order[0].race_progress
			for o in karts:
				if lead - o.race_progress > 300.0:
					o.carried_t = maxf(o.carried_t, 3.0)
			k.give_boost(1.5, 1.3)
		"fire":
			k.give_boost(4.0, 1.5)
			k.shield_t = maxf(k.shield_t, 4.0)
			for n in 8:
				_drop(k, "fire", 2.0 + n * 3.0, 6.0)
		"water":
			k.give_boost(1.0, 1.25)
			var near := karts.filter(func(o): return o != k)
			near.sort_custom(func(x, y): return x.position.distance_squared_to(k.position) < y.position.distance_squared_to(k.position))
			for o in near.slice(0, 2):
				o.give_boost(1.0, 1.15)
	used.emit(k, id)


func _drop(k: Kart, kind: String, back: float, life: float) -> void:
	var f := k.forward()
	var at := k.position - f * back + Vector3.UP * 0.4
	var node := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	if kind == "manna":
		var cm := CylinderMesh.new(); cm.top_radius = 0.45; cm.bottom_radius = 0.45; cm.height = 0.18
		node.mesh = cm
		m.albedo_color = Color(1.0, 0.97, 0.88)
		m.emission = Color(1.0, 0.9, 0.6); m.emission_energy_multiplier = 1.2
	else:
		var sm := SphereMesh.new(); sm.radius = 0.7; sm.height = 1.4
		node.mesh = sm
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.45, 0.1, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission = Color(1.0, 0.4, 0.05); m.emission_energy_multiplier = 4.0
	node.material_override = m
	node.position = at
	add_child(node)
	_trails.append([node, at, life, kind, k])
