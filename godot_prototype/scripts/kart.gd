class_name Kart
extends Node3D
## One racer: arcade kart driving (gas, steering, drifting with mini-turbos, boosts, jumps), walls and
## scenery to bump into, lap counting, and the look (wheels spinning, leaning, sparks and boost flames).
## The player and the computer drivers both use this; the computer just fills in its own steering.

signal lap_done(kart: Kart)
signal sound(kart: Kart, name: String)

const BASE_TOP := 32.5
const BASE_ACCEL := 13.0
const GRAVITY := 22.0
const TURN := 1.75

var track: Track
var char_index := 0
var display_name := ""
var stats := [1.0, 1.0, 1.0, 1.0]
var is_player := false

# where it is on the road
var idx := 0
var lateral := 0.0
var frac := 0.0
var heading := 0.0         # which way the kart points (yaw)
var move_heading := 0.0    # which way it is actually moving (lags while drifting)
var speed := 0.0
var vy := 0.0
var grounded := true

# controls (filled by the player's buttons or the computer driver)
var in_steer := 0.0
var in_gas := false
var in_brake := false
var in_drift := false
var frozen := true

# blessings (items)
var item := ""             # the blessing being held, "" = none
var item_hold := 0.0       # how long it has been held (the computer waits a little before using it)
var shield_t := 0.0        # Shield of Faith: no slowdowns from grass or bumps
var carried_t := 0.0       # carried along (Good Samaritan / Jubilee): fast, safe, steered for you
var parting_t := 0.0       # Parting of the Sea: the open land is as smooth as the road

var drift_dir := 0
var drift_charge := 0.0
var boost_t := 0.0
var boost_mul := 1.0

# laps
var laps_done := 0
var crossed_start := false
var half_passed := false
var last_p := 0.0
var finished := false
var finish_time := 0.0
var race_progress := 0.0

# computer driver
var ai_lane := 0.0
var ai_skill := 1.0
var ai_wobble := 0.0

# looks
var model: Node3D
var _wheels := {}
var _wheel_spin := 0.0
var _up := Vector3.UP
var _sparks: Array[GPUParticles3D] = []
var _spark_mat: StandardMaterial3D
var _flame: MeshInstance3D
var _dust: GPUParticles3D
var _bubble: MeshInstance3D


func setup(t: Track, ci: int, player: bool) -> void:
	track = t
	char_index = ci
	is_player = player
	var c: Dictionary = Game.CHARACTERS[ci]
	display_name = c["name"]
	stats = c["stats"]
	model = Game.char_scene(ci).instantiate() as Node3D
	add_child(model)
	for w in ["wheel_fl", "wheel_fr", "wheel_bl", "wheel_br"]:
		var node := model.find_child(w, true, false) as Node3D
		if node:
			_wheels[w] = node
	_make_effects()


func place(at_idx: int, back: float, lat: float) -> void:
	var p := track.pos[at_idx] - track.fwd[at_idx] * back + track.right[at_idx] * lat
	var loc := track.locate(p, at_idx)
	idx = loc[0]; lateral = loc[1]; frac = loc[2]
	p.y = track.ground_at(idx, frac, lateral)
	position = p
	heading = atan2(track.fwd[at_idx].x, track.fwd[at_idx].z)
	move_heading = heading
	last_p = track.progress_of(idx, frac)
	_update_look(0.0)


func forward() -> Vector3:
	return Vector3(sin(heading), 0.0, cos(heading))


func top_speed() -> float:
	return BASE_TOP * float(stats[0])


func boosting() -> bool:
	return boost_t > 0.0


# ---------------------------------------------------------------- driving

func step(dt: float, race_time: float) -> void:
	if (not is_player or carried_t > 0.0) and not frozen:
		_ai_think()
		if carried_t > 0.0:
			in_drift = false
	if item != "":
		item_hold += dt
	shield_t = maxf(shield_t - dt, 0.0)
	parting_t = maxf(parting_t - dt, 0.0)
	if carried_t > 0.0:
		carried_t -= dt
		boost_t = maxf(boost_t, 0.2); boost_mul = maxf(boost_mul, 1.6)
	var top := top_speed()
	if not is_player:
		top *= ai_skill
	var h := track.half(idx)
	var a := absf(lateral)
	var off := 1.0
	if a > h + track.shoulder:
		off = 0.55          # grass
	elif a > h + 0.3:
		off = 0.78          # dirt shoulder
	if shield_t > 0.0 or parting_t > 0.0:
		off = maxf(off, 0.92)
	if boost_t > 0.0:
		boost_t -= dt
		top *= boost_mul
		off = maxf(off, 0.95)
		if boost_t <= 0.0:
			boost_mul = 1.0
	top *= off

	if frozen:
		speed = move_toward(speed, 0.0, 20.0 * dt)
	elif in_brake:
		speed = move_toward(speed, -8.0, (30.0 if speed > 0.0 else 10.0) * dt)
	elif in_gas:
		if speed < top:
			var acc := BASE_ACCEL * float(stats[1]) * (1.0 - 0.55 * clampf(speed / top, 0.0, 1.0))
			speed = minf(speed + acc * dt * 1.6, top)
		else:
			speed = move_toward(speed, top, 14.0 * dt)
	else:
		speed = move_toward(speed, 0.0, 7.0 * dt)

	# steering and drifting
	var turn := TURN * float(stats[2])
	var sf := clampf(absf(speed) / 9.0, 0.0, 1.0) * (1.0 - 0.3 * clampf(speed / BASE_TOP, 0.0, 1.0))
	if drift_dir == 0 and in_drift and grounded and absf(in_steer) > 0.5 and speed > 12.0 and not frozen:
		drift_dir = 1 if in_steer > 0.0 else -1
		drift_charge = 0.0
		vy = 3.8; grounded = false          # a little hop into the drift
	if drift_dir != 0:
		if not in_drift or speed < 8.0:
			_end_drift()
		else:
			# stick toward the drift = tighter, stick away = wider, stick in the middle = a gentle arc
			var k := 0.42 + 0.38 * in_steer * drift_dir
			heading -= drift_dir * k * turn * dt
			drift_charge += dt * (0.8 + 0.6 * absf(in_steer))
	else:
		heading -= in_steer * turn * sf * dt * signf(speed if absf(speed) > 0.1 else 1.0)
	heading = wrapf(heading, -PI, PI)
	var grip := 5.0 if drift_dir != 0 else 9.0
	move_heading = lerp_angle(move_heading, heading, clampf(grip * dt, 0.0, 1.0))

	# move
	var dir := Vector3(sin(move_heading), 0.0, cos(move_heading))
	var p := position + dir * speed * dt
	p = _collide_scenery(p)
	var loc := track.locate(p, idx)
	idx = loc[0]; lateral = loc[1]; frac = loc[2]
	# the low walls at the edge of the open land
	var side := 1 if lateral > 0.0 else -1
	var b := track.bound(idx, side) + 0.2
	if absf(lateral) > b:
		var r := track.right[idx].lerp(track.right[(idx + 1) % track.n], frac).normalized()
		var push := absf(lateral) - b
		p -= r * side * push
		var inward := -r * side
		var v := dir * speed
		var into := v.dot(inward)
		if into < 0.0:
			v -= inward * into * 1.5
			speed = v.length() * 0.8 * signf(speed)
			if speed > 0.1:
				move_heading = atan2(v.x, v.z)
				heading = lerp_angle(heading, move_heading, 0.5)
			if into < -6.0:
				sound.emit(self, "bump")
		lateral = signf(lateral) * b
	# ground height, jumps and landing
	var g := track.ground_at(idx, frac, lateral)
	if grounded:
		if p.y - g > 0.8:
			grounded = false
		else:
			p.y = g
	if not grounded:
		vy -= GRAVITY * dt
		p.y += vy * dt
		if p.y <= g:
			p.y = g
			if vy < -7.0:
				sound.emit(self, "land")
			vy = 0.0
			grounded = true
	position = p
	if grounded:
		_check_pads()
	_count_laps(race_time)
	_update_look(dt)


func _end_drift() -> void:
	if drift_charge > 2.6:
		_boost(1.25, 1.38); sound.emit(self, "super_turbo")
	elif drift_charge > 1.2:
		_boost(0.7, 1.3); sound.emit(self, "mini_turbo")
	drift_dir = 0
	drift_charge = 0.0


func give_boost(t: float, mul: float) -> void:
	_boost(t, mul)


func _boost(t: float, mul: float) -> void:
	boost_mul = maxf(boost_mul if boost_t > 0.0 else 1.0, mul)
	boost_t = maxf(boost_t, t)
	speed = maxf(speed, top_speed() * minf(mul, 1.15))


func _check_pads() -> void:
	for pd in track.pads:
		var pi := int(pd["idx"])
		var di := absi(pi - idx)
		di = mini(di, track.n - di)
		if di <= 2 and absf(lateral - float(pd["lat"])) < float(pd["half"]) + 0.6:
			if pd["kind"] == "boost":
				if boost_t < 1.0:
					sound.emit(self, "boost_pad")
				boost_t = maxf(boost_t, 1.3); boost_mul = maxf(boost_mul, 1.4)
				speed = maxf(speed, top_speed() * 1.05)
			elif grounded:
				vy = 11.0; grounded = false
				boost_t = maxf(boost_t, 0.6); boost_mul = maxf(boost_mul, 1.2)
				sound.emit(self, "bounce")


func _collide_scenery(p: Vector3) -> Vector3:
	var me := Vector2(p.x, p.z)
	for o in track.obstacles:
		var c: Vector2 = o[0]
		var r: float = o[1] + 0.9
		var d := me - c
		if d.length_squared() < r * r and d.length_squared() > 0.0001:
			var nrm := d.normalized()
			me = c + nrm * r
			speed *= 0.85 if shield_t > 0.0 else 0.55
			sound.emit(self, "bump")
	p.x = me.x
	p.z = me.y
	return p


func _count_laps(race_time: float) -> void:
	var L := track.length
	var pr := track.progress_of(idx, frac)
	if pr > L * 0.4 and pr < L * 0.6:
		half_passed = true
	if last_p > L * 0.8 and pr < L * 0.2:
		if not crossed_start:
			crossed_start = true
		elif half_passed:
			laps_done += 1
			half_passed = false
			if laps_done >= track.laps and not finished:
				finished = true
				finish_time = race_time
			lap_done.emit(self)
	last_p = pr
	race_progress = (laps_done * L + pr) if crossed_start else (pr - L)
	if finished:
		race_progress = 1e6 - finish_time


# ---------------------------------------------------------------- the computer driver

func _ai_think() -> void:
	ai_wobble += 0.016
	var look := 6 + int(speed * 0.16)
	var ti := (idx + look) % track.n
	var lane := clampf(ai_lane + sin(ai_wobble * 0.7 + ai_lane) * 1.2, -track.half(ti) + 1.2, track.half(ti) - 1.2)
	var target := track.pos[ti] + track.right[ti] * lane
	var want := atan2(target.x - position.x, target.z - position.z)
	var diff := wrapf(want - heading, -PI, PI)
	in_steer = clampf(-diff * 3.0, -1.0, 1.0)
	in_gas = true
	in_brake = false
	# ease off for sharp bends so they don't run wide onto the grass
	var bend := absf(wrapf(atan2(track.fwd[(idx + 14) % track.n].x, track.fwd[(idx + 14) % track.n].z) - heading, -PI, PI))
	in_brake = bend > 0.9 and speed > top_speed() * 0.75
	in_drift = false


# ---------------------------------------------------------------- looks

static var _soft_dot: Texture2D


static func soft_dot() -> Texture2D:
	if _soft_dot == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
		_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot


func _make_effects() -> void:
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.albedo_texture = soft_dot()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(0.4, 0.75, 1.0)
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for sx in [-0.8, 0.8]:
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, -1)
		pm.spread = 35.0
		pm.initial_velocity_min = 3.0; pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(0, -12, 0)
		pm.scale_min = 0.6; pm.scale_max = 1.2
		p.process_material = pm
		var q := QuadMesh.new(); q.size = Vector2(0.22, 0.22); q.material = _spark_mat
		p.draw_pass_1 = q
		p.amount = 40; p.lifetime = 0.35; p.emitting = false
		p.position = Vector3(sx, 0.15, -1.0)
		add_child(p)
		_sparks.append(p)
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.28; cone.height = 1.4
	_flame.mesh = cone
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.6, 0.2, 0.85); fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.emission_enabled = true; fm.emission = Color(1.0, 0.5, 0.1); fm.emission_energy_multiplier = 4.0
	_flame.material_override = fm
	_flame.rotation.x = -PI / 2.0
	_flame.position = Vector3(0, 0.55, -1.7)
	_flame.visible = false
	add_child(_flame)
	_dust = GPUParticles3D.new()
	var dm := ParticleProcessMaterial.new()
	dm.direction = Vector3(0, 0.6, -1); dm.spread = 25.0
	dm.initial_velocity_min = 1.0; dm.initial_velocity_max = 2.5
	dm.gravity = Vector3(0, 0.5, 0)
	dm.scale_min = 1.0; dm.scale_max = 2.2
	dm.color = Color(0.55, 0.5, 0.42, 0.45)
	_dust.process_material = dm
	var dq := QuadMesh.new(); dq.size = Vector2(0.7, 0.7)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = soft_dot()
	dq.material = dmat
	_dust.draw_pass_1 = dq
	_dust.amount = 24; _dust.lifetime = 0.8; _dust.emitting = false
	_dust.position = Vector3(0, 0.2, -1.2)
	add_child(_dust)


func _update_look(dt: float) -> void:
	# tilt to the ground: compare the ground height a little ahead/behind and left/right
	var i2 := (idx + 1) % track.n
	var slope_f := (track.pos[i2].y - track.pos[idx].y) / maxf(track.pos[idx].distance_to(track.pos[i2]), 0.01)
	var slope_r := (track.surface_y(idx, lateral + 0.7) - track.surface_y(idx, lateral - 0.7)) / 1.4
	var r := track.right[idx]
	var t := track.fwd[idx]
	var target_up := (Vector3.UP - t * slope_f - r * slope_r).normalized()
	if not grounded:
		target_up = Vector3.UP
	_up = _up.lerp(target_up, clampf(dt * 10.0, 0.0, 1.0)).normalized() if dt > 0.0 else target_up
	var f := forward()
	f = (f - _up * f.dot(_up)).normalized()
	var x := _up.cross(f).normalized()
	basis = Basis(x, _up, f)
	# model lean into turns and drifts
	var lean := -in_steer * 0.07 + (-drift_dir * 0.12)
	if model:
		model.rotation = Vector3(0.0, -drift_dir * 0.35, lerpf(model.rotation.z, lean, clampf(dt * 8.0, 0.0, 1.0)))
	_wheel_spin += speed * dt / 0.32
	for w in _wheels:
		var node: Node3D = _wheels[w]
		var yaw := -in_steer * 0.35 if w.begins_with("wheel_f") else 0.0
		node.rotation = Vector3(_wheel_spin, yaw, 0.0)
	# sparks: blue, then orange when the mini-turbo is charged
	var sparking := drift_dir != 0 and grounded and drift_charge > 0.4
	for s in _sparks:
		s.emitting = sparking
	if drift_charge > 2.6:
		_spark_mat.albedo_color = Color(1.0, 0.55, 0.15)
	elif drift_charge > 1.2:
		_spark_mat.albedo_color = Color(0.35, 0.7, 1.0)
	else:
		_spark_mat.albedo_color = Color(1.0, 1.0, 0.85)
	if _bubble == null:
		_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 1.7; sm.height = 2.6
		_bubble.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.85, 0.35, 0.18)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.emission_enabled = true; bm.emission = Color(1.0, 0.8, 0.3); bm.emission_energy_multiplier = 0.8
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bubble.material_override = bm
		_bubble.position = Vector3(0, 0.9, 0)
		add_child(_bubble)
	_bubble.visible = shield_t > 0.0 or carried_t > 0.0
	if _bubble.visible:
		_bubble.scale = Vector3.ONE * (1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.01))
	_flame.visible = boost_t > 0.0
	if _flame.visible:
		_flame.scale = Vector3.ONE * (0.8 + 0.3 * sin(Time.get_ticks_msec() * 0.05))
	_dust.emitting = grounded and absf(lateral) > track.half(idx) + 0.3 and absf(speed) > 6.0
