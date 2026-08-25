extends RefCounted
class_name TankPaintCatalog

const DEFAULT_SCALE := 1.0
const DEFAULT_STRENGTH := 0.86

static var _catalog: Array[Dictionary] = []
static var _textures: Dictionary = {}

static func configure_server(items: Array) -> void:
    _catalog.clear()
    _textures.clear()
    for raw in items:
        if not (raw is Dictionary):
            continue
        var item: Dictionary = (raw as Dictionary).duplicate(true)
        var paint_id: String = String(item.get("id", ""))
        if paint_id == "":
            continue
        item["scale"] = float(item.get("scale", DEFAULT_SCALE))
        item["strength"] = float(item.get("strength", DEFAULT_STRENGTH))
        _catalog.append(item)
    _catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
    )

static func install_texture(paint_id: String, texture: Texture2D) -> void:
    if paint_id != "" and texture != null:
        _textures[paint_id] = texture

static func has_texture(paint_id: String) -> bool:
    return _textures.has(paint_id) and _textures[paint_id] is Texture2D

static func scan() -> Array[Dictionary]:
    return _catalog.duplicate(true)

static func resolve(paint_id: String) -> Dictionary:
    for source in _catalog:
        if String(source.get("id", "")) == paint_id:
            var out: Dictionary = source.duplicate(true)
            if has_texture(paint_id):
                out["texture_object"] = _textures[paint_id]
            return out
    if not _catalog.is_empty():
        var fallback: Dictionary = _catalog[0].duplicate(true)
        var fallback_id: String = String(fallback.get("id", ""))
        if has_texture(fallback_id):
            fallback["texture_object"] = _textures[fallback_id]
        return fallback
    return {
        "id":"",
        "name":"Unpainted",
        "scale":DEFAULT_SCALE,
        "strength":0.0
    }
