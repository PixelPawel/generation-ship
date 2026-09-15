extends Node

# Push-to-talk voice chat. Captures through Godot's own audio input
# (AudioStreamMicrophone -> a muted "VoiceCapture" bus tapped by an
# AudioEffectCapture) rather than Steam's voice API — Steamworks'
# StartVoiceRecording/GetVoice has no device-selection parameter of its own
# (it just uses whatever the OS/Steam client has set as default), so it
# can't honor a per-app input-device setting. Going through AudioServer
# instead means AudioServer.input_device (set from the pause menu) actually
# takes effect, at the cost of sending raw 16-bit PCM instead of Steam's
# compressed codec — acceptable for a push-to-talk voice channel in a 2-4
# player co-op game, and it removes the earlier dependency on GodotSteam's
# voice dictionary key names, which couldn't be confirmed from the shipped
# binary alone.
#
# Delivery relays through the host the same way chat_manager.gd and
# lobby.gd's player-list sync do (any_peer -> rpc_id(1, ...) -> host
# re-broadcasts), since that's the only path this project's
# SteamMultiplayerPeer setup is proven to reach every client through.
# Each packet carries the sender's own capture sample rate so playback
# always matches it exactly, even if two players' audio devices ended up
# running the engine at different effective mix rates.

signal peer_speaking_changed(peer_id: int, speaking: bool)
signal local_recording_changed(recording: bool)

const SPEAKING_TIMEOUT_MSEC: int = 400
const GENERATOR_BUFFER_LEN: float = 0.5
const CAPTURE_BUS_NAME: String = "VoiceCapture"
const PLAYBACK_BUS_NAME: String = "Voice"

var muted_peers: Dictionary = {}          # peer_id (int) -> true, local-only
var voice_enabled: bool = true            # master on/off for capturing+sending

var _recording: bool = false
var _capture_sample_rate: int = 48000
var _mic_player: AudioStreamPlayer = null
var _capture_effect: AudioEffectCapture = null

var _playback_players: Dictionary = {}    # peer_id -> AudioStreamPlayer
var _playback_gens: Dictionary = {}       # peer_id -> AudioStreamGeneratorPlayback
var _last_packet_msec: Dictionary = {}    # peer_id -> int
var _speaking: Dictionary = {}            # peer_id -> bool

func _ready() -> void:
	if not InputMap.has_action("voice_ptt"):
		InputMap.add_action("voice_ptt")
	_capture_sample_rate = AudioServer.get_mix_rate()
	_setup_capture()
	set_process(true)

func _setup_capture() -> void:
	var bus_idx: int = AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if bus_idx < 0:
		push_warning("VoiceManager: '%s' bus not found — voice capture disabled." % CAPTURE_BUS_NAME)
		return
	for i: int in AudioServer.get_bus_effect_count(bus_idx):
		var fx: AudioEffect = AudioServer.get_bus_effect(bus_idx, i)
		if fx is AudioEffectCapture:
			_capture_effect = fx
			break
	if not _capture_effect:
		push_warning("VoiceManager: no AudioEffectCapture on '%s' bus — voice capture disabled." % CAPTURE_BUS_NAME)
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = CAPTURE_BUS_NAME
	add_child(_mic_player)

func _process(_delta: float) -> void:
	if not multiplayer.multiplayer_peer or not voice_enabled:
		if _recording:
			_stop_recording()
	else:
		if Input.is_action_just_pressed("voice_ptt"):
			_start_recording()
		elif Input.is_action_just_released("voice_ptt"):
			_stop_recording()
		if _recording:
			_pump_local_voice()
	_check_speaking_timeouts()

func is_recording() -> bool:
	return _recording

func is_speaking(peer_id: int) -> bool:
	return bool(_speaking.get(peer_id, false))

func set_peer_muted(peer_id: int, muted: bool) -> void:
	muted_peers[peer_id] = muted

func is_peer_muted(peer_id: int) -> bool:
	return bool(muted_peers.get(peer_id, false))

# ── Local capture ────────────────────────────────────────────────────────────

func _start_recording() -> void:
	if _recording or not _mic_player:
		return
	_recording = true
	if _capture_effect:
		_capture_effect.clear_buffer()
	_mic_player.play()
	local_recording_changed.emit(true)

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	if _mic_player:
		_mic_player.stop()
	local_recording_changed.emit(false)

func _pump_local_voice() -> void:
	if not _capture_effect or not multiplayer.multiplayer_peer:
		return
	var avail: int = _capture_effect.get_frames_available()
	if avail <= 0:
		return
	var frames: PackedVector2Array = _capture_effect.get_buffer(avail)
	if frames.is_empty():
		return
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(frames.size() * 2)
	for i: int in frames.size():
		var sample: float = clampf(frames[i].x, -1.0, 1.0)
		pcm.encode_s16(i * 2, int(sample * 32767.0))
	# When the local peer IS the host, rpc_id(1, ...) would be an RPC call
	# targeting yourself — Godot rejects that outright ("RPC on yourself is
	# not allowed") unless the method is call_local, which this one isn't
	# (it doesn't need to be: the host never needs to hear its own voice).
	# Route straight into the relay logic instead, same as ChatManager.
	# send_message() already does for host-authored chat messages.
	if multiplayer.is_server():
		_relay_voice_as_host(multiplayer.get_unique_id(), _capture_sample_rate, pcm)
	else:
		_rpc_relay_voice.rpc_id(1, _capture_sample_rate, pcm)

# ── Network relay (host re-broadcasts, same shape as ChatManager) ──────────────

@rpc("any_peer", "unreliable")
func _rpc_relay_voice(sample_rate: int, data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	_relay_voice_as_host(multiplayer.get_remote_sender_id(), sample_rate, data)

func _relay_voice_as_host(sender: int, sample_rate: int, data: PackedByteArray) -> void:
	for pid: int in multiplayer.get_peers():
		if pid == sender:
			continue
		_rpc_deliver_voice.rpc_id(pid, sender, sample_rate, data)
	if sender != 1:
		_on_voice_received(sender, sample_rate, data)

@rpc("authority", "unreliable")
func _rpc_deliver_voice(sender: int, sample_rate: int, data: PackedByteArray) -> void:
	_on_voice_received(sender, sample_rate, data)

func _on_voice_received(sender: int, sample_rate: int, data: PackedByteArray) -> void:
	_last_packet_msec[sender] = Time.get_ticks_msec()
	if not _speaking.get(sender, false):
		_speaking[sender] = true
		peer_speaking_changed.emit(sender, true)
	if is_peer_muted(sender):
		return
	_play_pcm(sender, sample_rate, data)

func _check_speaking_timeouts() -> void:
	var now: int = Time.get_ticks_msec()
	for pid: Variant in _last_packet_msec.keys():
		if not _speaking.get(pid, false):
			continue
		if now - int(_last_packet_msec[pid]) > SPEAKING_TIMEOUT_MSEC:
			_speaking[pid] = false
			peer_speaking_changed.emit(int(pid), false)

# ── Playback ─────────────────────────────────────────────────────────────────

func _get_or_create_playback(peer_id: int, sample_rate: int) -> AudioStreamGeneratorPlayback:
	if _playback_gens.has(peer_id):
		return _playback_gens[peer_id]
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = GENERATOR_BUFFER_LEN
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = gen
	player.bus = PLAYBACK_BUS_NAME
	add_child(player)
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	_playback_players[peer_id] = player
	_playback_gens[peer_id] = playback
	return playback

func _play_pcm(peer_id: int, sample_rate: int, pcm: PackedByteArray) -> void:
	var playback: AudioStreamGeneratorPlayback = _get_or_create_playback(peer_id, sample_rate)
	if not playback:
		return
	@warning_ignore("integer_division")
	var frame_count: int = pcm.size() / 2  # 2 bytes per 16-bit PCM sample
	if frame_count <= 0:
		return
	var frames: PackedVector2Array = PackedVector2Array()
	frames.resize(frame_count)
	for i: int in frame_count:
		var sample: int = pcm.decode_s16(i * 2)
		var f: float = sample / 32768.0
		frames[i] = Vector2(f, f)
	var avail: int = playback.get_frames_available()
	if avail < frame_count:
		frames = frames.slice(frame_count - avail)
	playback.push_buffer(frames)
