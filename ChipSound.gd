class_name ChipSound
extends Node
## THE SOUND CHIP -- placeholder voice while the tracker is being built.
## Real synthesis, modulators, panning and drums land in the next pass;
## this keeps the console audible and the API stable in the meantime.

var song: Dictionary = {}
var sfx_bank: Array = []
var volume: float = 0.7

func load_cart(cart: ArcadeCart) -> void:
	song = cart.song
	sfx_bank = cart.sfx

func play_sfx(_n: int, _chan: int = -1) -> void:
	Sfx.play("click", -22.0)

func play_music(_n: int, _fade: float = 0.0) -> void:
	pass

func play_note(_ch: int, _semi: float, _vol: float, _inst: int = 0) -> void:
	pass
