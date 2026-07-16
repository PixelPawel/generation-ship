extends Node

var _fuse_player: AudioStreamPlayer = null
var _gavel_player: AudioStreamPlayer = null
var _recycle_player: AudioStreamPlayer = null
var _auction_player: AudioStreamPlayer = null
var _supply_players: Dictionary = {}

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
		_auction_player = AudioStreamPlayer.new()
		_auction_player.stream = auction_stream
		_auction_player.bus = &"Music"
		add_child(_auction_player)

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

func play_supply_sfx(color: CardData.SupplyColor) -> void:
	var player: AudioStreamPlayer = _supply_players.get(color) as AudioStreamPlayer
	if player:
		player.play()
