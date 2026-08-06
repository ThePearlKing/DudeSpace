extends HBoxContainer
## The eight monolith triangles above the inventory. Gray = untouched;
## a fed monolith paints its slot in its tetrahedron's color.

func refresh() -> void:
	for c in get_children():
		c.queue_free()
	for i in 8:
		var l := Label.new()
		l.text = "▲"
		l.add_theme_font_size_override("font_size", 26)
		l.modulate = Game.MONO_COLORS[i] if Game.monolith_stage > i \
			else Color("#3a3f47")
		add_child(l)
