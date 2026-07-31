class_name Invader
extends Node3D
## A space-invader built from a grid of tough, high-value destructible
## blocks. Floats in deep space (no gravity), so debris drifts and you
## must line up your rocket to smash it. Built in local space.

const PATTERN := [
	"  X     X  ",
	"   X   X   ",
	"  XXXXXXX  ",
	" XX XXX XX ",
	"XXXXXXXXXXX",
	"X XXXXXXX X",
	"X X     X X",
	"   XX XX   ",
]

func build(color: Color) -> void:
	add_to_group("invader")
	var block := 4.0
	var step := 4.4
	var rows := PATTERN.size()
	for r in rows:
		var line: String = PATTERN[r]
		for c in line.length():
			if line[c] != "X":
				continue
			var d := Destructible.new()
			d.setup(Vector3(block, block, block), color, 4, 55, 1.0)
			add_child(d)
			d.position = Vector3(
				(float(c) - float(line.length()) * 0.5) * step,
				(float(rows) * 0.5 - float(r)) * step,
				0.0)
