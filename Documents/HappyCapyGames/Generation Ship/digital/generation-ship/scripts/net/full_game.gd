extends Node
# FullGame — the Android app is free to download; Versus and Co-op unlock with
# a one-time Google Play purchase (product PRODUCT_ID, through the
# GodotGooglePlayBilling plugin in addons/) or with one of our codes, checked
# by the API server (digital/server/app/unlock.py; batches are made with
# tools/unlock_codes.py). The desktop (Steam) game is bought as a whole, so
# it's always unlocked there.
#
# The unlock is kept in SAVE_PATH. A Play purchase is checked again at every
# start (a refund locks it again); a code unlock stays. A new phone or a
# reinstall gets its Play purchase back on its own. A code is good for one
# player: with Google Play Games signed in, that's the Play Games account, so
# any install of that account gets the unlock back at start (server restore);
# without it, just this install.
#
# The plugins are reached by name only (call/connect), never through their
# class_names: billing through its script, loaded only on Android; Play Games
# (addons/GodotPlayGameServices) through its Android singleton.

signal changed                                  # unlocked, or the price became known
signal purchase_result(ok: bool, message: String)
signal redeem_result(ok: bool, message: String)
signal games_changed                            # Play Games sign-in known or changed

const PRODUCT_ID: String = "full_game"
const SERVER_URL: String = "https://api.happycapygames.com"
const SAVE_PATH: String = "user://full_game.cfg"
const BILLING_SCRIPT: String = "res://addons/GodotGooglePlayBilling/BillingClient.gd"
const GAMES_SINGLETON: String = "GodotPlayGameServices"
const TIMEOUT_SEC: float = 15.0
# the plugin's enums (BillingClient.gd), as plain values
const INAPP: int = 0
const RESPONSE_OK: int = 0
const USER_CANCELED: int = 1
const ITEM_ALREADY_OWNED: int = 7
const PURCHASED: int = 1
const PENDING: int = 2

var unlocked: bool = true
var price_text: String = ""                     # Play's price in the player's currency, "" until known
var _source: String = ""                        # what unlocked it: "play" or "code"
var _billing: Node = null
var _product_ready: bool = false                # Play knows the product: buying can start
var games_player_id: String = ""                # Google Play Games player, "" while not signed in
var games_name: String = ""                     # its Play Games name, shown in the unlock panel only
var _games: Object = null                       # the Play Games Android singleton

func _ready() -> void:
	if OS.get_name() != "Android":
		return
	unlocked = false
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_source = str(cfg.get_value("unlock", "source", ""))
		unlocked = not _source.is_empty()
	_start_games()
	if not ResourceLoader.exists(BILLING_SCRIPT):
		return
	var script: GDScript = load(BILLING_SCRIPT) as GDScript
	_billing = script.new() as Node
	add_child(_billing)
	_billing.connect("connected", _on_billing_connected)
	_billing.connect("query_product_details_response", _on_product_details)
	_billing.connect("query_purchases_response", _on_purchases.bind(false))
	_billing.connect("on_purchase_updated", _on_purchases.bind(true))
	_billing.call("start_connection")

func is_locked() -> bool:
	return not unlocked

## Starts Google Play's purchase sheet; the outcome comes as purchase_result.
func buy() -> void:
	if _billing == null or not _product_ready:
		purchase_result.emit(false, tr("Google Play isn't available right now. Please try again later."))
		return
	var r: Dictionary = _billing.call("purchase", PRODUCT_ID)
	var code: int = int(r.get("response_code", RESPONSE_OK))
	if code == ITEM_ALREADY_OWNED:
		_billing.call("query_purchases", INAPP)   # bought before (another install): restore it
	elif code != RESPONSE_OK:
		purchase_result.emit(false, tr("The purchase didn't go through. Please try again."))

## Checks a code with the server; the outcome comes as redeem_result.
func redeem(code: String) -> void:
	var votes: Node = get_node_or_null("/root/TranslationVotes")
	var player: String = str(votes.call("player_id")) if votes else ""
	var body: String = JSON.stringify({code = code.strip_edges(), player = player, platform = "android",
		games_player = games_player_id})
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, _bytes: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			redeem_result.emit(false, tr("Can't reach the server. Check your connection and try again."))
		elif status == 200:
			_unlock("code")
			if games_signed_in():
				var saved: ConfigFile = ConfigFile.new()
				saved.load(SAVE_PATH)
				saved.set_value("unlock", "games_player", games_player_id)
				saved.save(SAVE_PATH)
			redeem_result.emit(true, "")
		elif status == 404:
			redeem_result.emit(false, tr("That code doesn't exist. Please check it and try again."))
		elif status == 409:
			redeem_result.emit(false, tr("This code has already been used."))
		elif status == 429:
			redeem_result.emit(false, tr("Too many wrong codes. Please try again in an hour."))
		else:
			redeem_result.emit(false, tr("Can't reach the server. Check your connection and try again.")))
	if req.request(SERVER_URL + "/v1/unlock/redeem", PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		redeem_result.emit(false, tr("Can't reach the server. Check your connection and try again."))

# ── Google Play Games ───────────────────────────────────────────────────────

func _start_games() -> void:
	if not Engine.has_singleton(GAMES_SINGLETON):
		return
	_games = Engine.get_singleton(GAMES_SINGLETON)
	_games.call("initialize")
	_games.connect("userAuthenticated", _on_games_authenticated)
	_games.connect("currentPlayerLoaded", _on_games_player)
	_games.call("isAuthenticated")

func games_available() -> bool:
	return _games != null

func games_signed_in() -> bool:
	return not games_player_id.is_empty()

## Play Games' own sign-in sheet (for players it didn't sign in by itself).
func sign_in_games() -> void:
	if _games:
		_games.call("signIn")

func _on_games_authenticated(ok: bool) -> void:
	if ok:
		_games.call("loadCurrentPlayer", false)
	else:
		games_changed.emit()

func _on_games_player(player_json: String) -> void:
	var d: Variant = JSON.parse_string(player_json)
	if typeof(d) != TYPE_DICTIONARY:
		return
	games_player_id = str((d as Dictionary).get("playerId", ""))
	games_name = str((d as Dictionary).get("displayName", ""))
	games_changed.emit()
	if games_signed_in() and _source != "play":
		_restore_from_games()

# A code redeemed on this Play Games account (any install) unlocks this one
# too; a code redeemed here before signing in gets linked to the account.
# Asked once per account and install: SAVE_PATH remembers the link.
func _restore_from_games() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)
	if _source == "code" and str(cfg.get_value("unlock", "games_player", "")) == games_player_id:
		return
	var votes: Node = get_node_or_null("/root/TranslationVotes")
	var player: String = str(votes.call("player_id")) if votes else ""
	var body: String = JSON.stringify({player = player, games_player = games_player_id, platform = "android"})
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	req.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, _bytes: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and status == 200:
			_unlock("code")
			var saved: ConfigFile = ConfigFile.new()
			saved.load(SAVE_PATH)
			saved.set_value("unlock", "games_player", games_player_id)
			saved.save(SAVE_PATH))
	if req.request(SERVER_URL + "/v1/unlock/restore", PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()

func _on_billing_connected() -> void:
	_billing.call("query_product_details", PackedStringArray([PRODUCT_ID]), INAPP)
	_billing.call("query_purchases", INAPP)

func _on_product_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != RESPONSE_OK:
		return
	for d: Variant in response.get("product_details", []):
		if typeof(d) != TYPE_DICTIONARY or str((d as Dictionary).get("product_id", "")) != PRODUCT_ID:
			continue
		_product_ready = true
		var offers: Variant = (d as Dictionary).get("one_time_purchase_offer_details_list")
		if typeof(offers) == TYPE_ARRAY and not (offers as Array).is_empty():
			price_text = str(((offers as Array)[0] as Dictionary).get("formatted_price", ""))
		changed.emit()

# Both the start-up check (query_purchases) and a finished purchase sheet
# (on_purchase_updated, from_sheet) land here.
func _on_purchases(response: Dictionary, from_sheet: bool) -> void:
	var code: int = int(response.get("response_code", -1))
	if code != RESPONSE_OK:
		if not from_sheet:
			return   # Play didn't answer: keep what we had
		if code == ITEM_ALREADY_OWNED:
			_billing.call("query_purchases", INAPP)
		elif code == USER_CANCELED:
			purchase_result.emit(false, "")
		else:
			purchase_result.emit(false, tr("The purchase didn't go through. Please try again."))
		return
	var owned: bool = false
	var pending: bool = false
	for p: Variant in response.get("purchases", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var purchase: Dictionary = p
		var ids: Variant = purchase.get("product_ids", [])
		if typeof(ids) != TYPE_ARRAY and typeof(ids) != TYPE_PACKED_STRING_ARRAY:
			continue
		if not PRODUCT_ID in ids:
			continue
		match int(purchase.get("purchase_state", 0)):
			PURCHASED:
				owned = true
				# unacknowledged purchases are refunded by Google after 3 days
				if not bool(purchase.get("is_acknowledged", false)):
					_billing.call("acknowledge_purchase", str(purchase.get("purchase_token", "")))
			PENDING:
				pending = true
	if owned:
		_unlock("play")
		if from_sheet:
			purchase_result.emit(true, "")
	elif pending:
		if from_sheet:
			purchase_result.emit(false, tr("Payment pending: Versus and Co-op unlock as soon as it's complete."))
	elif not from_sheet and _source == "play":
		_set_source("")   # no longer owned (refunded)

func _unlock(source: String) -> void:
	# a code unlock is for good: a purchase found later doesn't replace it, so
	# a refund of that purchase can't lock the game again
	if _source == source or _source == "code":
		return
	_set_source(source)

func _set_source(source: String) -> void:
	_source = source
	unlocked = not source.is_empty()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("unlock", "source", source)
	cfg.save(SAVE_PATH)
	changed.emit()
