extends Node
## Autoload "Settings". Global options tweaked from title or pause menu.
## Persisted to user://settings.cfg (username included).

const CFG_PATH := "user://settings.cfg"

var mouse_sensitivity: float = 1.0
var fullscreen: bool = true      # game launches fullscreen (project setting)
var fov: float = 90.0
var username: String = ""        # multiplayer display name
var epilepsy_seen: bool = false  # 'don't show again' on the photosensitivity note
var music_vol: float = 1.0       # background-music volume (0..1)
var sfx_vol: float = 1.0         # sound-effects volume (0..1)
var radio_vol: float = 1.0       # the radio's own fader (RadioFX bus)
var voice_vol: float = 1.0       # spoken voices (humans, studio aliens)

## Every spoken voice routes through a runtime "Voice" bus.
func ensure_voice_bus() -> void:
	if AudioServer.get_bus_index("Voice") == -1:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Voice")
		AudioServer.set_bus_send(bi, "Master")
	apply_voice_vol()

func apply_voice_vol() -> void:
	var bi := AudioServer.get_bus_index("Voice")
	if bi >= 0:
		AudioServer.set_bus_volume_db(bi, linear_to_db(clampf(voice_vol, 0.0005, 1.0)))

## The radio plays through its RadioFX bus -- one knob rules it all.
func apply_radio_vol() -> void:
	var bi := AudioServer.get_bus_index("RadioFX")
	if bi >= 0:
		AudioServer.set_bus_volume_db(bi, linear_to_db(clampf(radio_vol, 0.0005, 1.0)))

## Rebindable keys. Anything not in here keeps its hardcoded default.
const KEY_DEFAULTS := {"interact": KEY_F, "inventory": KEY_E,
	"jetpack": KEY_J, "jet_down": KEY_C, "zoom": KEY_V, "map": KEY_M,
	"calendar": KEY_K, "chat": KEY_T, "pose": KEY_G, "drop": KEY_Q,
	"hyper": KEY_H}
var keys: Dictionary = {}

func key(a: String) -> int:
	return int(keys.get(a, KEY_DEFAULTS.get(a, 0)))

func music_db() -> float:
	return linear_to_db(clampf(music_vol, 0.0005, 1.0))

func sfx_db() -> float:
	return linear_to_db(clampf(sfx_vol, 0.0005, 1.0))

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		mouse_sensitivity = float(cf.get_value("opts", "sens", mouse_sensitivity))
		fov = float(cf.get_value("opts", "fov", fov))
		username = str(cf.get_value("opts", "username", ""))
		epilepsy_seen = bool(cf.get_value("opts", "epilepsy_seen", false))
		music_vol = clampf(float(cf.get_value("opts", "music_vol", 1.0)), 0.0, 1.0)
		sfx_vol = clampf(float(cf.get_value("opts", "sfx_vol", 1.0)), 0.0, 1.0)
		radio_vol = clampf(float(cf.get_value("opts", "radio_vol", 1.0)), 0.0, 1.0)
		voice_vol = clampf(float(cf.get_value("opts", "voice_vol", 1.0)), 0.0, 1.0)
		for a in KEY_DEFAULTS:
			keys[a] = int(cf.get_value("keys", str(a), KEY_DEFAULTS[a]))
		var fs := bool(cf.get_value("opts", "fullscreen", fullscreen))
		if fs != fullscreen:
			apply_fullscreen(fs)
	ensure_voice_bus()

func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("opts", "sens", mouse_sensitivity)
	cf.set_value("opts", "fov", fov)
	cf.set_value("opts", "fullscreen", fullscreen)
	cf.set_value("opts", "username", username)
	cf.set_value("opts", "epilepsy_seen", epilepsy_seen)
	cf.set_value("opts", "music_vol", music_vol)
	cf.set_value("opts", "sfx_vol", sfx_vol)
	cf.set_value("opts", "radio_vol", radio_vol)
	cf.set_value("opts", "voice_vol", voice_vol)
	for a in KEY_DEFAULTS:
		cf.set_value("keys", str(a), key(str(a)))
	cf.save(CFG_PATH)

func apply_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
