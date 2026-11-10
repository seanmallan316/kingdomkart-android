class_name Hud
extends CanvasLayer
## Everything on top of the race picture: place, lap, time, big messages, phone touch buttons,
## the pause menu and the results board.

signal pause_pressed
signal menu_choice(choice: String)

var results_shown := false

var _place: Label
var _lap: Label
var _time: Label
var _big: Label
var _big_tween: Tween
var _pause_panel: Control
var _results: Control
var _touch: Node2D
var _buttons := {}
var _choice_buttons: Array = []
var _last_choice_ms := 0
var _item_icon: TextureRect
var _item_frame: Panel
var _blessing: Label
var _blessing_tween: Tween
var _spin_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_lap = _label(root, 64, Control.PRESET_TOP_LEFT, Vector2(40, 24))
	_time = _label(root, 52, Control.PRESET_TOP_RIGHT, Vector2(-40, 28))
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place = _label(root, 130, Control.PRESET_BOTTOM_RIGHT, Vector2(-60, -40))
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_big = _label(root, 150, Control.PRESET_CENTER, Vector2.ZERO)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.modulate.a = 0.0
	_make_touch()
	_make_item_slot(root)
	get_viewport().size_changed.connect(_layout_touch)
	_layout_touch()


func _label(parent: Control, size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.2))
	l.add_theme_constant_override("outline_size", maxi(8, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	if preset == Control.PRESET_CENTER:
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.grow_vertical = Control.GROW_DIRECTION_BOTH
	elif preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.position += offset
	return l


func big(text: String) -> void:
	_big.text = text
	_big.pivot_offset = _big.size * 0.5
	if _big_tween:
		_big_tween.kill()
	_big.modulate.a = 1.0
	_big.scale = Vector2(1.6, 1.6)
	_big_tween = create_tween()
	_big_tween.tween_property(_big, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_big_tween.tween_interval(0.6)
	_big_tween.tween_property(_big, "modulate:a", 0.0, 0.35)


func _make_item_slot(root: Control) -> void:
	_item_frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.12, 0.55)
	sb.border_color = Color(1.0, 0.82, 0.4)
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(30)
	_item_frame.add_theme_stylebox_override("panel", sb)
	_item_frame.position = Vector2(40, 120)
	_item_frame.size = Vector2(170, 170)
	_item_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_item_frame)
	_item_icon = TextureRect.new()
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.position = Vector2(15, 15)
	_item_icon.size = Vector2(140, 140)
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_frame.add_child(_item_icon)
	_blessing = _label(root, 54, Control.PRESET_CENTER_BOTTOM, Vector2(0, -250))
	_blessing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blessing.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_blessing.modulate.a = 0.0


## The blessing slot spins through the pictures for a moment, then lands on the one you got.
func item_picked() -> void:
	_spin_t = 1.0


func show_blessing(id: String) -> void:
	var b: Dictionary = Items.BLESSINGS[id]
	_blessing.text = "%s  -  %s\n%s" % [b["name"], b["verse"], b["line"]]
	if _blessing_tween:
		_blessing_tween.kill()
	_blessing.modulate.a = 1.0
	_blessing_tween = create_tween()
	_blessing_tween.tween_interval(2.4)
	_blessing_tween.tween_property(_blessing, "modulate:a", 0.0, 0.5)


func update_item(id: String, dt: float) -> void:
	if _spin_t > 0.0:
		_spin_t -= dt
		var ids := Items.BLESSINGS.keys()
		_item_icon.texture = load("res://ui/item_%s.png" % ids[int(Time.get_ticks_msec() / 80) % ids.size()])
		return
	_item_icon.texture = load("res://ui/item_%s.png" % id) if id != "" else null


func update_race(player: Kart, place: int, t: float, laps: int) -> void:
	_lap.text = "LAP %d/%d" % [mini(player.laps_done + 1, laps), laps]
	_time.text = Game.format_time(t)
	var suffix := "th"
	if place == 1: suffix = "st"
	elif place == 2: suffix = "nd"
	elif place == 3: suffix = "rd"
	_place.text = "%d%s" % [place, suffix]
	var gold := Color(1.0, 0.85, 0.3)
	_place.add_theme_color_override("font_color", gold if place <= 3 else Color(1.0, 0.95, 0.8))


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		pause_pressed.emit()


# ---------------------------------------------------------------- touch buttons

## Phone controls, laid out like a game controller with fewer buttons:
## left thumb = steering stick (put your thumb down anywhere on the left side and slide),
## right thumb = big GAS button, with DRIFT right next to it (DRIFT also keeps the gas on, so just roll
## your thumb from GAS onto DRIFT and back), and a smaller BRAKE.
const STICK_RADIUS := 130.0

var _stick_base: Sprite2D
var _stick_knob: Sprite2D
var _stick_home := Vector2.ZERO
var _stick_finger := -1


func _make_touch() -> void:
	_touch = Node2D.new()
	add_child(_touch)
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_stick_base = Sprite2D.new()
	_stick_base.texture = load("res://ui/stick_base.png")
	_touch.add_child(_stick_base)
	_stick_knob = Sprite2D.new()
	_stick_knob.texture = load("res://ui/stick_knob.png")
	_touch.add_child(_stick_knob)
	for spec in [["accelerate", "gas", 150.0], ["drift", "drift", 118.0], ["brake", "brake", 88.0], ["use_item", "item", 88.0]]:
		var b := TouchScreenButton.new()
		b.texture_normal = load("res://ui/btn_%s.png" % spec[1])
		b.texture_pressed = load("res://ui/btn_%s_on.png" % spec[1])
		b.action = spec[0]
		b.passby_press = true          # slide your thumb between buttons without lifting it
		var c := CircleShape2D.new()
		c.radius = spec[2]
		b.shape = c
		_touch.add_child(b)
		_buttons[spec[1]] = b
	var p := TouchScreenButton.new()
	p.texture_normal = load("res://ui/btn_pause.png")
	p.pressed.connect(func(): pause_pressed.emit())
	_touch.add_child(p)
	_buttons["pause"] = p


func _layout_touch() -> void:
	var s := get_viewport().get_visible_rect().size
	var gas := 300.0      # picture sizes
	var drift := 250.0
	var brake := 190.0
	var gas_pos := Vector2(s.x - gas - 50.0, s.y - gas - 40.0)
	_buttons["gas"].position = gas_pos
	# DRIFT sits up and to the left of GAS, touching it, so one thumb rolls between them
	_buttons["drift"].position = gas_pos + Vector2(-drift * 0.55, -drift * 0.70)
	# BRAKE is further left and lower, away from the thumb's resting spot
	_buttons["brake"].position = gas_pos + Vector2(-brake - 150.0, gas - brake + 10.0)
	_buttons["pause"].position = Vector2(s.x * 0.5 - 60.0, 20.0)
	# ITEM sits above BRAKE, left of DRIFT: a short reach for the right thumb
	_buttons["item"].position = gas_pos + Vector2(-brake - 200.0, -drift * 0.62)
	_stick_home = Vector2(80.0 + STICK_RADIUS + 40.0, s.y - STICK_RADIUS - 110.0)
	_reset_stick()
	# keep the place number clear of the buttons on phones
	if _touch.visible:
		_place.position.y = 120.0


func _reset_stick() -> void:
	_stick_finger = -1
	_stick_base.position = _stick_home
	_stick_knob.position = _stick_home
	Input.action_release("steer_left")
	Input.action_release("steer_right")


func _input(e: InputEvent) -> void:
	if (_pause_panel or results_shown) and e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed:
		if _tap_menu((e as InputEventScreenTouch).position):
			get_viewport().set_input_as_handled()
		return
	if not _touch.visible or _pause_panel != null:
		return
	var s := get_viewport().get_visible_rect().size
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and _stick_finger == -1 and t.position.x < s.x * 0.45 and t.position.y > s.y * 0.3:
			# the stick appears under your thumb wherever you put it down on the left side
			_stick_finger = t.index
			_stick_base.position = t.position
			_stick_knob.position = t.position
		elif not t.pressed and t.index == _stick_finger:
			_reset_stick()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _stick_finger:
			var off := (d.position - _stick_base.position).limit_length(STICK_RADIUS)
			_stick_knob.position = _stick_base.position + off
			var x := off.x / STICK_RADIUS
			if absf(x) < 0.12:
				x = 0.0
			x = clampf(x * 1.15, -1.0, 1.0)
			if x < 0.0:
				Input.action_press("steer_left", -x); Input.action_release("steer_right")
			elif x > 0.0:
				Input.action_press("steer_right", x); Input.action_release("steer_left")
			else:
				Input.action_release("steer_left"); Input.action_release("steer_right")


# ---------------------------------------------------------------- pause and results

func _panel(title: String) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.08, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	shade.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 96)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	t.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.2))
	t.add_theme_constant_override("outline_size", 16)
	box.add_child(t)
	return shade


func _button(parent: Control, text: String, choice: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560, 120)
	b.add_theme_font_size_override("font_size", 56)
	b.pressed.connect(func(): _choose(choice))
	parent.add_child(b)
	_choice_buttons.append([b, choice])
	return b


func _choose(choice: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_choice_ms < 400:
		return            # a tap can arrive both as a touch and as a click: act on it once
	_last_choice_ms = now
	menu_choice.emit(choice)


func _tap_menu(pos: Vector2) -> bool:
	for pair in _choice_buttons:
		var b: Button = pair[0]
		if is_instance_valid(b) and b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			_choose(pair[1])
			return true
	return false


func _center(box: VBoxContainer) -> void:
	await get_tree().process_frame
	box.position = (box.get_parent() as Control).size * 0.5 - box.size * 0.5


func show_pause(on: bool) -> void:
	_reset_stick()
	if on and _pause_panel == null:
		_pause_panel = _panel("PAUSED")
		var box := _pause_panel.get_child(0) as VBoxContainer
		var first := _button(box, "Keep Racing", "resume")
		_button(box, "Restart", "again")
		_button(box, "Quit to Menu", "menu")
		_center(box)
		first.grab_focus()
	elif not on and _pause_panel:
		_pause_panel.queue_free()
		_pause_panel = null
		_choice_buttons.clear()
	_touch.visible = not on and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"))


func show_results(rows: Array, best: float, note := "") -> void:
	results_shown = true
	_touch.visible = false
	_results = _panel("RESULTS")
	var box := _results.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation", 8)
	var place := 1
	for r in rows:
		var l := Label.new()
		var you: bool = r["you"]
		l.text = "%d.  %-10s  %s%s" % [place, r["name"], Game.format_time(r["time"]), "   <  YOU" if you else ""]
		l.add_theme_font_size_override("font_size", 48 if you else 40)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if you else Color(0.95, 0.95, 1.0))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		place += 1
	if note != "":
		var n := Label.new()
		n.text = note
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(1300, 0)
		n.add_theme_font_size_override("font_size", 36)
		n.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(n)
	var rec := Label.new()
	rec.text = "Best time on Bethlehem Road: %s" % Game.format_time(best)
	rec.add_theme_font_size_override("font_size", 34)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rec)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	var again := Button.new()
	again.text = "Race Again"
	again.custom_minimum_size = Vector2(440, 110)
	again.add_theme_font_size_override("font_size", 50)
	again.pressed.connect(func(): _choose("again"))
	row.add_child(again)
	_choice_buttons.append([again, "again"])
	var menu := Button.new()
	menu.text = "Menu"
	menu.custom_minimum_size = Vector2(440, 110)
	menu.add_theme_font_size_override("font_size", 50)
	menu.pressed.connect(func(): _choose("menu"))
	row.add_child(menu)
	_choice_buttons.append([menu, "menu"])
	_center(box)
	again.grab_focus()
