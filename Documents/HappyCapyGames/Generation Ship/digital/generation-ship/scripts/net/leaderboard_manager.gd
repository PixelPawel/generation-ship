extends Node
# LeaderboardManager — global Top-100 leaderboard via Steamworks
# (ISteamUserStats, wrapped by GodotSteam). One leaderboard, "TotalScore",
# holds every completed game's final VP total regardless of solo/multiplayer.
#
# Steam always attributes an upload to whichever account is locally logged
# in — there is no way (or need) to submit on behalf of another player, so
# each client just submits its own score once it computes it in
# main.gd's _game_over(). This matches the game's existing trust model:
# opponents' displayed scores are already client-reported snapshots, not
# host-validated (see main.gd _game_over()/_opp_snapshots).
#
# Entry display names: Steam only has a cached persona name for friends and
# recently-seen players out of the box. For everyone else getFriendPersonaName()
# returns "[unknown]" until requestUserInformation() is called and the
# persona_state_change signal fires — so rows start with a Steam-ID
# placeholder and get patched in-place once (if) the real name arrives.

const LEADERBOARD_NAME: String = "TotalScore"
const TOP_COUNT: int = 100

signal top_scores_ready(entries: Array[Dictionary])
signal top_scores_failed
signal score_uploaded(success: bool)
signal entry_name_resolved(steam_id: int, name: String)

var _leaderboard_handle: int = 0
var _finding: bool = false
var _pending_score: int = -1
var _pending_details: PackedInt32Array = PackedInt32Array()
var _pending_download: bool = false
var _name_cache: Dictionary = {}          # steam_id (int) -> persona name (String)
var _requested_names: Dictionary = {}     # steam_id (int) -> true, once requestUserInformation() called

func _ready() -> void:
	Steam.leaderboard_find_result.connect(_on_leaderboard_find_result)
	Steam.leaderboard_score_uploaded.connect(_on_leaderboard_score_uploaded)
	Steam.leaderboard_scores_downloaded.connect(_on_leaderboard_scores_downloaded)
	Steam.persona_state_change.connect(_on_persona_state_change)

func submit_score(score: int, details: PackedInt32Array = PackedInt32Array()) -> void:
	if not SteamManager.is_initialized:
		return
	_pending_score = score
	_pending_details = details
	_ensure_leaderboard()

func request_top_scores() -> void:
	if not SteamManager.is_initialized:
		top_scores_failed.emit()
		return
	_pending_download = true
	_ensure_leaderboard()

# Best-effort synchronous name lookup — returns a cached/known persona name
# immediately if Steam already has one, otherwise kicks off an async
# request and returns "" (caller should show a placeholder and listen for
# entry_name_resolved to patch it in).
func resolve_name(steam_id: int) -> String:
	if _name_cache.has(steam_id):
		return _name_cache[steam_id]
	var name: String = Steam.getFriendPersonaName(steam_id)
	if name != "" and name != "[unknown]":
		_name_cache[steam_id] = name
		return name
	if not _requested_names.has(steam_id):
		_requested_names[steam_id] = true
		Steam.requestUserInformation(steam_id, true)
	return ""

# Decodes a downloaded entry's "details" field into resolved CardData refs.
# See CardSnapshotCodec for the packing scheme this reverses.
func decode_snapshot(entry: Dictionary) -> Array[Dictionary]:
	var raw: Variant = entry.get("details", PackedInt32Array())
	var details: PackedInt32Array = raw if raw is PackedInt32Array else PackedInt32Array(raw)
	return CardSnapshotCodec.decode_details(details)

func _ensure_leaderboard() -> void:
	if _leaderboard_handle != 0:
		_run_pending()
		return
	if _finding:
		return
	_finding = true
	Steam.findOrCreateLeaderboard(LEADERBOARD_NAME, Steam.LEADERBOARD_SORT_METHOD_DESCENDING, Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC)

func _run_pending() -> void:
	if _pending_score >= 0:
		var score: int = _pending_score
		var details: PackedInt32Array = _pending_details
		_pending_score = -1
		_pending_details = PackedInt32Array()
		Steam.uploadLeaderboardScore(score, true, details, _leaderboard_handle)
	if _pending_download:
		_pending_download = false
		Steam.downloadLeaderboardEntries(1, TOP_COUNT, Steam.LEADERBOARD_DATA_REQUEST_GLOBAL, _leaderboard_handle)

func _on_leaderboard_find_result(leaderboard_handle: int, found: int) -> void:
	_finding = false
	if found == 0:
		push_warning("LeaderboardManager: could not find/create leaderboard '%s'." % LEADERBOARD_NAME)
		if _pending_download:
			_pending_download = false
			top_scores_failed.emit()
		_pending_score = -1
		_pending_details = PackedInt32Array()
		return
	_leaderboard_handle = leaderboard_handle
	_run_pending()

func _on_leaderboard_score_uploaded(success: bool, _this_handle: int, _this_score: Dictionary) -> void:
	score_uploaded.emit(success)

func _on_leaderboard_scores_downloaded(_message: String, _leaderboard_handle: int, leaderboard_entries: Array) -> void:
	var entries: Array[Dictionary] = []
	for e: Dictionary in leaderboard_entries:
		entries.append(e)
	top_scores_ready.emit(entries)

func _on_persona_state_change(steam_id: int, _flags: int) -> void:
	if not _requested_names.has(steam_id):
		return
	var name: String = Steam.getFriendPersonaName(steam_id)
	if name != "" and name != "[unknown]":
		_name_cache[steam_id] = name
		entry_name_resolved.emit(steam_id, name)
