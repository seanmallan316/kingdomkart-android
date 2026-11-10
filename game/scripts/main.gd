extends Node
## The front of the game: the opening cutscene, the title screen, the start menu (Story Mode, Grand Prix,
## Single Race, Time Trial, Options), character select, the Story Mode scenes, and switching to a race.

var _ui: Control                  # whatever menu screen is showing
var _race: Race
var _stage: Node3D
var _turntable: Node3D
var _shown: Node3D
var _logo: Node3D
var _video: VideoStreamPlayer
var _name_label: Label
var _stats_label: Label
var _music: AudioStreamPlayer
var _click: AudioStreamPlayer
var _screen := ""
var _story_page := 0
var _story_text: Label
var _song_name := ""
var _last_tap_ms := -1000

const STORY := [
	["Chapter 1", "The Road to Bethlehem"],
	["Long ago, Joseph and Mary travelled to Bethlehem, the city of David.", "Luke 2:4-5"],
	["There was no room for them in the inn, so baby Jesus was laid in a manger.", "Luke 2:7"],
	["That night a great Star shone over Bethlehem, and angels sang to the shepherds!", "Luke 2:9-14"],
	["Race through Bethlehem under the Star and bring the good news to everyone!", "Tap to race"],
]


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://sfx/sfx_menu_ok.wav")
	add_child(_click)
	if OS.get_environment("KK_AUTOTEST") != "":
		_autotest.call_deferred()
	else:
		_play_opener()


func _process(dt: float) -> void:
	if _turntable:
		_turntable.rotation.y += dt * 0.6
	if _logo:
		_logo.rotation.y = sin(Time.get_ticks_msec() * 0.0008) * 0.18


func _song(file: String) -> void:
	if _song_name == file and _music.playing:
		return
	var s := load("res://music/%s.mp3" % file) as AudioStreamMP3
	if s == null:
		return
	_song_name = file
	s = s.duplicate()
	s.loop = true
	_music.stream = s
	_music.play()


func _clear() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
	_name_label = null
	_stats_label = null
	_story_text = null


# ---------------------------------------------------------------- opening cutscene

func _play_opener() -> void:
	_screen = "opener"
	_video = VideoStreamPlayer.new()
	_video.stream = load("res://video/opener.ogv")
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	add_child(_video)
	_video.finished.connect(_end_opener)
	_video.play()
	var skip := _label_at(_video, "Tap to skip", 34, Control.PRESET_BOTTOM_RIGHT)
	skip.position += Vector2(-30, -20)
	skip.modulate.a = 0.7


func _end_opener() -> void:
	if _video:
		_video.queue_free()
		_video = null
	_open_title()


# ---------------------------------------------------------------- title screen

func _open_title() -> void:
	_clear()
	_screen = "title"
	_song("music_menu")
	if _stage == null:
		_build_stage()
	_show_character(Game.player_char)
	_make_logo()
	_ui = _full_rect()
	var tap := _label_at(_ui, "TAP TO START", 64, Control.PRESET_CENTER_BOTTOM)
	tap.position.y -= 70
	var tw := tap.create_tween().set_loops()
	tw.tween_property(tap, "modulate:a", 0.25, 0.7)
	tw.tween_property(tap, "modulate:a", 1.0, 0.7)


func _make_logo() -> void:
	# the title in solid 3D gold letters floating over the stage
	if _logo:
		_logo.queue_free()
	_logo = Node3D.new()
	_logo.position = Vector3(0, 2.85, 0.6)
	_stage.add_child(_logo)
	var font := load("res://fonts/Poppins-Bold.ttf") as Font
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.3); gold.metallic = 0.85; gold.roughness = 0.22
	gold.emission_enabled = true; gold.emission = Color(0.9, 0.55, 0.15); gold.emission_energy_multiplier = 0.6
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 1.0); white.metallic = 0.3; white.roughness = 0.3
	white.emission_enabled = true; white.emission = Color(0.6, 0.7, 1.0); white.emission_energy_multiplier = 0.4
	for spec in [["KINGDOM KART", 0.0, 0.0092, gold, 0.18], ["ROAD TO GLORY", -0.5, 0.005, white, 0.08]]:
		var mi := MeshInstance3D.new()
		var tm := TextMesh.new()
		tm.text = spec[0]; tm.font = font; tm.font_size = 96; tm.pixel_size = spec[2]; tm.depth = spec[4]
		mi.mesh = tm
		mi.material_override = spec[3]
		mi.position.y = spec[1]
		_logo.add_child(mi)


func _leave_title() -> void:
	if _logo:
		_logo.queue_free()
		_logo = null
	_click.play()
	_open_start_menu()


func _unhandled_input(e: InputEvent) -> void:
	var tapped := (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) \
		or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) \
		or e.is_action_pressed("ui_accept") or e.is_action_pressed("accelerate")
	if tapped:
		# one finger tap arrives as a touch and as a click: only count it once
		var now := Time.get_ticks_msec()
		if now - _last_tap_ms < 250:
			return
		_last_tap_ms = now
	if _screen == "opener" and tapped:
		_video.stop()
		_end_opener()
	elif _screen == "title" and tapped:
		_leave_title()
	elif _screen == "story" and tapped:
		_story_next()
	elif _screen == "select":
		if e.is_action_pressed("steer_left"):
			_pick(-1)
		elif e.is_action_pressed("steer_right"):
			_pick(1)


# ---------------------------------------------------------------- start menu

func _open_start_menu() -> void:
	_clear()
	_screen = "start"
	_show_character(Game.player_char)
	_ui = _full_rect()
	var title := _label_at(_ui, "KINGDOM KART", 96, Control.PRESET_CENTER_TOP)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	title.position.y += 20
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(90, 230)
	_ui.add_child(box)
	var first := _menu_button(box, "Story Mode", func(): _choose_mode("story"))
	_menu_button(box, "Grand Prix", func(): _coming_soon("More roads are on the way for the Grand Prix cups!"))
	_menu_button(box, "Single Race", func(): _choose_mode("single"))
	_menu_button(box, "Time Trial", func(): _choose_mode("time"))
	_menu_button(box, "Options", _open_options)
	first.grab_focus()


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(620, 120)
	b.add_theme_font_size_override("font_size", 56)
	b.pressed.connect(func(): _click.play(); action.call())
	parent.add_child(b)
	return b


func _coming_soon(msg: String) -> void:
	var l := _label_at(_ui, msg, 40, Control.PRESET_CENTER_BOTTOM)
	l.position.y -= 60
	var tw := l.create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(l.queue_free)


func _choose_mode(m: String) -> void:
	Game.mode = m
	_open_select()


func _open_options() -> void:
	_clear()
	_screen = "options"
	_ui = _full_rect()
	var head := _label_at(_ui, "OPTIONS", 96, Control.PRESET_CENTER_TOP)
	head.position.y += 20
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(90, 260)
	_ui.add_child(box)
	var diff := _menu_button(box, "", func(): pass)
	diff.text = "Computer racers: " + ["Easy", "Normal", "Hard"][Game.difficulty]
	diff.pressed.connect(func():
		Game.difficulty = (Game.difficulty + 1) % 3
		diff.text = "Computer racers: " + ["Easy", "Normal", "Hard"][Game.difficulty]
		Game.save())
	var bus := AudioServer.get_bus_index("Master")
	var snd := _menu_button(box, "", func(): pass)
	snd.text = "Sound: " + ("Off" if AudioServer.is_bus_mute(bus) else "On")
	snd.pressed.connect(func():
		AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))
		snd.text = "Sound: " + ("Off" if AudioServer.is_bus_mute(bus) else "On"))
	var back := _menu_button(box, "Back", _open_start_menu)
	back.grab_focus()


# ---------------------------------------------------------------- character select

func _open_select() -> void:
	_clear()
	_screen = "select"
	_song("music_select")
	_ui = _full_rect()
	var heading := {"story": "STORY MODE", "single": "SINGLE RACE", "time": "TIME TRIAL"}
	var head := _label_at(_ui, heading.get(Game.mode, "RACE"), 80, Control.PRESET_CENTER_TOP)
	head.position.y += 20
	var sub := _label_at(_ui, "Choose your character", 40, Control.PRESET_CENTER_TOP)
	sub.position.y += 130
	var prev := _arrow("<", Control.PRESET_CENTER_LEFT, -1)
	prev.position.x = 60
	var next := _arrow(">", Control.PRESET_CENTER_RIGHT, 1)
	next.position.x -= 60
	_name_label = _label_at(_ui, "", 80, Control.PRESET_CENTER_BOTTOM)
	_name_label.position.y -= 300
	_stats_label = _label_at(_ui, "", 34, Control.PRESET_CENTER_BOTTOM)
	_stats_label.position.y -= 220
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.position.y -= 170
	_ui.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(320, 130)
	back.add_theme_font_size_override("font_size", 50)
	back.pressed.connect(func(): _click.play(); _open_start_menu())
	row.add_child(back)
	var go := Button.new()
	go.text = "RACE!" if Game.mode != "story" else "START STORY"
	go.custom_minimum_size = Vector2(560, 130)
	go.add_theme_font_size_override("font_size", 64)
	go.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	go.pressed.connect(_go)
	row.add_child(go)
	var best := _label_at(_ui, "Bethlehem Road best: %s" % Game.format_time(Game.best_time), 30, Control.PRESET_BOTTOM_LEFT)
	best.position += Vector2(30, -20)
	_refresh()
	go.grab_focus()


func _arrow(text: String, preset: Control.LayoutPreset, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 160)
	b.add_theme_font_size_override("font_size", 90)
	_ui.add_child(b)
	b.set_anchors_and_offsets_preset(preset)
	b.pressed.connect(func(): _pick(dir))
	return b


func _pick(dir: int) -> void:
	Game.player_char = wrapi(Game.player_char + dir, 0, Game.CHARACTERS.size())
	_click.play()
	_refresh()


func _refresh() -> void:
	var c: Dictionary = Game.CHARACTERS[Game.player_char]
	if _name_label:
		_name_label.text = c["name"]
	var st: Array = c["stats"]
	if _stats_label:
		_stats_label.text = "Speed %s   Start %s   Turning %s   Weight %s" % [_stars(st[0]), _stars(st[1]), _stars(st[2]), _stars(st[3])]
	_show_character(Game.player_char)


func _stars(v: float) -> String:
	var n := clampi(int(round((v - 0.85) / 0.06)) + 1, 1, 5)
	return "%d/5" % n


func _go() -> void:
	_click.play()
	Game.save()
	if Game.mode == "story":
		_open_story()
	else:
		_start_race()


# ---------------------------------------------------------------- story mode scenes

func _open_story() -> void:
	_clear()
	_screen = "story"
	_story_page = 0
	_ui = _full_rect()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.08, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -330
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	_story_text = _label_at(_ui, "", 50, Control.PRESET_CENTER_BOTTOM)
	_story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_text.custom_minimum_size = Vector2(1500, 0)
	_story_text.position.y -= 90
	_story_show()


func _story_show() -> void:
	var page: Array = STORY[_story_page]
	_story_text.text = "%s\n%s" % [page[0], page[1]]
	_story_text.modulate.a = 0.0
	_story_text.create_tween().tween_property(_story_text, "modulate:a", 1.0, 0.5)


func _story_next() -> void:
	_click.play()
	_story_page += 1
	if _story_page >= STORY.size():
		_start_race()
	else:
		_story_show()


# ---------------------------------------------------------------- the 3D stage behind the menus

func _build_stage() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/night_sky.gdshader")
	sm.set_shader_parameter("star_dir", Vector3(0.35, 0.5, -1.0))
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.65)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	_stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.5, 0.65, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 8.0
	rim.position = Vector3(-2.5, 2.5, -2.5)
	_stage.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4; cm.bottom_radius = 2.6; cm.height = 0.3
	floor_mi.mesh = cm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.3); gold.metallic = 0.85; gold.roughness = 0.25
	floor_mi.material_override = gold
	floor_mi.position.y = -0.15
	_stage.add_child(floor_mi)
	_turntable = Node3D.new()
	_stage.add_child(_turntable)
	var cam := Camera3D.new()
	cam.fov = 38
	cam.position = Vector3(0, 2.1, 8.2)
	_stage.add_child(cam)
	cam.look_at(Vector3(0, 0.85, 0))
	cam.current = true


func _show_character(i: int) -> void:
	if _turntable == null:
		return
	if _shown:
		_shown.queue_free()
	_shown = Game.char_scene(i).instantiate() as Node3D
	_turntable.add_child(_shown)


func _full_rect() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


func _label_at(parent: Control, text: String, size: int, preset: Control.LayoutPreset) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.22))
	l.add_theme_constant_override("outline_size", maxi(8, size / 6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]:
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	elif preset in [Control.PRESET_BOTTOM_RIGHT, Control.PRESET_TOP_RIGHT]:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return l


# ---------------------------------------------------------------- races

func _start_race() -> void:
	_clear()
	_screen = "race"
	_music.stop()
	_song_name = ""
	if _stage:
		_stage.queue_free()
	_stage = null; _turntable = null; _shown = null; _logo = null
	_race = Race.new()
	_race.finished_race.connect(_on_race_over)
	add_child(_race)


func _on_race_over(go_menu: bool) -> void:
	_race.queue_free()
	_race = null
	if go_menu:
		_build_stage.call_deferred()
		_open_start_menu.call_deferred()
	else:
		_start_race.call_deferred()


# ---------------------------------------------------------------- build-machine check

## Plays the opener, the title, the start menu, Story Mode's scenes, character select, then races one whole
## race with the computer driving for you, printing what happens and saving pictures, then quits.
func _autotest() -> void:
	_play_opener()
	await get_tree().create_timer(2.0).timeout
	await _shot("opener")
	await get_tree().create_timer(0.3).timeout
	_unhandled_input(_tap())
	print("AUTOTEST title up")
	await _shot("title")
	await get_tree().create_timer(0.3).timeout
	_unhandled_input(_tap())
	print("AUTOTEST start menu up")
	await _shot("start_menu")
	_choose_mode("story")
	for i in Game.CHARACTERS.size():
		_pick(1)
		await get_tree().process_frame
	print("AUTOTEST characters ok")
	await _shot("select")
	_go()
	await _shot("story")
	for i in STORY.size():
		await get_tree().create_timer(0.3).timeout
		_unhandled_input(_tap())
	print("AUTOTEST story ok")
	Engine.time_scale = float(OS.get_environment("KK_SPEED")) if OS.get_environment("KK_SPEED") != "" else 1.0
	while _race == null:
		await get_tree().process_frame
	_race.autotest = true


func _tap() -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	return t


func _shot(tag: String) -> void:
	var dir := OS.get_environment("KK_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [dir, tag])
		print("AUTOTEST shot ", tag)
