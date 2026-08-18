extends Node
## MENUS KEEP THEIR SHAPE. A Label with a long line asks its container
## for as much width as the line needs, and the container gives it --
## which is how one sentence stretches a pause menu across the screen.
##
## This watches every Control the game ever builds and tells the text to
## wrap instead of push: labels wrap on word boundaries and clip what
## still will not fit, buttons clip their captions. It runs once per
## node as it enters the tree, so it covers menus that do not exist yet
## as well as the fifty that already do.

func _ready() -> void:
	get_tree().node_added.connect(_on_added)

func _on_added(n: Node) -> void:
	if n is Label:
		var l: Label = n
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.clip_text = true
	elif n is Button:
		var b: Button = n
		b.clip_text = true
		if b.autowrap_mode == TextServer.AUTOWRAP_OFF:
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif n is RichTextLabel:
		# rich text already wraps; stop it demanding width for its
		# longest unbroken line
		(n as RichTextLabel).fit_content = false
