extends Node

var _fuse_player: AudioStreamPlayer = null
var _gavel_player: AudioStreamPlayer = null
var _recycle_player: AudioStreamPlayer = null
var _auction_player: AudioStreamPlayer = null

func _ready() -> void:
	var fuse_stream: AudioStream = load("res://assets/effects/fuse.ogg") as AudioStream
	if fuse_stream:
		_fuse_player = AudioStreamPlayer.new()
		_fuse_player.stream = fuse_stream
		_fuse_player.bus = &"SFX"
		add_child(_fuse_player)

	var gavel_stream: AudioStream = load("res://assets/effects/gavel.ogg") as AudioStream
	if gavel_stream:
		_gavel_player = AudioStreamPlayer.new()
		_gavel_player.stream = gavel_stream
		_gavel_player.bus = &"SFX"
		add_child(_gavel_player)

	var recycle_stream: AudioStream = load("res://assets/effects/recycle.ogg") as AudioStream
	if recycle_stream:
		_recycle_player = AudioStreamPlayer.new()
		_recycle_player.stream = recycle_stream
		_recycle_player.bus = &"SFX"
		add_child(_recycle_player)

	var auction_stream: AudioStreamOggVorbis = load("res://assets/music/auction.ogg") as AudioStreamOggVorbis
	if auction_stream:
		auction_stream.loop = true
		_auction_player = AudioStreamPlayer.new()
		_auction_player.stream = auction_stream
		_auction_player.bus = &"Music"
		add_child(_auction_player)

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
