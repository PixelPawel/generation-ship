extends Node

## Steam lobbies and Steam P2P through the GodotSteam GDExtension
## (addons/godotsteam, same build Generation Ship ships). Created at runtime
## by NetworkManager (no autoload of its own, so nothing in project.godot
## has to change). No class_name - preload it.
##
## App ID: Uprising has no Steam App ID yet, so development runs on 480
## (Valve's public "Spacewar" test app, from steam_appid.txt next to
## project.godot). Every lobby is tagged LOBBY_TAG_KEY = LOBBY_TAG and the
## lobby list filters on it, so other games testing on 480 never show up.
## When the real App ID exists: put it in steam_appid.txt and APP_ID below.
##
## Everything goes through Engine.get_singleton("Steam") rather than the
## global `Steam` identifier, so these scripts still compile when the
## extension isn't loaded (a fresh editor session, a platform without the
## binaries) - Steam features are then simply unavailable and the lobby
## falls back to LAN play.

const APP_ID: int = 480  # TODO: Uprising's own Steam App ID (and steam_appid.txt)
const LOBBY_TAG_KEY := "game"
const LOBBY_TAG := "uprising_digital"
const MAX_MEMBERS: int = 4

## Values of the GodotSteam enums used here, read from ClassDB when the
## extension is loaded (fallbacks are the Steamworks values).
const FALLBACK_CONSTANTS: Dictionary = {
	"STEAM_API_INIT_RESULT_OK": 0, "RESULT_OK": 1, "LOBBY_TYPE_FRIENDS_ONLY": 1, "LOBBY_TYPE_PUBLIC": 2,
	"LOBBY_COMPARISON_EQUAL": 0, "LOBBY_DISTANCE_FILTER_WORLDWIDE": 3, "CHAT_ROOM_ENTER_RESPONSE_SUCCESS": 1,
}

signal lobby_hosted(lobby_id: int)
signal lobby_entered(lobby_id: int, owner_steam_id: int)
signal lobby_list_received(lobbies: Array)  # [{id, host, members}]
signal lobby_failed(reason: String)
signal invite_accepted(lobby_id: int)

var steam: Object = null
var is_initialized: bool = false
var init_message: String = ""
var lobby_id: int = 0


func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		init_message = "Steam support isn't loaded (addons/godotsteam)."
		return
	steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("steamInitEx")
	if int(result.get("status", -1)) != _const("STEAM_API_INIT_RESULT_OK"):
		init_message = "Steam isn't running: %s" % str(result.get("verbal", "start Steam to play online"))
		return
	is_initialized = true
	# Start connecting to Steam's relay network early - P2P needs it.
	steam.call("initRelayNetworkAccess")
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("lobby_match_list", _on_lobby_match_list)
	steam.connect("join_requested", _on_join_requested)


func _process(_delta: float) -> void:
	if is_initialized:
		steam.call("run_callbacks")


func _const(name: String) -> int:
	if ClassDB.class_exists("Steam") and ClassDB.class_has_integer_constant("Steam", name):
		return ClassDB.class_get_integer_constant("Steam", name)
	return int(FALLBACK_CONSTANTS.get(name, 0))


func persona_name() -> String:
	if not is_initialized:
		return ""
	return str(steam.call("getPersonaName"))


func friend_name(steam_id: int) -> String:
	if not is_initialized:
		return ""
	return str(steam.call("getFriendPersonaName", steam_id))


func steam_id() -> int:
	return int(steam.call("getSteamID")) if is_initialized else 0


func peer_available() -> bool:
	return ClassDB.class_exists("SteamMultiplayerPeer")


## A SteamMultiplayerPeer hosting on virtual port 0, or null.
func make_host_peer() -> MultiplayerPeer:
	if not peer_available():
		return null
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null or int(peer.call("create_host", 0)) != OK:
		return null
	return peer


## A SteamMultiplayerPeer connected to the lobby owner, or null.
func make_client_peer(owner_steam_id: int) -> MultiplayerPeer:
	if not peer_available():
		return null
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null or int(peer.call("create_client", owner_steam_id, 0)) != OK:
		return null
	return peer


func host_lobby(friends_only: bool) -> void:
	if not is_initialized:
		lobby_failed.emit(init_message)
		return
	steam.call("createLobby", _const("LOBBY_TYPE_FRIENDS_ONLY") if friends_only else _const("LOBBY_TYPE_PUBLIC"), MAX_MEMBERS)


func request_lobby_list() -> void:
	if not is_initialized:
		lobby_failed.emit(init_message)
		return
	steam.call("addRequestLobbyListDistanceFilter", _const("LOBBY_DISTANCE_FILTER_WORLDWIDE"))
	steam.call("addRequestLobbyListStringFilter", LOBBY_TAG_KEY, LOBBY_TAG, _const("LOBBY_COMPARISON_EQUAL"))
	steam.call("requestLobbyList")


func join_lobby(id: int) -> void:
	if not is_initialized:
		lobby_failed.emit(init_message)
		return
	steam.call("joinLobby", id)


func leave_lobby() -> void:
	if is_initialized and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
	lobby_id = 0


func set_lobby_joinable(joinable: bool) -> void:
	if is_initialized and lobby_id != 0:
		steam.call("setLobbyJoinable", lobby_id, joinable)


## Opens the Steam overlay's friend-invite dialog for this lobby.
func invite_friends() -> void:
	if is_initialized and lobby_id != 0:
		steam.call("activateGameOverlayInviteDialog", lobby_id)


func _on_lobby_created(connect_result: int, id: int) -> void:
	if connect_result != _const("RESULT_OK"):
		lobby_failed.emit("Steam couldn't create the lobby (code %d)." % connect_result)
		return
	lobby_id = id
	steam.call("setLobbyData", id, LOBBY_TAG_KEY, LOBBY_TAG)
	steam.call("setLobbyData", id, "host", persona_name())
	lobby_hosted.emit(id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != _const("CHAT_ROOM_ENTER_RESPONSE_SUCCESS"):
		lobby_failed.emit("Couldn't join that lobby (it may be full or closed).")
		return
	lobby_id = id
	lobby_entered.emit(id, int(steam.call("getLobbyOwner", id)))


func _on_lobby_match_list(lobbies: Array) -> void:
	var out: Array = []
	for l: Variant in lobbies:
		var id: int = int(l)
		out.append({
			"id": id,
			"host": str(steam.call("getLobbyData", id, "host")),
			"members": int(steam.call("getNumLobbyMembers", id)),
		})
	lobby_list_received.emit(out)


func _on_join_requested(id: int, _friend_id: int) -> void:
	invite_accepted.emit(id)
