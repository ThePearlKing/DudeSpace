class_name ClawdeCrab
extends Node3D
## A space invader shaped like a crab of Claude. Its blocks are valuable
## but destroying them ANGERS the noodle gods (Claude is cool). Floats in
## deep space. Built in local space.

const PATTERN := [
	"C   C   C   C",
	" C C     C C ",
	"  CCCCCCCCC  ",
	" CCCCCCCCCCC ",
	"C CCCCCCCCC C",
	"C C       C C",
]

func build() -> void:
	add_to_group("invader")
	var step := 1.6
	var rows := PATTERN.size()
	var claude := Color("#d97757")   # Claude's warm clay colour
	for r in rows:
		var line: String = PATTERN[r]
		for c in line.length():
			if line[c] != "C":
				continue
			var d := Destructible.new()
			# tough, valuable, and each break stokes the gods' wrath
			d.setup(Vector3(1.4, 1.4, 1.4), claude, 3, 30, 1.2, 4.0)
			add_child(d)
			d.position = Vector3(
				(float(c) - float(line.length()) * 0.5) * step,
				(float(rows) * 0.5 - float(r)) * step,
				0.0)
	# no label. the shape says everything.
