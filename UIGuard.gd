extends Node
## MENUS FIT THEIR TEXT. A Label or a Button reports a minimum size that
## includes its whole caption, and a container grows to fit that -- which
## is how a panel ends up exactly as wide as the longest line in it.
## Clipping breaks that: the control claims to need almost no room, the
## panel stays small, and the words run out over the edge of it.
##
## So nothing here clips. It undoes clipping wherever it finds it, and
## it keeps centred panels centred as they grow, instead of letting them
## expand off to one side.

func _ready() -> void:
	get_tree().node_added.connect(_on_added)

func _on_added(n: Node) -> void:
	if n is Label:
		var l: Label = n
		l.clip_text = false
		l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	elif n is Button:
		var b: Button = n
		b.clip_text = false
		b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	elif n is PanelContainer or n is MarginContainer:
		# a panel pinned to the middle should stay in the middle when it
		# grows, not walk off to the right
		var c: Control = n
		if c.anchor_left == 0.5 and c.anchor_right == 0.5:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		if c.anchor_top == 0.5 and c.anchor_bottom == 0.5:
			c.grow_vertical = Control.GROW_DIRECTION_BOTH
