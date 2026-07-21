extends Node

# Applies GameTheme project-wide once, at startup, so every Control anywhere
# in the game inherits it by default — no scene needs its own explicit
# `theme = GameTheme.get_theme()`, and no standalone button (one with no
# themed ancestor to inherit from) needs an explicit
# GameTheme.apply_to_button() call either.

func _ready() -> void:
	get_tree().root.theme = GameTheme.get_theme()
