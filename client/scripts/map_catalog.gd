extends RefCounted
class_name TankiMapCatalog

# v18.18.29: server-authoritative maps + portable local authoring folder.
#
# Exported Godot projects package res:// into the executable/PCK, so res:// is not a
# writable user-map directory. Server maps are announced in the network catalog and
# downloaded into user://server_maps. Authors may put Arena-derived .tscn files into
# user://maps or (in exported builds) a maps/ directory next to the executable.

const MAP_DIR := "res://scenes/maps"
const USER_MAP_DIR := "user://maps"
const SERVER_CACHE_DIR := "user://server_maps"
const PREVIEW_DIR := "res://assets/ui/maps"
const DEFAULT_PREVIEW := "res://assets/ui/battles/kungur.jpg"

static var _server_maps: Array[Dictionary] = []
static var _server_by_id: Dictionary = {}
static var _downloaded_scenes: Dictionary = {}

static func configure_server(items: Array[Dictionary]) -> void:
	_server_maps.clear()
	_server_by_id.clear()
	for raw: Dictionary in items:
		var entry := raw.duplicate(true)
		var map_id := String(entry.get("id", "")).strip_edges().to_lower()
		if map_id == "":
			continue
		entry["id"] = map_id
		entry["source"] = "server"
		_server_maps.append(entry)
		_server_by_id[map_id] = entry

static func server_entry(map_id: String) -> Dictionary:
	var value: Variant = _server_by_id.get(map_id.strip_edges().to_lower(), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}

static func install_downloaded(map_id: String, scene_path: String, sha256: String = "") -> void:
	_downloaded_scenes[map_id.strip_edges().to_lower()] = {
		"scene": scene_path,
		"sha256": sha256.to_lower(),
	}

static func resolve_scene_path(map_id: String) -> String:
	var key := map_id.strip_edges().to_lower()
	var cached: Variant = _downloaded_scenes.get(key, {})
	if cached is Dictionary:
		var cached_path := String((cached as Dictionary).get("scene", ""))
		if cached_path != "" and FileAccess.file_exists(cached_path):
			return cached_path
	var server := server_entry(key)
	if not server.is_empty():
		var scene_name := String(server.get("scene", ""))
		if scene_name != "":
			var bundled := "%s/%s" % [MAP_DIR, scene_name]
			if ResourceLoader.exists(bundled):
				return bundled
	return ""

static func discover_maps() -> Array[Dictionary]:
	_ensure_authoring_folders()
	var merged: Dictionary = {}
	for server: Dictionary in _server_maps:
		merged[String(server.get("id", ""))] = server.duplicate(true)

	# In the editor, keep normal res:// discovery for convenient authoring. In exports
	# server catalog is primary because directory enumeration inside packed resources is
	# not a reliable user-map workflow.
	if OS.has_feature("editor"):
		for entry: Dictionary in _discover_directory(MAP_DIR, "project"):
			var key := String(entry.get("id", ""))
			if merged.has(key):
				var server_entry_value: Dictionary = merged[key]
				entry["server_sha256"] = String(server_entry_value.get("sha256", ""))
			merged[key] = entry

	for entry: Dictionary in _discover_directory(USER_MAP_DIR, "local"):
		var key := String(entry.get("id", ""))
		if merged.has(key):
			var server_entry_value: Dictionary = merged[key]
			entry["server_sha256"] = String(server_entry_value.get("sha256", ""))
		merged[key] = entry

	var portable_dir := _portable_map_dir()
	if portable_dir != "":
		for entry: Dictionary in _discover_directory(portable_dir, "local"):
			var key := String(entry.get("id", ""))
			if merged.has(key):
				var server_entry_value: Dictionary = merged[key]
				entry["server_sha256"] = String(server_entry_value.get("sha256", ""))
			merged[key] = entry

	var maps: Array[Dictionary] = []
	for value: Variant in merged.values():
		if value is Dictionary:
			maps.append((value as Dictionary).duplicate(true))
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a.get("id", "")) == "arena":
			return true
		if String(b.get("id", "")) == "arena":
			return false
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	return maps

static func by_id(maps: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in maps:
		out[String(entry.get("id", ""))] = entry
	return out

static func _discover_directory(path: String, source: String) -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return maps
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".tscn"):
			var scene_path := path.path_join(file_name)
			var stem := file_name.substr(0, file_name.length() - 5)
			var map_id := _map_id_from_stem(stem)
			var metadata := _read_scene_metadata(scene_path)
			if bool(metadata.get("enabled", true)):
				maps.append({
					"id": map_id,
					"name": String(metadata.get("name", _humanize_map_id(map_id))),
					"scene": scene_path,
					"preview": String(metadata.get("preview", _find_preview(path, stem, map_id))),
					"source": source,
					"sha256": FileAccess.get_sha256(scene_path).to_lower(),
					"bytes": _file_length(scene_path),
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	return maps

static func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length

static func _map_id_from_stem(stem: String) -> String:
	var clean := stem.strip_edges().to_lower()
	if clean == "arena_editable":
		return "arena"
	return clean

static func _humanize_map_id(map_id: String) -> String:
	if map_id == "arena":
		return "Арена"
	var words := map_id.replace("_", " ").replace("-", " ").split(" ", false)
	var out: PackedStringArray = []
	for word: String in words:
		out.append(word.capitalize())
	return " ".join(out)

static func _find_preview(base_dir: String, stem: String, map_id: String) -> String:
	for base: String in [base_dir.path_join(stem), "%s/%s" % [PREVIEW_DIR, map_id]]:
		for ext: String in ["png", "jpg", "jpeg", "webp"]:
			var candidate := "%s.%s" % [base, ext]
			if FileAccess.file_exists(candidate) or ResourceLoader.exists(candidate):
				return candidate
	return DEFAULT_PREVIEW

static func _read_scene_metadata(scene_path: String) -> Dictionary:
	var result := {"enabled": true}
	var file := FileAccess.open(scene_path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("metadata/tanki_map_name = "):
			result["name"] = _parse_quoted(line.trim_prefix("metadata/tanki_map_name = "))
		elif line.begins_with("metadata/tanki_map_preview = "):
			result["preview"] = _parse_quoted(line.trim_prefix("metadata/tanki_map_preview = "))
		elif line == "metadata/tanki_map_enabled = false":
			result["enabled"] = false
	file.close()
	return result

static func _parse_quoted(raw: String) -> String:
	var value := raw.strip_edges()
	var quote := "\""
	if value.length() >= 2 and value.begins_with(quote) and value.ends_with(quote):
		return value.substr(1, value.length() - 2).replace("\\\"", "\"").replace("\\n", "\n")
	return value

static func _portable_map_dir() -> String:
	if OS.has_feature("editor"):
		return ""
	var exe := OS.get_executable_path()
	if exe == "":
		return ""
	return exe.get_base_dir().path_join("maps")

static func _ensure_authoring_folders() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_MAP_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SERVER_CACHE_DIR))
	var portable := _portable_map_dir()
	if portable != "":
		DirAccess.make_dir_recursive_absolute(portable)
		var readme_path := portable.path_join("README_MAPS_RU.txt")
		if not FileAccess.file_exists(readme_path):
			var f := FileAccess.open(readme_path, FileAccess.WRITE)
			if f != null:
				f.store_string("Положите сюда Arena-derived .tscn карту. При создании битвы клиент автоматически загрузит её на сервер, а остальные игроки скачают её при входе.\nКарта должна использовать ресурсы стандартной Arena, уже встроенные в игру.\n")
				f.close()
