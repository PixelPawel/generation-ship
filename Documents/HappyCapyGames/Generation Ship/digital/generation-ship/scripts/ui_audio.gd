extends Node

var _fuse_player: AudioStreamPlayer = null
var _gavel_player: AudioStreamPlayer = null
var _recycle_player: AudioStreamPlayer = null
var _auction_player: AudioStreamPlayer = null
var _shift_change_player: AudioStreamPlayer = null
var _supply_players: Dictionary = {}
var _sfx_players: Dictionary = {}     # cue -> AudioStreamPlayer, see SFX_CUES

# Sound effects made with Stable Audio 3 (2026-11-05; prompts in _Shared/SFX/genship_cues.txt,
# the files in assets/effects/generated/) for moments that were silent, with their volume
# against the older effects. play_sfx(cue) plays one.
const SFX_DIR: String = "res://assets/effects/generated/"
const SFX_CUES: Dictionary = {
	"danger_reveal": -4.0, "danger_solved": -4.0, "mission_complete": -3.0, "mission_failed": -3.0,
	"round_end": -6.0, "game_end": -4.0, "expedition_reveal": -6.0, "tech_draw": -6.0,
	"pass_turn": -6.0, "fully_optimized": -5.0, "shuttle_send": -5.0, "scan_success": -4.0,
	"ui_click": -12.0, "intro_chime": -8.0,
}

func _ready() -> void:
	var fuse_stream: AudioStream = load("res://assets/effects/fuse.wav") as AudioStream
	if fuse_stream:
		_fuse_player = AudioStreamPlayer.new()
		_fuse_player.stream = fuse_stream
		_fuse_player.bus = &"SFX"
		add_child(_fuse_player)

	var gavel_stream: AudioStream = load("res://assets/effects/gavel.wav") as AudioStream
	if gavel_stream:
		_gavel_player = AudioStreamPlayer.new()
		_gavel_player.stream = gavel_stream
		_gavel_player.bus = &"SFX"
		add_child(_gavel_player)

	var recycle_stream: AudioStream = load("res://assets/effects/recycle.wav") as AudioStream
	if recycle_stream:
		_recycle_player = AudioStreamPlayer.new()
		_recycle_player.stream = recycle_stream
		_recycle_player.bus = &"SFX"
		add_child(_recycle_player)

	var auction_stream: AudioStreamWAV = load("res://assets/music/auction.wav") as AudioStreamWAV
	if auction_stream:
		# Don't rely on the .import file's baked loop_mode/loop_end — Godot's
		# WAV importer has been observed to bake loop_end as 0 regardless of
		# the "edit/loop_end" import setting (see main.gd/main_menu.gd
		# _setup_music() for the same fix and how it was diagnosed). A
		# loop_end of 0 makes the player loop back to the start after a
		# single sample, which sounds identical to no music playing at all.
		auction_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if auction_stream.loop_end <= auction_stream.loop_begin:
			auction_stream.loop_end = int(auction_stream.get_length() * auction_stream.mix_rate)
		_auction_player = AudioStreamPlayer.new()
		_auction_player.stream = auction_stream
		_auction_player.bus = &"Music"
		add_child(_auction_player)

	var shift_change_stream: AudioStream = load("res://assets/effects/computery-shift-change.wav") as AudioStream
	if shift_change_stream:
		_shift_change_player = AudioStreamPlayer.new()
		_shift_change_player.stream = shift_change_stream
		_shift_change_player.bus = &"SFX"
		add_child(_shift_change_player)

	var supply_files: Dictionary = {
		CardData.SupplyColor.DUST:     "res://assets/effects/dust.wav",
		CardData.SupplyColor.METALS:   "res://assets/effects/metals.wav",
		CardData.SupplyColor.LIQUIDS:  "res://assets/effects/liquids.wav",
		CardData.SupplyColor.ORGANIX:  "res://assets/effects/organix.wav",
		CardData.SupplyColor.ELECTRIX: "res://assets/effects/electrix.wav",
		CardData.SupplyColor.THRUST:   "res://assets/effects/thrust.wav",
	}
	for color: CardData.SupplyColor in supply_files:
		var stream: AudioStream = load(supply_files[color]) as AudioStream
		if stream:
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.stream = stream
			player.bus = &"SFX"
			add_child(player)
			_supply_players[color] = player
	_setup_sfx()
	_apply_saved_audio()

# The saved bus volumes and output device, at start-up: they were only applied
# when a PauseMenu was built (main menu), after the studio intro's chime had
# played at full SFX volume on the default device. PauseMenu still loads them
# for its sliders.
func _apply_saved_audio() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	for pair: Array in [["Music", "music_volume"], ["SFX", "sfx_volume"], ["Voice", "voice_volume"]]:
		var idx: int = AudioServer.get_bus_index(str(pair[0]))
		if idx < 0:
			continue
		var v: float = float(cfg.get_value("audio", str(pair[1]), 1.0))
		AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0 else -80.0)
	# only a device that's there: "" (unlike "Default") silences everything
	var device: String = str(cfg.get_value("audio", "output_device", ""))
	if not device.is_empty() and device in AudioServer.get_output_device_list():
		AudioServer.output_device = device

func _setup_sfx() -> void:
	for cue: String in SFX_CUES:
		var stream: AudioStream = load(SFX_DIR + cue + ".wav") as AudioStream
		if stream == null:
			continue
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = &"SFX"
		player.volume_db = float(SFX_CUES[cue])
		add_child(player)
		_sfx_players[cue] = player
	# every button in the game clicks softly when pressed, wherever it is created
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is BaseButton and not (node as BaseButton).pressed.is_connected(_on_button_pressed):
			(node as BaseButton).pressed.connect(_on_button_pressed))

func _on_button_pressed() -> void:
	play_sfx("ui_click")

func play_sfx(cue: String) -> void:
	var player: AudioStreamPlayer = _sfx_players.get(cue) as AudioStreamPlayer
	if player:
		player.play()

func play_fuse_sfx() -> void:
	if not _fuse_player:
		return
	_fuse_player.play()

func play_gavel_sfx() -> void:
	if not _gavel_player or _gavel_player.playing:
		return
	_gavel_player.play()

func play_recycle_sfx() -> void:
	if not _recycle_player:
		return
	_recycle_player.play()

func play_auction_music() -> void:
	if not _auction_player or _auction_player.playing:
		return
	_auction_player.play()

func stop_auction_music() -> void:
	if not _auction_player:
		return
	_auction_player.stop()

func play_shift_change_sfx() -> void:
	if not _shift_change_player:
		return
	_shift_change_player.play()

func play_supply_sfx(color: CardData.SupplyColor) -> void:
	var player: AudioStreamPlayer = _supply_players.get(color) as AudioStreamPlayer
	if player:
		player.play()
