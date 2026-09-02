extends Node

## Autoload. Carries config between Lobby and PlayBoard scenes -
## change_scene_to_file() doesn't take arguments, so this is the bridge.

var is_host: bool = false
var address: String = "127.0.0.1"
var port: int = 8955
