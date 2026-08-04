extends Node
## Autoload "Settings". Global options tweaked from title or pause menu.
## Persisted to user://settings.cfg (username included).

const CFG_PATH := "user://settings.cfg"

var mouse_sensitivity: float = 1.0
var fullscreen: bool = true      # game launches fullscreen (project setting)
var fov: float = 90.0
var username: String = ""        # multiplayer display name
var epilepsy_seen: bool = false  # 'don't show again' on the photosensitivity note

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		mouse_sensitivity = float(cf.get_value("opts", "sens", mouse_sensitivity))
		fov = float(cf.get_value("opts", "fov", fov))
		username = str(cf.get_value("opts", "username", ""))
		epilepsy_seen = bool(cf.get_value("opts", "epilepsy_seen", false))
		var fs := bool(cf.get_value("opts", "fullscreen", fullscreen))
		if fs != fullscreen:
			apply_fullscreen(fs)

func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("opts", "sens", mouse_sensitivity)
	cf.set_value("opts", "fov", fov)
	cf.set_value("opts", "fullscreen", fullscreen)
	cf.set_value("opts", "username", username)
	cf.set_value("opts", "epilepsy_seen", epilepsy_seen)
	cf.save(CFG_PATH)

func apply_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
