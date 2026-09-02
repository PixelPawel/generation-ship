extends Control

## First-pass lobby: Host immediately builds+broadcasts a 2-player Normal
## GameState and moves on to PlayBoard (which itself shows a "waiting for
## opponent" indicator until a second peer connects and gets auto-
## assigned the second faction - see PlayBoard._on_peer_connected). Join
## connects to a host and waits for the initial state broadcast before
## moving on. A real per-player faction-claim UI is a reasonable follow-up,
## not built for this first playable pass (see NetworkManager.assign_faction's
## own doc comment on this same simplification).

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var address_edit: LineEdit = $CenterContainer/VBoxContainer/AddressEdit
@onready var port_edit: LineEdit = $CenterContainer/VBoxContainer/PortEdit
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)


func _on_host_pressed() -> void:
	var port: int = int(port_edit.text) if port_edit.text.is_valid_int() else 8955
	var card_db: Node = get_node("/root/CardDatabase")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)

	var net: Node = get_node("/root/NetworkManager")
	var err: Error = net.host_game(port)
	if err != OK:
		status_label.text = "Failed to host: error %d" % err
		return
	net.assign_faction(1, state.players[0].faction)  # ENet's own peer id for the local/server side is always 1.
	# Bound to the NetworkManager autoload itself, NOT this Lobby node -
	# this scene is about to be freed by change_scene_to_file() below, and
	# a Callable bound to a freed node would silently go invalid right
	# when the game actually needs it (see NetworkManager.default_action_handler's doc comment).
	net.action_handler = Callable(net, "default_action_handler")
	net.set_initial_state(state)

	LobbyConfig.is_host = true
	LobbyConfig.port = port
	get_tree().change_scene_to_file("res://scenes/PlayBoard.tscn")


func _on_join_pressed() -> void:
	var port: int = int(port_edit.text) if port_edit.text.is_valid_int() else 8955
	var address: String = address_edit.text if not address_edit.text.is_empty() else "127.0.0.1"
	var net: Node = get_node("/root/NetworkManager")
	var err: Error = net.join_game(address, port)
	if err != OK:
		status_label.text = "Failed to join: error %d" % err
		return

	LobbyConfig.is_host = false
	LobbyConfig.address = address
	LobbyConfig.port = port
	get_tree().change_scene_to_file("res://scenes/PlayBoard.tscn")
