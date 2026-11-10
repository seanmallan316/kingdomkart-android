extends Node
## The title and character select screen, and switching between the menu and a race.

var _menu: Control
var _race: Race
var _stage: Node3D
var _turntable: Node3D
var _shown: Node3D
var _name_label: Label
var _stats_label: Label
var _diff_button: Button
var _music: AudioStreamPlayer
var _click: AudioStreamPlayer


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://sfx/sfx_menu_ok.wav")
	add_child(_click)
	_open_menu()
	if OS.get_environment("KK_AUTOTEST") != "":
		_autotest.call_deferred()


## Build-machine check: shows the menu, flips through every character, then races one whole race with the
## computer driving for you, printing what happens and saving pictures, then quits.
func _autotest() -> void:
	print("AUTOTEST menu up")
	await _shot("menu")
	for i in Game.CHARACTERS.size():
		_pick(1)
		await get_tree().process_frame
	print("AUTOTEST characters ok")
	Engine.time_scale = float(OS.get_environment("KK_SPEED")) if OS.get_environment("KK_SPEED") != "" else 1.0
	_start_race()
	_race.autotest = true


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


func _process(dt: float) -> void:
	if _turntable:
		_turntable.rotation.y += dt * 0.6


# ---------------------------------------------------------------- menu

func _open_menu() -> void:
	var s := load("res://music/music_select.mp3") as AudioStreamMP3
	if s:
		s = s.duplicate(); s.loop = true
		_music.stream = s; _music.play()
	_build_stage()
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var title := Label.new()
	title.text = "KINGDOM KART"
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.3))
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 20
	_menu.add_child(title)
	var sub := Label.new()
	sub.text = "ROAD TO GLORY"
	sub.add_theme_font_size_override("font_size", 52)
	sub.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	sub.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.25))
	sub.add_theme_constant_override("outline_size", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y = 170
	_menu.add_child(sub)

	# choose your character: arrows either side of the spinning 3D model
	var prev := _big_button("<", Vector2(120, 160))
	prev.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	prev.position.x = 60
	prev.pressed.connect(func(): _pick(-1))
	var next := _big_button(">", Vector2(120, 160))
	next.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	next.position.x -= 60
	next.pressed.connect(func(): _pick(1))

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 80)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.2))
	_name_label.add_theme_constant_override("outline_size", 16)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_label.position.y -= 300
	_menu.add_child(_name_label)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 34)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_stats_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.2))
	_stats_label.add_theme_constant_override("outline_size", 8)
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stats_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats_label.position.y -= 220
	_menu.add_child(_stats_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.position.y -= 170
	_menu.add_child(row)
	_diff_button = Button.new()
	_diff_button.custom_minimum_size = Vector2(420, 130)
	_diff_button.add_theme_font_size_override("font_size", 46)
	_diff_button.pressed.connect(_cycle_difficulty)
	row.add_child(_diff_button)
	var go := Button.new()
	go.text = "RACE!"
	go.custom_minimum_size = Vector2(520, 130)
	go.add_theme_font_size_override("font_size", 70)
	go.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	go.pressed.connect(_start_race)
	row.add_child(go)
	var best := Label.new()
	best.text = "Bethlehem Road best: %s" % Game.format_time(Game.best_time)
	best.add_theme_font_size_override("font_size", 30)
	best.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	best.position += Vector2(30, -20)
	_menu.add_child(best)
	_refresh()
	go.grab_focus()


func _big_button(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 90)
	_menu.add_child(b)
	return b


func _build_stage() -> void:
	# a little 3D stage under the night sky for the character to spin on
	_stage = Node3D.new()
	add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/night_sky.gdshader")
	sm.set_shader_parameter("star_dir", Vector3(0.0, 0.45, -1.0))
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
	cam.fov = 40
	cam.position = Vector3(0, 1.9, 6.2)
	_stage.add_child(cam)
	cam.look_at(Vector3(0, 0.75, 0))
	cam.current = true


func _pick(dir: int) -> void:
	Game.player_char = wrapi(Game.player_char + dir, 0, Game.CHARACTERS.size())
	_click.play()
	_refresh()


func _cycle_difficulty() -> void:
	Game.difficulty = (Game.difficulty + 1) % 3
	_click.play()
	_refresh()


func _refresh() -> void:
	var c: Dictionary = Game.CHARACTERS[Game.player_char]
	_name_label.text = c["name"]
	var st: Array = c["stats"]
	_stats_label.text = "Speed %s   Start %s   Turning %s   Weight %s" % [_stars(st[0]), _stars(st[1]), _stars(st[2]), _stars(st[3])]
	_diff_button.text = ["Easy", "Normal", "Hard"][Game.difficulty]
	if _shown:
		_shown.queue_free()
	_shown = Game.char_scene(Game.player_char).instantiate() as Node3D
	_turntable.add_child(_shown)


func _stars(v: float) -> String:
	var n := clampi(int(round((v - 0.85) / 0.06)) + 1, 1, 5)
	return "%d/5" % n


func _unhandled_input(e: InputEvent) -> void:
	if _menu == null:
		return
	if e.is_action_pressed("steer_left"):
		_pick(-1)
	elif e.is_action_pressed("steer_right"):
		_pick(1)


# ---------------------------------------------------------------- race

func _start_race() -> void:
	_click.play()
	Game.save()
	_music.stop()
	_menu.queue_free(); _menu = null
	_stage.queue_free(); _stage = null; _turntable = null; _shown = null
	_race = Race.new()
	_race.finished_race.connect(_on_race_over)
	add_child(_race)


func _on_race_over(go_menu: bool) -> void:
	_race.queue_free()
	_race = null
	if go_menu:
		_open_menu()
	else:
		_start_race_again.call_deferred()


func _start_race_again() -> void:
	_race = Race.new()
	_race.finished_race.connect(_on_race_over)
	add_child(_race)
