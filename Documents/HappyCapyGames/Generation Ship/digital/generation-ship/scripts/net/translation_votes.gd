extends Node
# TranslationVotes — community up/down votes on each card's translation, per
# language, stored in Steam leaderboards (no server of our own).
#
# One leaderboard per card image per language, e.g. "tv_PL_Tech_GSTechs44x67mm12",
# created on first view. A player's vote is their entry's score: +1 good,
# -1 needs work, 0 retracted (Steam can't delete an entry, so 0 just isn't
# counted). Uploads force-update, so changing a vote overwrites the old one;
# Steam keeps exactly one entry per account.
#
# Requests run one at a time. LeaderboardManager listens to the same GodotSteam
# signals, so every handler here filters by board name/handle.

signal votes_ready(key: String, up: int, down: int, mine: int)
signal votes_failed(key: String)

const PREFIX: String = "tv_"
const MAX_ENTRIES: int = 2000

var _handles: Dictionary = {}     # board name -> handle
var _cache: Dictionary = {}       # board name -> {up, down, mine}
var _queue: Array[Dictionary] = []  # {name, op: "fetch"|"vote", value}
var _busy: Dictionary = {}        # current request, {} when idle

func _ready() -> void:
	if not SteamManager.is_initialized:
		return
	Steam.leaderboard_find_result.connect(_on_find_result)
	Steam.leaderboard_score_uploaded.connect(_on_uploaded)
	Steam.leaderboard_scores_downloaded.connect(_on_downloaded)

func is_available() -> bool:
	return SteamManager.is_initialized

# Stable board name for one card image in one language. Only [A-Za-z0-9_]
# so file names with spaces/commas ("GS Dangers 63,5x89mm12") stay safe.
static func board_name(lang: String, folder: String, fname: String) -> String:
	var base: String = fname.get_basename()
	var clean: String = ""
	for ch: String in (folder + "_" + base):
		var c: int = ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch == "_":
			clean += ch
	return (PREFIX + lang.to_upper() + "_" + clean).left(128)

func cached(key: String) -> Dictionary:
	return _cache.get(key, {})

func fetch(key: String) -> void:
	if not is_available():
		votes_failed.emit(key)
		return
	_enqueue({name = key, op = "fetch"})

# value: 1, -1 or 0 (retract). Optimistically updates the cache so the UI can
# react instantly; the follow-up fetch replaces it with Steam's real counts.
func vote(key: String, value: int) -> void:
	if not is_available():
		return
	var c: Dictionary = _cache.get(key, {up = 0, down = 0, mine = 0})
	var up: int = int(c.up) - (1 if int(c.mine) > 0 else 0) + (1 if value > 0 else 0)
	var down: int = int(c.down) - (1 if int(c.mine) < 0 else 0) + (1 if value < 0 else 0)
	_cache[key] = {up = up, down = down, mine = value}
	votes_ready.emit(key, up, down, value)
	_enqueue({name = key, op = "vote", value = value})
	_enqueue({name = key, op = "fetch"})

func _enqueue(req: Dictionary) -> void:
	_queue.append(req)
	if _busy.is_empty():
		_next()

func _next() -> void:
	_busy = {}
	if _queue.is_empty():
		return
	_busy = _queue.pop_front()
	var key: String = _busy.name
	if _handles.has(key):
		_run(_handles[key])
	else:
		Steam.findOrCreateLeaderboard(key, Steam.LEADERBOARD_SORT_METHOD_DESCENDING, Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC)

func _run(handle: int) -> void:
	if _busy.op == "vote":
		Steam.uploadLeaderboardScore(int(_busy.value), false, PackedInt32Array(), handle)
	else:
		Steam.downloadLeaderboardEntries(1, MAX_ENTRIES, Steam.LEADERBOARD_DATA_REQUEST_GLOBAL, handle)

func _fail() -> void:
	var key: String = _busy.get("name", "")
	# Drop any queued follow-ups for the same board; the UI keeps its last state.
	_queue = _queue.filter(func(r: Dictionary) -> bool: return r.name != key)
	votes_failed.emit(key)
	_next()

func _on_find_result(handle: int, found: int) -> void:
	if _busy.is_empty() or _handles.has(_busy.name):
		return
	if found == 0:
		# Can't tell whose failure this was by name (handle is 0); only
		# claim it while we're the ones waiting on a find.
		_fail()
		return
	if Steam.getLeaderboardName(handle) != _busy.name:
		return
	_handles[_busy.name] = handle
	_run(handle)

func _on_uploaded(success: bool, this_handle: int, _score: Dictionary) -> void:
	if _busy.is_empty() or _busy.op != "vote" or _handles.get(_busy.name, -1) != this_handle:
		return
	if not success:
		_fail()
		return
	_next()

func _on_downloaded(_message: String, this_handle: int, entries: Array) -> void:
	if _busy.is_empty() or _busy.op != "fetch" or _handles.get(_busy.name, -1) != this_handle:
		return
	var me: int = Steam.getSteamID()
	var up: int = 0
	var down: int = 0
	var mine: int = 0
	for e: Dictionary in entries:
		var s: int = int(e.get("score", 0))
		if s > 0:
			up += 1
		elif s < 0:
			down += 1
		if int(e.get("steam_id", 0)) == me:
			mine = signi(s)
	var key: String = _busy.name
	_cache[key] = {up = up, down = down, mine = mine}
	votes_ready.emit(key, up, down, mine)
	_next()
