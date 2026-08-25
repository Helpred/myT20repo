extends RefCounted
class_name CombatCatalog

static var _cached: Dictionary = {}
static var _hull_items: Array[Dictionary] = []
static var _turret_items: Array[Dictionary] = []

static func configure(server_data: Dictionary, hull_items: Array[Dictionary] = [], turret_items: Array[Dictionary] = []) -> void:
    _cached = server_data.duplicate(true)
    _hull_items.clear()
    _turret_items.clear()
    for item: Dictionary in hull_items:
        _hull_items.append(item.duplicate(true))
    for item: Dictionary in turret_items:
        _turret_items.append(item.duplicate(true))

static func data() -> Dictionary:
    return _cached

static func protocol() -> int:
    return int(_cached.get("protocol", 5))

static func default_hull_mod(hull_id: String) -> int:
    var hulls_value: Variant = _cached.get("hulls", {})
    if not (hulls_value is Dictionary):
        return 0
    var hulls: Dictionary = hulls_value
    var spec_value: Variant = hulls.get(hull_id, {})
    return int((spec_value as Dictionary).get("default_mod", 0)) if spec_value is Dictionary else 0

static func default_weapon_mod(weapon_id: String) -> int:
    var weapons_value: Variant = _cached.get("weapons", {})
    if not (weapons_value is Dictionary):
        return 0
    var weapons: Dictionary = weapons_value
    var spec_value: Variant = weapons.get(weapon_id, {})
    return int((spec_value as Dictionary).get("default_mod", 0)) if spec_value is Dictionary else 0

static func modifier(mod_level: int) -> Dictionary:
    var mods_value: Variant = _cached.get("modifiers", {})
    if not (mods_value is Dictionary):
        return {"hp":1.0, "damage":1.0, "reload":1.0, "fuel":1.0}
    var mods: Dictionary = mods_value
    var clamped_mod: int = clampi(mod_level, 0, 3)
    var value: Variant = mods.get(str(clamped_mod), {})
    return (value as Dictionary).duplicate(true) if value is Dictionary else {"hp":1.0, "damage":1.0, "reload":1.0, "fuel":1.0}

static func hull_spec(hull_id: String, mod_level: int = -1) -> Dictionary:
    var hulls_value: Variant = _cached.get("hulls", {})
    if not (hulls_value is Dictionary):
        return {}
    var hulls: Dictionary = hulls_value
    var source_value: Variant = hulls.get(hull_id, {})
    if not (source_value is Dictionary):
        return {}
    var source: Dictionary = source_value
    var resolved_mod: int = mod_level if mod_level >= 0 else int(source.get("default_mod", 0))
    resolved_mod = clampi(resolved_mod, 0, 3)
    var mult: Dictionary = modifier(resolved_mod)
    var out: Dictionary = source.duplicate(true)
    out["mod"] = resolved_mod
    out["max_hp"] = roundf(float(source.get("base_hp", 1.0)) * float(mult.get("hp", 1.0)))
    return out

static func weapon_spec(weapon_id: String, mod_level: int = -1) -> Dictionary:
    var weapons_value: Variant = _cached.get("weapons", {})
    if not (weapons_value is Dictionary):
        return {}
    var weapons: Dictionary = weapons_value
    var source_value: Variant = weapons.get(weapon_id, {})
    if not (source_value is Dictionary):
        return {}
    var source: Dictionary = source_value
    var resolved_mod: int = mod_level if mod_level >= 0 else int(source.get("default_mod", 0))
    resolved_mod = clampi(resolved_mod, 0, 3)
    var mult: Dictionary = modifier(resolved_mod)
    var out: Dictionary = source.duplicate(true)
    out["mod"] = resolved_mod
    if source.has("base_damage"):
        out["damage"] = roundf(float(source["base_damage"]) * float(mult.get("damage", 1.0)))
    if source.has("base_dps"):
        out["dps"] = float(source["base_dps"]) * float(mult.get("damage", 1.0))
    if source.has("base_reload"):
        out["reload"] = float(source["base_reload"]) * float(mult.get("reload", 1.0))
    if source.has("fuel_capacity"):
        out["fuel_max"] = float(source["fuel_capacity"]) * float(mult.get("fuel", 1.0))
    return out

static func visual_spec(category: String, item_id: String, mod_level: int) -> Dictionary:
    var source: Array[Dictionary] = _hull_items if category == "hull" else _turret_items
    for item: Dictionary in source:
        if String(item.get("id", "")) == item_id and int(item.get("mod", -1)) == mod_level:
            return item.duplicate(true)
    # A missing per-mod visual should not make a tank invisible. Fall back to the
    # first entry for the same module, then let tank.gd's legacy hardcoded path win.
    for item: Dictionary in source:
        if String(item.get("id", "")) == item_id:
            return item.duplicate(true)
    return {}
