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
#
# Entries: {rank, name, score, details, platform, source, me}. `details` is the
# ScoringSnapshotCodec-packed score breakdown shown when a row is expanded.
#
# No direct reference to the Steam class: GodotSteam doesn't exist in the
# Android build.

signal top_scores_ready(entries: Array[Dictionary])
signal top_scores_failed
signal score_uploaded(success: bool)

const SERVER_URL: String = "https://api.happycapygames.com"
const TIMEOUT_SEC: float = 10.0
const TOP_COUNT: int = 100
const _SETTINGS_PATH: String = "user://settings.cfg"

# The player's own best, from the last download (null if not on the board).
var my_best: Dictionary = {}

const SOURCE_PLAY: String = "play"
const SOURCE_SCAN: String = "scan"
const SOURCE_ALL: String = "all"

func submit_score(score: int, details: PackedInt32Array = PackedInt32Array(), source: String = SOURCE_PLAY) -> void:
	var body: String = JSON.stringify({
		player = _player_id(), name = player_name(), score = clampi(score, 0, 999),
		details = Array(details), platform = "android" if OS.get_name() == "Android" else "steam",
		source = source,
	})
	_request(HTTPClient.METHOD_POST, "/v1/scores", body, func(ok: bool, _data: Dictionary) -> void:
		score_uploaded.emit(ok))

## source: SOURCE_ALL, SOURCE_PLAY or SOURCE_SCAN.
func request_top_scores(source: String = SOURCE_ALL) -> void:
	var path: String = "/v1/scores/top?limit=%d&player=%s&source=%s" % [TOP_COUNT, _player_id().uri_encode(), source]
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
