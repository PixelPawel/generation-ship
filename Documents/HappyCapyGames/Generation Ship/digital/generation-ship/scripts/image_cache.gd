extends Node

signal all_loaded
signal progress_updated(loaded: int, total: int)

const MAX_CONCURRENT := 6
const CACHE_DIR := "user://card_cache"
const META_PATH := "user://card_cache/meta.json"

var _memory: Dictionary = {}
var _meta: Dictionary = {}
var _queue: Array[String] = []
var _active: int = 0
var _total: int = 0
var _loaded: int = 0

func _ready() -> void:
	_ensure_cache_dir()
	_load_meta()

func _ensure_cache_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))

func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var file: FileAccess = FileAccess.open(META_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) == OK:
		_meta = json.get_data()

func _save_meta() -> void:
	var file: FileAccess = FileAccess.open(META_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_meta, "\t"))
	file.close()

func preload_urls(urls: Array[String]) -> void:
	var added: int = 0
	for url: String in urls:
		if url.is_empty() or _memory.has(url):
			continue
		_queue.append(url)
		_memory[url] = null
		added += 1
	_total += added
	if added == 0:
		if _active == 0:
			all_loaded.emit()
		return
	_pump()

func _pump() -> void:
	while _active < MAX_CONCURRENT and not _queue.is_empty():
		_fetch(_queue.pop_front())

func _fetch(url: String) -> void:
	_active += 1
	var entry: Variant = _meta.get(url, null)
	var etag: String = ""
	var file_path: String = ""
	if entry != null:
		file_path = entry.get("file", "")
		etag = entry.get("etag", "")

	var headers: PackedStringArray = PackedStringArray()
	if not etag.is_empty() and not file_path.is_empty() and FileAccess.file_exists(file_path):
		headers.append("If-None-Match: " + etag)

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response.bind(url, http))
	http.request(url, headers)

func _on_response(_result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray, url: String, http: HTTPRequest) -> void:
	_active -= 1
	http.queue_free()

	if code == 304:
		_load_from_disk(url)
		_pump()
		return

	if code == 200:
		var img: Image = Image.new()
		var err: Error = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err == OK:
			_memory[url] = ImageTexture.create_from_image(img)
			var file_path: String = _cache_path(url)
			_save_to_disk(file_path, body)
			_meta[url] = { file = file_path, etag = _extract_etag(response_headers) }
			_save_meta()

	_loaded += 1
	progress_updated.emit(_loaded, _total)
	if _loaded >= _total:
		all_loaded.emit()
	else:
		_pump()

func _load_from_disk(url: String) -> void:
	var entry: Variant = _meta.get(url, null)
	var file_path: String = ""
	if entry != null:
		file_path = entry.get("file", "")
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		call_deferred("_finish_disk_load", url, null)
		return
	var captured_url: String = url
	var captured_path: String = file_path
	WorkerThreadPool.add_task(func() -> void:
		var file: FileAccess = FileAccess.open(captured_path, FileAccess.READ)
		if not file:
			call_deferred("_finish_disk_load", captured_url, null)
			return
		var data: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		var img: Image = Image.new()
		if img.load_png_from_buffer(data) == OK:
			call_deferred("_finish_disk_load", captured_url, img)
		else:
			call_deferred("_finish_disk_load", captured_url, null)
	)

func _finish_disk_load(url: String, img: Image) -> void:
	if img:
		_memory[url] = ImageTexture.create_from_image(img)
	_loaded += 1
	progress_updated.emit(_loaded, _total)
	if _loaded >= _total:
		all_loaded.emit()

func _save_to_disk(file_path: String, data: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()

func _cache_path(url: String) -> String:
	return CACHE_DIR + "/" + url.md5_text() + ".png"

func _extract_etag(headers: PackedStringArray) -> String:
	for header: String in headers:
		if header.to_lower().begins_with("etag:"):
			return header.substr(5).strip_edges()
	return ""

func get_texture(url: String) -> Texture2D:
	if url.begins_with("res://"):
		return load(url) as Texture2D
	return _memory.get(url, null) as Texture2D

func preload_local_art() -> void:
	# CardDatabase already resolved each card's current-locale print art into
	# local_art_path/adv_local_art_path (see card_database.gd) — just load
	# and cache it here, keyed the same way set_card_data() looks it up
	# (by image_url/adv_image_url, so the existing get_texture() call sites
	# in card.gd don't need to change).
	var cards: Array = []
	cards.append_array(CardDatabase.sectors)
	cards.append_array(CardDatabase.techs)
	cards.append_array(CardDatabase.expeditions)
	for cd: CardData in cards:
		_cache_local_art(cd.image_url, cd.local_art_path)
		_cache_local_art(cd.adv_image_url, cd.adv_local_art_path)

	# Deck-back images for tech and expedition have a load() fallback in
	# set_face_down() so no preloading needed here.

func _cache_local_art(cache_key: String, art_path: String) -> void:
	if cache_key.is_empty() or art_path.is_empty() or _memory.has(cache_key):
		return
	var tex: Texture2D = load(art_path) as Texture2D
	if tex:
		_memory[cache_key] = tex
