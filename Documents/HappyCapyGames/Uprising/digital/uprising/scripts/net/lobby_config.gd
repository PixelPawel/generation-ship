extends Node
## Autoload. Godot's change_scene_to_file() doesn't pass arguments, so this
## is the simplest bridge for a project this size: the Lobby scene fills
## these in and calls change_scene_to_file("res://scenes/game_board.tscn"),
## which reads them back in _ready().
##
## `configured` starts false and the other fields hold a small 2-player
## local-test default -- so launching scenes/game_board.tscn directly
## (dev iteration, tools/screenshot_scene.gd, game_board_flow_test.gd) keeps
## auto-hosting that same test game exactly like before the Lobby existed,
## without needing to go through the Lobby at all.

var configured: bool = false

var is_host: bool = true
var faction_hero_pairs: Array = [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
var difficulty: String = "Veteran"
var max_chapters: int = 3
var port: int = NetworkManager.DEFAULT_PORT

var join_address: String = "127.0.0.1"
var join_port: int = NetworkManager.DEFAULT_PORT
