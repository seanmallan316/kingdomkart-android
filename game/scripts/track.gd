class_name Track
extends Node3D
## Bethlehem Road: builds the road, shoulders, open land, walls, scenery and lights from data/beth.json,
## and answers "where am I on the road?" and "how high is the ground here?" for the karts.

const CHUNK := 32            # road samples per mesh piece (lets each piece get its own nearby lantern lights)
const WALL_DROP := 1.2

var n := 0
var laps := 3
var length := 0.0
var shoulder := 4.0
var pos: PackedVector3Array = []
var fwd: PackedVector3Array = []
var right: PackedVector3Array = []
var width: PackedFloat32Array = []
var bank: PackedFloat32Array = []
var dist: PackedFloat32Array = []
var field_l: PackedFloat32Array = []
var field_r: PackedFloat32Array = []
var pads: Array = []
var obstacles: Array = []    # [Vector2 xz, radius]
var star_pos := Vector3.ZERO

var _tex_cache := {}


func load_data(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	n = int(d["n"]); laps = int(d["laps"]); length = float(d["length"]); shoulder = float(d["shoulder"])
	for i in n:
		pos.append(Vector3(d["x"][i], d["y"][i], d["z"][i]))
		width.append(float(d["width"][i])); bank.append(float(d["bank"][i])); dist.append(float(d["dist"][i]))
		field_l.append(float(d["field_l"][i])); field_r.append(float(d["field_r"][i]))
	for i in n:
		var t := pos[(i + 1) % n] - pos[(i - 1 + n) % n]
		t.y = 0.0
		t = t.normalized()
		fwd.append(t)
		right.append(Vector3(-t.z, 0.0, t.x))
	pads = d["pads"]
	star_pos = Vector3(d["star"][0], d["star"][1], d["star"][2])
	_build_ground()
	_build_walls()
	_build_pads()
	_build_scenery(d["scenery"])
	_build_start_line()


# ---------------------------------------------------------------- road math

func half(i: int) -> float:
	return width[i] * 0.5


func edge(i: int) -> float:
	return width[i] * 0.5 + shoulder


func bound(i: int, side: int) -> float:
	return edge(i) + (field_r[i] if side > 0 else field_l[i])


func surface_y(i: int, lateral: float) -> float:
	var h := half(i)
	var e := h + shoulder
	var bl := clampf(lateral, -e, e)
	var y := pos[i].y + bl * tan(bank[i])
	var a := absf(lateral)
	if a > h:
		var u := minf((a - h) / shoulder, 1.0)
		y -= WALL_DROP * u * u
	return y


## Finds the nearest road sample to a point, searching near a hint. Returns [index, lateral, fraction to next].
func locate(p: Vector3, hint: int) -> Array:
	var best := hint
	var bd := INF
	for o in range(-12, 25):
		var i := (hint + o + n) % n
		var dx := p.x - pos[i].x
		var dz := p.z - pos[i].z
		var dd := dx * dx + dz * dz
		if dd < bd:
			bd = dd; best = i
	var a := pos[best]
	var b := pos[(best + 1) % n]
	var seg := Vector2(b.x - a.x, b.z - a.z)
	var rel := Vector2(p.x - a.x, p.z - a.z)
	var f := clampf(rel.dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
	if rel.dot(seg) < 0.0:
		var pi := (best - 1 + n) % n
		var pa := pos[pi]
		var seg2 := Vector2(a.x - pa.x, a.z - pa.z)
		var rel2 := Vector2(p.x - pa.x, p.z - pa.z)
		best = pi
		f = clampf(rel2.dot(seg2) / maxf(seg2.length_squared(), 0.0001), 0.0, 1.0)
	var c := pos[best].lerp(pos[(best + 1) % n], f)
	var r := right[best].lerp(right[(best + 1) % n], f).normalized()
	var lat := Vector2(p.x - c.x, p.z - c.z).dot(Vector2(r.x, r.z))
	return [best, lat, f]


func ground_at(i: int, f: float, lateral: float) -> float:
	var j := (i + 1) % n
	return lerpf(surface_y(i, lateral), surface_y(j, lateral), f)


func point_at(i: int, lateral: float) -> Vector3:
	var p := pos[i] + right[i] * lateral
	p.y = surface_y(i, lateral)
	return p


## Distance along the road from the start line.
func progress_of(i: int, f: float) -> float:
	var j := (i + 1) % n
	var d1 := dist[j] if j != 0 else length
	return lerpf(dist[i], d1, f)


# ---------------------------------------------------------------- building

func _tex(tex_name: String) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var t := load("res://textures/%s.png" % tex_name) as Texture2D
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	_tex_cache[tex_name] = it
	return it


func _mat(tex_name: String, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex_name)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _build_ground() -> void:
	# cross-section, left to right: land edge, shoulder edge, road edge, road edge, shoulder edge, land edge
	var road_m := _mat("beth_road", 0.75)
	var dirt_m := _mat("beth_dirt")
	var grass_m := _mat("beth_grass")
	var body := StaticBody3D.new()
	add_child(body)
	var c := 0
	while c < n:
		var stop := mini(c + CHUNK, n)
		var road := SurfaceTool.new(); road.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dirt := SurfaceTool.new(); dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
		var grass := SurfaceTool.new(); grass.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(c, stop):
			var j := (i + 1) % n
			var vi := dist[i] / 8.0
			var vj := (dist[j] if j != 0 else length) / 8.0
			_strip(road, i, j, -half(i), half(i), -half(j), half(j), 0.0, 1.0, vi, vj)
			_strip(dirt, i, j, -edge(i), -half(i), -edge(j), -half(j), 0.0, 1.0, vi, vj)
			_strip(dirt, i, j, half(i), edge(i), half(j), edge(j), 0.0, 1.0, vi, vj)
			_strip(grass, i, j, -bound(i, -1) - 1.0, -edge(i), -bound(j, -1) - 1.0, -edge(j), 0.0, 4.0, vi, vj, true)
			_strip(grass, i, j, edge(i), bound(i, 1) + 1.0, edge(j), bound(j, 1) + 1.0, 0.0, 4.0, vi, vj, true)
		var mesh := ArrayMesh.new()
		for pair in [[road, road_m], [dirt, dirt_m], [grass, grass_m]]:
			var st: SurfaceTool = pair[0]
			st.generate_normals()
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		c = stop
	# a wide plain beyond the walls so the world never ends
	var plain := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(1400, 1400); pm.subdivide_depth = 8; pm.subdivide_width = 8
	plain.mesh = pm
	var gm := _mat("beth_grass")
	gm.uv1_scale = Vector3(120, 120, 1)
	gm.albedo_color = Color(0.55, 0.6, 0.55)
	plain.material_override = gm
	plain.position = Vector3(-120, -2.0, 30)
	add_child(plain)


func _strip(st: SurfaceTool, i: int, j: int, a0: float, b0: float, a1: float, b1: float,
		u0: float, u1: float, v0: float, v1: float, world_uv := false) -> void:
	var p := [point_at(i, a0), point_at(i, b0), point_at(j, a1), point_at(j, b1)]
	var uv: Array
	if world_uv:
		uv = []
		for q in p:
			uv.append(Vector2(q.x, q.z) / 6.0)
	else:
		uv = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1)]
	# two triangles; road runs along +tangent and +right is to the right, so wind them facing up
	for k in [0, 2, 1, 1, 2, 3]:
		st.set_uv(uv[k])
		st.add_vertex(p[k])


func _build_walls() -> void:
	# a low stone wall along the edge of the open land on both sides
	var m := _mat("beth_wall")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side: int in [-1, 1]:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n:
			var j := (i + 1) % n
			var a := point_at(i, side * (bound(i, side) + 1.0))
			var b := point_at(j, side * (bound(j, side) + 1.0))
			var a2 := a + Vector3.UP * 1.4
			var b2 := b + Vector3.UP * 1.4
			var u0 := dist[i] / 3.0
			var u1 := (dist[j] if j != 0 else length) / 3.0
			var quad := [a, b, a2, b2]
			var uvs := [Vector2(u0, 1), Vector2(u1, 1), Vector2(u0, 0), Vector2(u1, 0)]
			var order := [0, 2, 1, 1, 2, 3] if side < 0 else [0, 1, 2, 2, 1, 3]
			for k in order:
				st.set_uv(uvs[k]); st.add_vertex(quad[k])
			# the top of the wall
			var out := right[i] * side * 0.6
			var outj := right[j] * side * 0.6
			var top := [a2, b2, a2 + out, b2 + outj]
			for k in ([0, 2, 1, 1, 2, 3] if side < 0 else [0, 1, 2, 2, 1, 3]):
				st.set_uv(uvs[k] * Vector2(1, 0.2)); st.add_vertex(top[k])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		add_child(mi)


## Road frame at a sample: local +X = left, +Y = up, +Z = forward along the road.
func frame(i: int) -> Basis:
	return Basis(-right[i], Vector3.UP, fwd[i])


func _build_pads() -> void:
	for p in pads:
		var i := int(p["idx"])
		var boost: bool = p["kind"] == "boost"
		var root := Node3D.new()
		root.position = point_at(i, float(p["lat"])) + Vector3.UP * 0.05
		root.basis = frame(i)
		add_child(root)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.75, 0.2) if boost else Color(0.3, 0.85, 1.0)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.1) if boost else Color(0.2, 0.7, 1.0)
		m.emission_energy_multiplier = 3.0
		var w := float(p["half"])
		# a dark base plate, then glowing raised chevrons (boost) or a ring (bounce)
		var plate := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(w * 2.0, 0.06, 4.2)
		plate.mesh = bm
		var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.12, 0.1, 0.08); dark.metallic = 0.5; dark.roughness = 0.4
		plate.material_override = dark
		root.add_child(plate)
		if boost:
			for k in 3:
				for sd in [-1, 1]:
					var arm := MeshInstance3D.new()
					var am := BoxMesh.new(); am.size = Vector3(0.28, 0.12, w * 0.95)
					arm.mesh = am; arm.material_override = m
					arm.position = Vector3(sd * w * 0.32, 0.06, (k - 1) * 1.3 - 0.2)
					arm.rotation.y = -sd * 0.75
					root.add_child(arm)
		else:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new(); tm.inner_radius = w * 0.55; tm.outer_radius = w * 0.8
			ring.mesh = tm; ring.material_override = m
			ring.position = Vector3(0, 0.08, 0)
			ring.scale = Vector3(1, 0.4, 1)
			root.add_child(ring)
		var light := OmniLight3D.new()
		light.light_color = m.emission; light.light_energy = 1.5; light.omni_range = 7.0
		light.position = Vector3.UP * 1.0
		root.add_child(light)


func _model_height(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := node.global_transform.affine_inverse() * m.global_transform if node.is_inside_tree() else _rel_xf(node, m)
		var bb := xf * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return box


func _rel_xf(root: Node3D, n3: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n3
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _place_model(model: String, at: Vector3, height: float, yaw: float) -> Node3D:
	var ps := load("res://models/%s.glb" % model) as PackedScene
	var inst := ps.instantiate() as Node3D
	var bb := _model_height(inst)
	var s := height / maxf(bb.size.y, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = at - Vector3(0, bb.position.y * s, 0)
	inst.rotation.y = yaw
	add_child(inst)
	return inst


func _build_scenery(list: Array) -> void:
	var models := {"house": "prop_house", "house2": "prop_house", "inn": "prop_house", "palm": "prop_palm",
		"olive": "prop_olive", "sheep": "prop_sheep", "stable": "prop_stall", "stall": "prop_stall",
		"villager": "prop_villager", "boulder": "prop_boulder", "brazier": "prop_brazier"}
	for s in list:
		var i := int(s["idx"])
		var lat := float(s["side"])
		var side := 1 if lat > 0 else -1
		var limit := bound(i, side) - 1.0
		if absf(lat) > limit:
			lat = side * limit
		var at := point_at(i, lat)
		var kind: String = s["kind"]
		var h := float(s["h"])
		var face := atan2(-right[i].x * side, -right[i].z * side)    # buildings face the road
		match kind:
			"lantern":
				_lantern(at, h)
			"well":
				_well(at)
			"crystal":
				_crystal(at, h)
			_:
				var scale_h := h * (1.4 if kind == "inn" else 1.0)
				_place_model(models.get(kind, "prop_house"), at, scale_h, face)
				if kind == "stable":
					var glow := OmniLight3D.new()
					glow.light_color = Color(1.0, 0.8, 0.45); glow.light_energy = 3.0; glow.omni_range = 14.0
					glow.position = at + Vector3.UP * 2.0
					add_child(glow)
		var r := {"house": 4.0, "house2": 4.5, "inn": 5.5, "stable": 3.5, "stall": 1.8, "palm": 0.8, "olive": 1.2,
			"well": 1.6, "lantern": 0.4, "sheep": 0.9, "boulder": 1.6, "villager": 0.5, "brazier": 0.6, "crystal": 0.8}
		obstacles.append([Vector2(at.x, at.z), r.get(kind, 1.0)])


func _lantern(at: Vector3, h: float) -> void:
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.08; cm.bottom_radius = 0.12; cm.height = h
	post.mesh = cm
	var wood := StandardMaterial3D.new(); wood.albedo_color = Color(0.25, 0.16, 0.08); wood.roughness = 0.8
	post.material_override = wood
	post.position = at + Vector3.UP * h * 0.5
	add_child(post)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.32; sm.height = 0.64
	lamp.mesh = sm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.75, 0.4); glow.emission_enabled = true
	glow.emission = Color(1.0, 0.65, 0.25); glow.emission_energy_multiplier = 6.0
	lamp.material_override = glow
	lamp.position = at + Vector3.UP * (h + 0.2)
	add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.35); light.light_energy = 2.2; light.omni_range = 16.0
	light.position = lamp.position
	add_child(light)


func _well(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.4; cm.bottom_radius = 1.5; cm.height = 1.0
	mi.mesh = cm
	mi.material_override = _mat("beth_wall")
	mi.position = at + Vector3.UP * 0.5
	add_child(mi)
	var water := MeshInstance3D.new()
	var dm := CylinderMesh.new(); dm.top_radius = 1.15; dm.bottom_radius = 1.15; dm.height = 0.05
	water.mesh = dm
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.1, 0.2, 0.4); wm.metallic = 0.6; wm.roughness = 0.05
	water.material_override = wm
	water.position = at + Vector3.UP * 0.92
	add_child(water)


func _crystal(at: Vector3, h: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new(); pm.size = Vector3(h * 0.5, h, h * 0.5)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.85, 1.0, 0.8); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true; m.emission = Color(0.3, 0.7, 1.0); m.emission_energy_multiplier = 3.0
	m.metallic = 0.3; m.roughness = 0.1
	mi.material_override = m
	mi.position = at + Vector3.UP * h * 0.5
	mi.rotation.y = randf() * TAU
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.75, 1.0); light.light_energy = 1.5; light.omni_range = 8.0
	light.position = mi.position
	add_child(light)


func _build_start_line() -> void:
	# a checkered start/finish line and a banner arch over the road
	var img := Image.create(16, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 16:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.1))
	var tex := ImageTexture.create_from_image(img)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(width[0], 2.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new(); m.albedo_texture = tex; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = m
	mi.position = pos[0] + Vector3.UP * 0.03
	mi.basis = frame(0)
	add_child(mi)
	var wood := StandardMaterial3D.new(); wood.albedo_color = Color(0.45, 0.3, 0.15); wood.roughness = 0.7
	for side in [-1, 1]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.6, 7.0, 0.6)
		post.mesh = bm; post.material_override = wood
		post.position = pos[0] + right[0] * side * (half(0) + 1.5) + Vector3.UP * 3.5
		add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new(); bb.size = Vector3(width[0] + 3.6, 1.2, 0.5)
	beam.mesh = bb
	var gold := StandardMaterial3D.new(); gold.albedo_color = Color(0.95, 0.75, 0.3); gold.metallic = 0.9; gold.roughness = 0.3
	beam.material_override = gold
	beam.position = pos[0] + Vector3.UP * 7.0
	beam.basis = frame(0)
	add_child(beam)
	# solid 3D lettering on the banner, facing the racers as they arrive
	var words := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = "BETHLEHEM ROAD"; tm.font_size = 64; tm.pixel_size = 0.012; tm.depth = 0.15
	words.mesh = tm
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(1.0, 0.97, 0.88)
	wm.emission_enabled = true; wm.emission = Color(1.0, 0.85, 0.5); wm.emission_energy_multiplier = 1.2
	words.material_override = wm
	words.basis = Basis(right[0], Vector3.UP, -fwd[0])
	words.position = beam.position - fwd[0] * 0.35
	add_child(words)
