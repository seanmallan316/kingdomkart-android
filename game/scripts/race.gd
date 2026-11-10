class_name Race
extends Node3D
## A race on Bethlehem Road: the night sky and lights, eight racers, the chase camera, the countdown,
## laps, places, sounds and music, pausing, and the results.

signal finished_race(go_menu: bool)

const KART_COUNT := 8
const PLAYER_SLOT := 5

var track: Track
var karts: Array[Kart] = []
var player: Kart
var cam: Camera3D
var hud: Hud
var state := "countdown"   # countdown, racing, done
var count_t := 4.0
var race_time := 0.0
var done_t := 0.0
var final_lap_played := false
var autotest := false
var _shots_taken := {}

var music: AudioStreamPlayer
var engine: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_cache := {}


func _ready() -> void:
	_make_world()
	track = Track.new()
	add_child(track)
	track.load_data("res://data/beth.json")
	_make_hills()
	_make_karts()
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_snap_camera()
	hud = Hud.new()
	add_child(hud)
	hud.pause_pressed.connect(_toggle_pause)
	hud.menu_choice.connect(_on_menu_choice)
	_make_audio()
	_play_music("music_beth")


# ---------------------------------------------------------------- the world

func _make_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/night_sky.gdshader")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.1, 0.25)
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# cool moonlight with shadows
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.72, 0.76, 0.98)
	moon.light_energy = 0.75
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(150.0), 0.0)
	add_child(moon)
	# the warm light of the Star from over the hill
	var star := DirectionalLight3D.new()
	star.light_color = Color(1.0, 0.85, 0.6)
	star.light_energy = 0.35
	star.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-70.0), 0.0)
	add_child(star)
	sm.set_shader_parameter("star_dir", -star.global_transform.basis.z * -1.0)
	sm.set_shader_parameter("moon_dir", moon.global_transform.basis.z)


func _make_hills() -> void:
	# dark rolling hills all the way round the horizon, so the world has depth
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(-120, 0, 30)
	var segs := 160
	var noise := FastNoiseLite.new()
	noise.frequency = 0.8
	for ring in [[480.0, 40.0, Color(0.06, 0.07, 0.13)], [720.0, 85.0, Color(0.04, 0.045, 0.1)]]:
		var rad: float = ring[0]
		var hmax: float = ring[1]
		var col: Color = ring[2]
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var h0 := hmax * (0.35 + 0.65 * absf(noise.get_noise_1d(a0 * rad * 0.01)))
			var h1 := hmax * (0.35 + 0.65 * absf(noise.get_noise_1d(a1 * rad * 0.01)))
			var b0 := center + Vector3(cos(a0), 0, sin(a0)) * rad + Vector3.DOWN * 5.0
			var b1 := center + Vector3(cos(a1), 0, sin(a1)) * rad + Vector3.DOWN * 5.0
			var t0 := b0 + Vector3.UP * h0 + Vector3(cos(a0), 0, sin(a0)) * 40.0
			var t1 := b1 + Vector3.UP * h1 + Vector3(cos(a1), 0, sin(a1)) * 40.0
			for v in [b0, t0, b1, b1, t0, t1]:
				st.set_color(col)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _make_karts() -> void:
	var others := []
	for i in Game.CHARACTERS.size():
		if i != Game.player_char:
			others.append(i)
	others.shuffle()
	var skill: float = [0.84, 0.93, 1.0][Game.difficulty]
	for slot in KART_COUNT:
		var k := Kart.new()
		add_child(k)
		var ci: int = Game.player_char if slot == PLAYER_SLOT else others[slot % others.size()]
		k.setup(track, ci, slot == PLAYER_SLOT)
		var row := slot / 2
		var lat := -3.2 if slot % 2 == 0 else 3.2
		k.place(0, 8.0 + row * 7.5 + (slot % 2) * 2.5, lat)
		k.ai_lane = lat * 0.6 + randf_range(-1.5, 1.5)
		k.ai_skill = skill * randf_range(0.97, 1.02)
		k.lap_done.connect(_on_lap)
		k.sound.connect(_on_sound)
		karts.append(k)
		if slot == PLAYER_SLOT:
			player = k


# ---------------------------------------------------------------- every frame

func _physics_process(dt: float) -> void:
	if state == "countdown":
		var before := ceili(count_t - 1.0)
		count_t -= dt
		var now := ceili(count_t - 1.0)
		if now != before and now >= 1:
			hud.big(str(now))
			_play_sfx("sfx_count_tick")
		if count_t <= 1.0:
			state = "racing"
			hud.big("GO!")
			_play_sfx("sfx_go")
			for k in karts:
				k.frozen = false
	elif state == "racing" or state == "done":
		race_time += dt
	_read_player_input()
	if autotest:
		_autotest_step()
	for k in karts:
		k.step(dt, race_time)
	_bump_karts()
	if state == "done":
		done_t += dt
		if done_t > 2.5 and not hud.results_shown:
			_show_results()


func _process(dt: float) -> void:
	_follow_camera(dt)
	var order := _standings()
	hud.update_race(player, order.find(player) + 1, race_time, track.laps)
	if engine and engine.playing:
		engine.pitch_scale = 0.55 + clampf(absf(player.speed) / Kart.BASE_TOP, 0.0, 1.4) * 0.75


func _read_player_input() -> void:
	if state == "done" or autotest:
		# the computer drives you over the line and on
		player.is_player = false
		return
	player.in_steer = Input.get_axis("steer_left", "steer_right")
	player.in_brake = Input.is_action_pressed("brake")
	player.in_gas = not player.in_brake    # always on the gas unless braking: easy for kids
	player.in_drift = Input.is_action_pressed("drift")


func _bump_karts() -> void:
	for a in karts.size():
		for b in range(a + 1, karts.size()):
			var ka := karts[a]
			var kb := karts[b]
			var d := Vector2(kb.position.x - ka.position.x, kb.position.z - ka.position.z)
			var l := d.length()
			if l < 1.9 and l > 0.001 and absf(ka.position.y - kb.position.y) < 1.5:
				var nrm := d / l
				var wa := float(kb.stats[3]) / (float(ka.stats[3]) + float(kb.stats[3]))
				var push := (1.9 - l)
				ka.position -= Vector3(nrm.x, 0, nrm.y) * push * wa
				kb.position += Vector3(nrm.x, 0, nrm.y) * push * (1.0 - wa)
				if ka.is_player or kb.is_player:
					_play_sfx("sfx_bump", -6.0)


func _standings() -> Array:
	var order := karts.duplicate()
	order.sort_custom(func(x, y): return x.race_progress > y.race_progress)
	return order


func _follow_camera(dt: float) -> void:
	var f := Vector3(sin(player.move_heading), 0, cos(player.move_heading))
	var want := player.position - f * 6.2 + Vector3.UP * 2.7
	var look := player.position + f * 4.0 + Vector3.UP * 1.1
	var k := clampf(dt * 7.0, 0.0, 1.0)
	cam.position = cam.position.lerp(want, k)
	var g := track.ground_at(player.idx, player.frac, player.lateral) + 1.0
	cam.position.y = maxf(cam.position.y, g)
	cam.look_at(look, Vector3.UP)
	var fov := 72.0 + (9.0 if player.boosting() else 0.0) + clampf(player.speed / Kart.BASE_TOP, 0.0, 1.0) * 4.0
	cam.fov = lerpf(cam.fov, fov, clampf(dt * 4.0, 0.0, 1.0))


func _snap_camera() -> void:
	var f := player.forward()
	cam.position = player.position - f * 6.2 + Vector3.UP * 2.7
	cam.look_at(player.position + f * 4.0 + Vector3.UP * 1.1, Vector3.UP)


# ---------------------------------------------------------------- laps and the finish

func _on_lap(k: Kart) -> void:
	if k != player:
		return
	if k.finished:
		state = "done"
		_play_sfx("sfx_finish")
		var place := _standings().find(player) + 1
		hud.big("FINISH!")
		if engine:
			engine.stop()
		if place <= 3:
			_play_music("music_results")
		if Game.best_time < 0.0 or race_time < Game.best_time:
			Game.best_time = race_time
			Game.save()
	elif k.laps_done == track.laps - 1:
		hud.big("FINAL LAP!")
		_play_sfx("sfx_final_lap")
		if not final_lap_played:
			final_lap_played = true
			_play_music("music_finallap")
	else:
		hud.big("LAP %d" % (k.laps_done + 1))
		_play_sfx("sfx_lap")


func _show_results() -> void:
	var rows := []
	var order := _standings()
	for k: Kart in order:
		var t := k.finish_time
		if not k.finished:
			# not over the line yet: guess from how far they still have to go
			var left := track.length * track.laps - k.race_progress
			t = race_time + left / maxf(k.top_speed() * 0.85, 1.0)
		rows.append({"name": k.display_name, "time": t, "you": k == player})
	rows.sort_custom(func(x, y): return x["time"] < y["time"])
	hud.show_results(rows, Game.best_time)
	_play_sfx("sfx_win")


func _toggle_pause() -> void:
	if hud.results_shown:
		return
	get_tree().paused = not get_tree().paused
	hud.show_pause(get_tree().paused)


func _on_menu_choice(choice: String) -> void:
	get_tree().paused = false
	match choice:
		"resume":
			hud.show_pause(false)
		"again":
			finished_race.emit(false)
		"menu":
			finished_race.emit(true)


# ---------------------------------------------------------------- sound

func _make_audio() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -6.0
	add_child(music)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	var es := load("res://sfx/kart_engine_top_speed.wav") as AudioStreamWAV
	if es:
		es = es.duplicate()
		es.loop_mode = AudioStreamWAV.LOOP_FORWARD
		es.loop_begin = 0
		es.loop_end = int(es.get_length() * es.mix_rate)
		engine = AudioStreamPlayer.new()
		engine.stream = es
		engine.volume_db = -16.0
		add_child(engine)
		engine.play()


func _play_music(song: String) -> void:
	var s := load("res://music/%s.mp3" % song) as AudioStreamMP3
	if s == null:
		return
	s = s.duplicate()
	s.loop = song != "music_results"
	music.stream = s
	music.play()


func _play_sfx(snd: String, vol := 0.0) -> void:
	if not _sfx_cache.has(snd):
		_sfx_cache[snd] = load("res://sfx/%s.wav" % snd)
	var s: AudioStream = _sfx_cache[snd]
	if s == null:
		return
	for p in _sfx:
		if not p.playing:
			p.stream = s
			p.volume_db = vol
			p.play()
			return


func _on_sound(k: Kart, what: String) -> void:
	if k.is_player or k.position.distance_to(player.position) < 20.0:
		var map := {"bump": "sfx_bump", "land": "sfx_land", "boost_pad": "sfx_boost_pad", "bounce": "sfx_bounce",
			"mini_turbo": "sfx_mini_turbo", "super_turbo": "sfx_super_turbo"}
		_play_sfx(map.get(what, "sfx_bump"), 0.0 if k.is_player else -10.0)


# ---------------------------------------------------------------- build-machine check

func _autotest_step() -> void:
	player.is_player = false
	player.ai_skill = 1.0
	for t in [3.0, 12.0, 30.0, 60.0]:
		if race_time >= t and not _shots_taken.has(t):
			_shots_taken[t] = true
			_autotest_shot("race_%02d" % int(t))
			print("AUTOTEST t=%.0f lap=%d place=%d speed=%.1f lateral=%.1f y=%.1f" % [race_time, player.laps_done, _standings().find(player) + 1, player.speed, player.lateral, player.position.y])
	if hud.results_shown and not _shots_taken.has("results"):
		_shots_taken["results"] = true
		_autotest_shot("results")
		for k in _standings():
			print("AUTOTEST result %s laps=%d finished=%s time=%.1f" % [k.display_name, k.laps_done, k.finished, k.finish_time])
		print("AUTOTEST race time %.1f" % race_time)
		_autotest_finish.call_deferred()
	if race_time > 600.0:
		print("AUTOTEST FAIL race did not finish in 10 minutes; player lap %d progress %.0f" % [player.laps_done, player.race_progress])
		get_tree().quit(1)


func _autotest_shot(tag: String) -> void:
	var dir := OS.get_environment("KK_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [dir, tag])


func _autotest_finish() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	print("AUTOTEST OK")
	get_tree().quit(0)
