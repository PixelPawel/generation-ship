extends Node

signal all_loaded
signal progress_updated(loaded: int, total: int)

const MAX_CONCURRENT := 6
const CACHE_DIR := "res://assets/cards"
const META_PATH := "res://assets/cards/meta.json"

var _memory: Dictionary = {}   # url -> ImageTexture
var _meta: Dictionary = {}     # url -> { file: String, etag: String }
var _queue: Array[String] = []
var _active: int = 0
var _total: int = 0
var _loaded: int = 0

func _ready() -> void:
	_ensure_cache_dir()
	_load_meta()

func _ensure_cache_dir() -> void:
	var dir: DirAccess = DirAccess.open("res://assets")
	if dir and not dir.dir_exists("cards"):
		dir.make_dir("cards")

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
	for url: String in urls:
		if url.is_empty() or _memory.has(url):
			continue
		_queue.append(url)
		_memory[url] = null
	_total = _queue.size()
	_loaded = 0
	if _total == 0:
		all_loaded.emit()
		return
	_pump()

func _pump() -> void:
	while _active < MAX_CONCURRENT and not _queue.is_empty():
		_fetch(_queue.pop_front())

func _fetch(url: String) -> void:
	_active += 1
	var entry: Variant = _meta.get(url, null)
	if entry != null:
		var file_path: String = entry.get("file", "")
		if not file_path.is_empty() and FileAccess.file_exists(file_path):
			_load_from_disk(url)
			_loaded += 1
			progress_updated.emit(_loaded, _total)
			_active -= 1
			if _loaded >= _total:
				all_loaded.emit()
			else:
				_pump()
			return

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response.bind(url, http))
	http.request(url)

func _on_response(_result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray, url: String, http: HTTPRequest) -> void:
	_active -= 1
	http.queue_free()

	if code == 304:
		_load_from_disk(url)
	elif code == 200:
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
	if entry == null:
		return
	var file_path: String = entry.get("file", "")
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	var img: Image = Image.new()
	if img.load_png_from_buffer(data) == OK:
		_memory[url] = ImageTexture.create_from_image(img)

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

func get_texture(url: String) -> ImageTexture:
	return _memory.get(url, null) as ImageTexture
