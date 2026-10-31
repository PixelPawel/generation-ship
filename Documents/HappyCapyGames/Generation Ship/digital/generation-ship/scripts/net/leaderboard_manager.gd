extends Node
# LeaderboardManager — global Top-100 leaderboard on the Happy Capy Games API
# server (digital/server/app/scores.py), shared by Steam and Android. Was a
# Steamworks leaderboard, which only ever worked with Steam running.
#
# One entry per player (the same id TranslationVotes uses: "steam:<id>" or an
# anonymous "dev:<device id>"), keeping their best total. Each client submits
# only its own final score from main.gd's _game_over() — the same trust model
# as before: opponents' scores are client-reported snapshots anyway.
#
# Every score has a source: "play" (a game played to the end in the app) or
# "scan" (a ship read from a photo by Scan Tableau, which can be any ship at all).
# The server keeps a best per player and source, and the board can show either.
# "fleet" is a won Generation Fleet (co-op) game, with the Destination's No.; it
# has its own board and the server leaves it out of "all".
#
# Entries: {rank, name, score, details, platform, source, me}. `details` is the
# ScoringSnapshotCodec-packed score breakdown shown when a row is expanded.
#
# No direct reference to the Steam class: GodotSteam doesn't exist in the
# Android build.
#
# Nothing is posted before the player says yes (privacy policy, digital/legal/):
# the first score waits while leaderboard_consent.gd asks once, under which name.
# After a no, finished games are skipped silently; a scan's "Add to Leaderboard"
# asks again. Settings (pause_menu.gd) can switch it either way.
const ConsentPopup = preload("res://scenes/ui/leaderboard_consent.gd")

signal top_scores_ready(entries: Array[Dictionary])
signal top_scores_failed
signal score_uploaded(success: bool)
signal score_not_shared            # the player said no (or posting is off): nothing was uploaded
signal sharing_changed(on: bool)

const SERVER_URL: String = "https://api.happycapygames.com"
const PRIVACY_URL: String = SERVER_URL + "/datenschutz"
const PRIVACY_URL_ANDROID: String = SERVER_URL + "/datenschutz-android"
const TIMEOUT_SEC: float = 10.0
const TOP_COUNT: int = 100
const _SETTINGS_PATH: String = "user://settings.cfg"
const SHARING_ON: String = "on"
const SHARING_OFF: String = "off"
const CONSENT_DELAY_SEC: float = 2.0   # end of a game: the final scores show first
const CONSENT_LAYER: int = 120         # above the game's UI, below scene transitions (128)

var _pending: Array[Dictionary] = []   # scores waiting for the player's answer
var _consent: Control = null

# The player's own best, from the last download (null if not on the board).
var my_best: Dictionary = {}

const SOURCE_PLAY: String = "play"
const SOURCE_SCAN: String = "scan"
const SOURCE_ALL: String = "all"
const SOURCE_FLEET: String = "fleet"

func submit_score(score: int, details: PackedInt32Array = PackedInt32Array(), source: String = SOURCE_PLAY,
		destination: int = 0) -> void:
	var entry: Dictionary = {score = clampi(score, 0, 999), details = Array(details), source = source,
		destination = destination}
	var state: String = _sharing_state()
	if state == SHARING_ON:
		_upload(entry)
	elif state == SHARING_OFF and source != SOURCE_SCAN:
		score_not_shared.emit()
	else:
		_pending.append(entry)
		ask_consent(0.0 if source == SOURCE_SCAN else CONSENT_DELAY_SEC)

func _upload(entry: Dictionary) -> void:
	var body: String = JSON.stringify({
		player = _player_id(), name = player_name(), score = int(entry["score"]), details = entry["details"],
		platform = "android" if OS.get_name() == "Android" else "steam",
		source = str(entry["source"]), destination = int(entry["destination"]),
	})
	_request(HTTPClient.METHOD_POST, "/v1/scores", body, func(ok: bool, _data: Dictionary) -> void:
		score_uploaded.emit(ok))

func is_sharing() -> bool:
	return _sharing_state() == SHARING_ON

func _sharing_state() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	return str(cfg.get_value("player", "leaderboard", ""))

## The player's answer (consent popup or Settings). A yes saves the name for the
## board and posts any scores that were waiting; a no drops them.
func set_sharing(on: bool, board_name: String = "") -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("player", "leaderboard", SHARING_ON if on else SHARING_OFF)
	if on and not board_name.strip_edges().is_empty():
		cfg.set_value("player", "name", board_name.strip_edges())
	cfg.save(_SETTINGS_PATH)
	var waiting: Array[Dictionary] = _pending.duplicate()
	_pending.clear()
	sharing_changed.emit(on)
	for entry: Dictionary in waiting:
		if on:
			_upload(entry)
		else:
			score_not_shared.emit()

## Shows the one-time question (also Settings' switch turning on).
func ask_consent(delay_sec: float = 0.0) -> void:
	if delay_sec > 0.0:
		await get_tree().create_timer(delay_sec).timeout
	if _consent == null or not is_instance_valid(_consent):
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = CONSENT_LAYER
		add_child(layer)
		_consent = ConsentPopup.new()
		layer.add_child(_consent)
		_consent.answered.connect(set_sharing)
	if not _consent.visible:
		_consent.open(player_name())

## The privacy policy for this build, at the half in the player's language.
func privacy_url() -> String:
	var base: String = PRIVACY_URL_ANDROID if OS.get_name() == "Android" else PRIVACY_URL
	return base + ("#de" if TranslationServer.get_locale().begins_with("de") else "#en")

## source: SOURCE_ALL, SOURCE_PLAY, SOURCE_SCAN or SOURCE_FLEET.
func request_top_scores(source: String = SOURCE_ALL) -> void:
	# the player id (to mark the own row) only goes along if the player posts to the board
	var path: String = "/v1/scores/top?limit=%d&source=%s" % [TOP_COUNT, source]
	if is_sharing():
		path += "&player=" + _player_id().uri_encode()
	_request(HTTPClient.METHOD_GET, path, "", func(ok: bool, data: Dictionary) -> void:
		if not ok or typeof(data.get("entries")) != TYPE_ARRAY:
			top_scores_failed.emit()
			return
		my_best = {}
		if typeof(data.get("mine")) == TYPE_DICTIONARY:
			my_best = data["mine"]
		var entries: Array[Dictionary] = []
		for e: Variant in data["entries"]:
			if typeof(e) == TYPE_DICTIONARY:
				entries.append(e)
		top_scores_ready.emit(entries))

# Decodes an entry's "details" into {label, vp} scoring lines. See
# ScoringSnapshotCodec for the packing scheme this reverses.
func decode_snapshot(entry: Dictionary) -> Array[Dictionary]:
	var raw: Variant = entry.get("details", [])
	var details: PackedInt32Array = PackedInt32Array()
	if typeof(raw) == TYPE_ARRAY:
		for v: Variant in raw:
			details.append(int(v))
	return ScoringSnapshotCodec.decode_lines(details)

# The name shown on the board: the lobby name if one was ever entered, else
# the Steam display name, else "Player".
func player_name() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) == OK:
		var saved: String = str(cfg.get_value("player", "name", "")).strip_edges()
		if not saved.is_empty():
			return saved
	var steam_mgr: Node = get_node_or_null("/root/SteamManager")
	if steam_mgr and bool(steam_mgr.get("is_initialized")) and Engine.has_singleton("Steam"):
		var steam_name: String = str(Engine.get_singleton("Steam").call("getPersonaName"))
		if not steam_name.is_empty():
			return steam_name
	return "Player"

func _player_id() -> String:
	var votes: Node = get_node_or_null("/root/TranslationVotes")
	return str(votes.call("player_id")) if votes else ""

func _request(method: HTTPClient.Method, path: String, body: String, done: Callable) -> void:
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		req.queue_free()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
		var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200 and typeof(parsed) == TYPE_DICTIONARY
		var data: Dictionary = {}
		if ok:
			data = parsed
		done.call(ok, data))
	var err: Error = req.request(SERVER_URL + path, PackedStringArray(["Content-Type: application/json"]), method, body)
	if err != OK:
		req.queue_free()
		done.call(false, {})
