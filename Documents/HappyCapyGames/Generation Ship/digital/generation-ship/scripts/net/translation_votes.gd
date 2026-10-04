extends Node
# TranslationVotes — community up/down votes on each card's translation, per
# language, stored on the Happy Capy Games API server (digital/server/) so
# Steam and Android players share one set of results.
#
# A card image in one language is one key, e.g. "tv_PL_Tech_GSTechs44x67mm12".
# A vote is +1 good, -1 needs work, 0 retracted; each voter has one vote per
# key and re-voting overwrites it. Voters are "steam:<id>" when Steam is
# running, otherwise "dev:<random id>" generated once per device.
#
# No direct reference to the Steam class here: GodotSteam doesn't exist in the
# Android build, and a bare `Steam` identifier would fail to compile there.

signal votes_ready(key: String, up: int, down: int, mine: int)
signal votes_failed(key: String)
# A translation comment was stored (ok) or not; mine = how many comments this
# player has sent on this card so far.
signal comment_sent(key: String, ok: bool, mine: int)

# Parts of a card a comment can be about (server checks the same list).
const COMMENT_FIELDS: Array[String] = ["name", "flavor", "effect"]
const COMMENT_MAX_CHARS: int = 500

# Set to "" to switch voting off entirely (the Collection then hides it).
const SERVER_URL: String = "https://api.happycapygames.com"
const TIMEOUT_SEC: float = 10.0
const _DEVICE_ID_PATH: String = "user://device_id.cfg"

var _cache: Dictionary = {}   # key -> {up, down, mine}
var _voter: String = ""

func is_available() -> bool:
	return not SERVER_URL.is_empty()

# Stable key for one card image in one language. Only [A-Za-z0-9_] so file
# names with spaces/commas ("GS Dangers 63,5x89mm12") stay safe; the server
# checks the same shape.
static func board_name(lang: String, folder: String, fname: String) -> String:
	var base: String = fname.get_basename()
	var clean: String = ""
	for ch: String in (folder + "_" + base):
		var c: int = ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch == "_":
			clean += ch
	return ("tv_" + lang.to_upper() + "_" + clean).left(128)

func cached(key: String) -> Dictionary:
	return _cache.get(key, {})

func fetch(key: String) -> void:
	if not is_available():
		votes_failed.emit(key)
		return
	_request(HTTPClient.METHOD_GET,
		"/v1/votes?keys=%s&voter=%s" % [key.uri_encode(), _voter_id().uri_encode()], "", key)

# value: 1, -1 or 0 (retract). Updates the cache optimistically so the UI
# reacts instantly; the server's reply then replaces it with the real counts.
func vote(key: String, value: int) -> void:
	if not is_available():
		return
	var c: Dictionary = _cache.get(key, {up = 0, down = 0, mine = 0})
	var up: int = int(c.up) - (1 if int(c.mine) > 0 else 0) + (1 if value > 0 else 0)
	var down: int = int(c.down) - (1 if int(c.mine) < 0 else 0) + (1 if value < 0 else 0)
	_cache[key] = {up = up, down = down, mine = value}
	votes_ready.emit(key, up, down, value)
	_request(HTTPClient.METHOD_POST, "/v1/votes",
		JSON.stringify({key = key, voter = _voter_id(), value = value}), key)

# Free-text feedback on one part (COMMENT_FIELDS) of one translated card.
# Players may send as many as they like; the server rate-limits floods.
func send_comment(key: String, field: String, text: String) -> void:
	var clean: String = text.strip_edges().left(COMMENT_MAX_CHARS)
	if not is_available() or not field in COMMENT_FIELDS or clean.is_empty():
		comment_sent.emit(key, false, 0)
		return
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		req.queue_free()
		var data: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
		var ok: bool = code == 200 and typeof(data) == TYPE_DICTIONARY and bool((data as Dictionary).get("ok", false))
		comment_sent.emit(key, ok, int((data as Dictionary).get("mine", 0)) if ok else 0))
	var body: String = JSON.stringify({key = key, voter = _voter_id(), field = field, text = clean,
		version = str(ProjectSettings.get_setting("application/config/version", ""))})
	if req.request(SERVER_URL + "/v1/comments", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		comment_sent.emit(key, false, 0)

func _request(method: HTTPClient.Method, path: String, body: String, key: String) -> void:
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		_on_completed(req, key, result, code, bytes))
	var err: Error = req.request(SERVER_URL + path, PackedStringArray(["Content-Type: application/json"]), method, body)
	if err != OK:
		req.queue_free()
		votes_failed.emit(key)

func _on_completed(req: HTTPRequest, key: String, result: int, code: int, bytes: PackedByteArray) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		votes_failed.emit(key)
		return
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("votes")) != TYPE_DICTIONARY:
		votes_failed.emit(key)
		return
	var v: Variant = (data["votes"] as Dictionary).get(key)
	if typeof(v) != TYPE_DICTIONARY:
		votes_failed.emit(key)
		return
	var up: int = int(v.get("up", 0))
	var down: int = int(v.get("down", 0))
	var mine: int = int(v.get("mine", 0))
	_cache[key] = {up = up, down = down, mine = mine}
	votes_ready.emit(key, up, down, mine)

# Also the player's id on the leaderboard (LeaderboardManager).
func player_id() -> String:
	return _voter_id()

func _voter_id() -> String:
	if not _voter.is_empty():
		return _voter
	var steam_mgr: Node = get_node_or_null("/root/SteamManager")
	if steam_mgr and bool(steam_mgr.get("is_initialized")) and Engine.has_singleton("Steam"):
		var steam_id: int = int(Engine.get_singleton("Steam").call("getSteamID"))
		if steam_id > 0:
			_voter = "steam:%d" % steam_id
			return _voter
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(_DEVICE_ID_PATH)
	var dev_id: String = str(cfg.get_value("device", "id", ""))
	if dev_id.is_empty():
		dev_id = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("device", "id", dev_id)
		cfg.save(_DEVICE_ID_PATH)
	_voter = "dev:" + dev_id
	return _voter
