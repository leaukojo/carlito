class_name LevelPacks
extends Node
## Island levels ship in packs of their own beside the main .pck, fetched the first time one is
## opened, so the boot download carries no island (docs/deploying.md § Level packs). A pack is
## `<build>.<level id>.pck`, which CI exports as a delta patch against the main pack of the SAME
## build, so it mounts over that build only. It is kept in user:// under that name, and every
## pack from another build is deleted on the next fetch. dev and stable share one origin and so
## one user://: while they run different builds, visiting one deletes the other's packs, and
## they download again on the next visit there. Keeping them apart would mean a cache folder per
## channel, keyed off the page URL.
##
## The editor and a desktop run have every island on disk; `needs_fetch` is false there and
## nothing below runs.

## Emitted once per `fetch`: the pack is mounted, or it could not be downloaded or mounted.
signal finished(ok: bool)

## Every registered level under here ships in its own pack, and export_presets.cfg carries one
## "Web <id>" preset per such level (tests/test_export_filter.gd pins both).
const PACK_ROOT := "res://src/levels/island/"
const CACHE_DIR := "user://level_packs/"

var _http: HTTPRequest = null
var _path := ""  # where the pack being fetched lives once complete


## Whether `scene_path` ships in a level pack rather than in the main one.
static func is_packed(scene_path: String) -> bool:
	return scene_path.begins_with(PACK_ROOT)


## Whether `scene_path` needs its pack mounted before it can load: false off the web and once
## this session has mounted it.
static func needs_fetch(scene_path: String) -> bool:
	return is_packed(scene_path) and not ResourceLoader.exists(scene_path)


static func pack_name(build: String, level_id: String) -> String:
	return "%s.%s.pck" % [build, level_id]


## Cached files that belong to another build. A delta pack only mounts over the main pack it
## was exported against, so these can never be used again.
static func stale(files: PackedStringArray, build: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		if not f.begins_with(build + "."):
			out.append(f)
	return out


## Bytes of the download in flight; 0 when nothing is downloading.
func downloaded_bytes() -> int:
	return _http.get_downloaded_bytes() if _http != null else 0


## Mount `level_id`'s pack, downloading it first unless this build's copy is already cached.
## Answers through `finished`, synchronously when there was nothing to download.
func fetch(level_id: String) -> void:
	var build := _build_name()
	if build.is_empty():
		push_error("Level pack %s: no web build to fetch it from" % level_id)
		finished.emit(false)
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for f in stale(DirAccess.get_files_at(CACHE_DIR), build):
		DirAccess.remove_absolute(CACHE_DIR + f)
	_path = CACHE_DIR + pack_name(build, level_id)
	if FileAccess.file_exists(_path):
		_mount()
		return
	_http = HTTPRequest.new()
	# No `download_file`: on the web 4.7.1 reports success and writes nothing. The body is written
	# in one go on completion instead, so no half pack is ever left in the cache.
	# The browser has already gunzipped what GitHub Pages sends; HTTPRequest would gunzip the
	# same bytes again off the still-visible Content-Encoding and fail
	# (RESULT_BODY_DECOMPRESS_FAILED).
	_http.accept_gzip = false
	_http.request_completed.connect(_on_downloaded)
	add_child(_http)
	var err := _http.request(_url(pack_name(build, level_id)))
	if err != OK:
		push_error("Level pack %s: request failed to start (error %d)" % [level_id, err])
		_drop_request()
		finished.emit(false)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_drop_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Level pack download failed: %s (result %d, HTTP %d)"
				% [_path.get_file(), result, code])
		finished.emit(false)
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("Level pack %s: cannot write the cache (error %d)"
				% [_path.get_file(), FileAccess.get_open_error()])
		finished.emit(false)
		return
	f.store_buffer(body)
	f.close()
	_mount()


func _mount() -> void:
	var ok := ProjectSettings.load_resource_pack(_path)
	if not ok:
		# A cached pack that will not mount is damaged; drop it so the next attempt downloads.
		var f := FileAccess.open(_path, FileAccess.READ)
		push_error("Level pack %s (%d bytes) would not mount; removed"
				% [_path.get_file(), f.get_length() if f != null else -1])
		f = null
		DirAccess.remove_absolute(_path)
	finished.emit(ok)


func _drop_request() -> void:
	if _http != null:
		_http.queue_free()
		_http = null


## The export basename this page booted from (`c2-<sha>` from CI, `index` from a local
## export): the main pack is `<build>.pck` and every level pack sits beside it.
static func _build_name() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("GODOT_CONFIG.executable", true)
	return v if typeof(v) == TYPE_STRING else ""


## Absolute URL of a file beside the page: HTTPRequest takes no relative URL.
static func _url(file: String) -> String:
	var v: Variant = JavaScriptBridge.eval(
			"new URL(%s, document.baseURI).href" % JSON.stringify(file), true)
	return v if typeof(v) == TYPE_STRING else ""
