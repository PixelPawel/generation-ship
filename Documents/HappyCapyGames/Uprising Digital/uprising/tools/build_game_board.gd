@tool
extends EditorScript

## Manual, on-demand alternative to game_board_setup.gd's automatic
## @tool _ready() build - use this if opening GameBoard.tscn shows an
## empty viewport (the automatic build depends on _ready() firing
## correctly and the CardDatabase/ModelManifest autoloads already being
## live in the editor, which isn't always reliable, e.g. right after
## project.godot gained new autoload entries without a project reload).
##
## HOW TO RUN THIS (Godot's standard EditorScript workflow):
##   1. Open scenes/GameBoard.tscn (double-click it in the FileSystem dock)
##      so it's the active scene tab.
##   2. Open this file (tools/build_game_board.gd) in the Script editor
##      (double-click it in the FileSystem dock).
##   3. With this script's tab focused in the Script editor, run
##      File > Run (or the toolbar's Run icon / Ctrl+Shift+X).
##   4. Check the Output panel at the bottom for what happened.
##   5. If it says "Board built...", press Ctrl+S to save the scene -
##      the generated Hexes/Pieces/Standees nodes are now real, permanent,
##      selectable/draggable scene content (game_board_setup.gd's own
##      _ready() guard means it won't rebuild over your edits afterward).

func _run() -> void:
	var scene_root: Node = get_scene()
	if scene_root == null:
		push_error("No scene is open. Open scenes/GameBoard.tscn first (double-click it in the FileSystem dock), THEN run this script again.")
		return
	if not scene_root.has_method("_build"):
		push_error("The currently open scene's root doesn't look like GameBoard.tscn (no _build() method on its script). Make sure GameBoard.tscn's tab is the active/focused scene, not some other scene.")
		return
	if scene_root.has_node("Hexes"):
		push_warning("This scene already has a 'Hexes' node - nothing to build. If you want a clean rebuild, delete the Hexes/Pieces/Standees nodes by hand first, then run this again.")
		return

	var card_db: Node = scene_root.get_node_or_null("/root/CardDatabase")
	if card_db == null:
		push_error("CardDatabase autoload isn't available to the editor right now. This usually means Godot hasn't picked up a project.godot change yet - try Project > Reload Current Project from the menu, then run this script again.")
		return

	scene_root.call("_build")

	if scene_root.has_node("Hexes"):
		var hex_count: int = scene_root.get_node("Hexes").get_child_count()
		print("Board built: %d hexes. Press Ctrl+S now to save the scene, or the next reload will lose this." % hex_count)
	else:
		push_error("_build() ran but no 'Hexes' node appeared - something failed partway through. Check the errors above this line in the Output panel.")
