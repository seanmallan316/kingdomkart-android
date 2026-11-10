extends Node
## Shared game state: the characters, who you picked, settings, and the controls.

# name, model file, portrait, stats [top speed, acceleration, handling, weight] (same balance as the Wii U game)
const CHARACTERS := [
	{"name": "Jesus", "model": "jesus", "stats": [1.01, 1.00, 1.01, 1.00], "color": Color(0.98, 0.95, 0.80)},
	{"name": "Moses", "model": "moses", "stats": [1.04, 0.92, 0.94, 1.15], "color": Color(0.35, 0.55, 0.95)},
	{"name": "David", "model": "david", "stats": [0.97, 1.05, 1.06, 0.88], "color": Color(0.80, 0.60, 0.30)},
	{"name": "Esther", "model": "esther", "stats": [0.99, 0.98, 1.08, 0.92], "color": Color(0.62, 0.35, 0.80)},
	{"name": "Peter", "model": "peter", "stats": [1.01, 0.97, 0.96, 1.10], "color": Color(0.25, 0.45, 0.75)},
	{"name": "Mary", "model": "mary", "stats": [0.96, 1.06, 1.05, 0.90], "color": Color(0.60, 0.80, 0.98)},
	{"name": "Daniel", "model": "daniel", "stats": [1.03, 0.94, 1.00, 1.05], "color": Color(0.92, 0.75, 0.25)},
]

var player_char := 0
var mode := "single"       # "story", "single" or "time" (time trial)
var difficulty := 1        # 0 easy, 1 normal, 2 hard
var best_time := -1.0

const SAVE_PATH := "user://save.cfg"


func _ready() -> void:
	_setup_inputs()
	_load()


func char_scene(i: int) -> PackedScene:
	return load("res://models/%s.glb" % CHARACTERS[i]["model"]) as PackedScene



func _add_key(action: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new(); e.button_index = b; InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new(); e.axis = a[0]; e.axis_value = a[1]; InputMap.action_add_event(action, e)


func _setup_inputs() -> void:
	# Phone screen buttons press these too; a Bluetooth controller works without any setup.
	_add_key("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_key("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_key("accelerate", [KEY_W, KEY_UP], [JOY_BUTTON_A])
	_add_key("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_B])
	_add_key("drift", [KEY_SHIFT, KEY_SPACE], [JOY_BUTTON_RIGHT_SHOULDER], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_key("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_add_key("use_item", [KEY_E, KEY_Q], [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("game", "player_char", player_char)
	c.set_value("game", "difficulty", difficulty)
	c.set_value("records", "beth", best_time)
	c.save(SAVE_PATH)


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) == OK:
		player_char = clampi(int(c.get_value("game", "player_char", 0)), 0, CHARACTERS.size() - 1)
		difficulty = clampi(int(c.get_value("game", "difficulty", 1)), 0, 2)
		best_time = float(c.get_value("records", "beth", -1.0))


static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]
