extends Node
## Autoload "Settings". Global options tweaked from title or pause menu.

var mouse_sensitivity: float = 1.0
var fullscreen: bool = true      # game launches fullscreen (project setting)
var fov: float = 90.0

func apply_fullscreen(on: bool) -> void:
	fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
