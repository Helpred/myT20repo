extends Node
class_name TankiNetworkClient

signal status_changed(text: String)
signal welcomed(player_id: int)
signal auth_result(ok: bool, reason: String, profile: Dictionary, catalog: Dictionary, chat_history: Array)
signal profile_received(profile: Dictionary)
signal chat_received(data: Dictionary)
signal purchase_result(ok: bool, reason: String, profile: Dictionary)
signal upgrade_result(ok: bool, reason: String, profile: Dictionary)
signal equip_result(ok: bool, reason: String, profile: Dictionary)
signal battle_joined(ok: bool, build: Dictionary, spawn_index: int, combat: Dictionary, match: Dictionary, reason: String)
signal battles_received(battles: Array)
signal battle_created(ok: bool, battle: Dictionary, reason: String)
signal battle_left()
signal bot_result(ok: bool, reason: String)
signal bot_control_received(data: Dictionary)
signal snapshot_received(players: Array)
signal shot_received(data: Dictionary)
signal combat_event(data: Dictionary)
signal respawn_requested(spawn_index: int, combat: Dictionary)
signal match_state_received(data: Dictionary)
signal round_end_received(data: Dictionary)
signal round_start_received(data: Dictionary)
signal supply_snapshot_received(supplies: Array)
signal supply_event_received(data: Dictionary)
signal connection_lost()

const PROTOCOL: int = 20

var host: String = "127.0.0.1"
var port: int = 9100
var map_id: String = "lobby"
var current_map_key: String = "arena"
var player_id: int = -1
var is_welcomed: bool = false
var is_authenticated: bool = false
var server_catalog: Dictionary = {}
var profile: Dictionary = {}
var asset_port: int = 0
var map_upload_token: String = ""
var current_map_asset: Dictionary = {}

var _peer: PacketPeerUDP
var _hello_elapsed: float = 999.0
var _heartbeat_elapsed: float = 0.0
var _last_rx_ms: int = 0
var _profile_sync_elapsed: float = 0.0
var _profile_sync_seq: int = -1
var _next_seq: int = 1
var _pending: Dictionary = {}

func connect_to_server(new_host: String, new_port: int, _new_map_id: String = "lobby") -> void:
    close()
    host = new_host.strip_edges()
    port = new_port
    map_id = "lobby"
    current_map_key = "arena"
    _peer = PacketPeerUDP.new()
    var err: Error = _peer.connect_to_host(host, port)
    if err != OK:
        status_changed.emit("UDP error: %s" % error_string(err))
        return
    _hello_elapsed = 999.0
    _heartbeat_elapsed = 0.0
    _last_rx_ms = Time.get_ticks_msec()
    status_changed.emit("Подключение к %s:%d…" % [host, port])

func close() -> void:
    if _peer != null:
        if is_welcomed:
            _send({"type":"bye"})
        _peer.close()
    _peer = null
    is_welcomed = false
    is_authenticated = false
    player_id = -1
    map_id = "lobby"
    current_map_key = "arena"
    server_catalog.clear()
    profile.clear()
    asset_port = 0
    map_upload_token = ""
    current_map_asset.clear()
    _pending.clear()
    _profile_sync_elapsed = 0.0
    _profile_sync_seq = -1

func _exit_tree() -> void:
    close()

func _process(delta: float) -> void:
    if _peer == null:
        return
    _hello_elapsed += delta
    _heartbeat_elapsed += delta
    if not is_welcomed and _hello_elapsed >= 0.65:
        _hello_elapsed = 0.0
        _send({"type":"hello", "protocol":PROTOCOL, "client":"godot", "map":"lobby"})
    if is_welcomed and _heartbeat_elapsed >= 1.0:
        _heartbeat_elapsed = 0.0
        _send({"type":"heartbeat"})
    while _peer.get_available_packet_count() > 0:
        var raw: PackedByteArray = _peer.get_packet()
        _last_rx_ms = Time.get_ticks_msec()
        var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
        if parsed is Dictionary:
            _handle_message(parsed as Dictionary)
    if _profile_sync_seq >= 0 and not _pending.has(_profile_sync_seq):
        _profile_sync_seq = -1
    if is_authenticated and map_id != "lobby":
        _profile_sync_elapsed += delta
        if _profile_sync_elapsed >= 2.0:
            _profile_sync_elapsed = 0.0
            request_profile_sync()
    else:
        _profile_sync_elapsed = 0.0
    _retry_reliable()
    if is_welcomed and Time.get_ticks_msec() - _last_rx_ms > 6000:
        is_welcomed = false
        is_authenticated = false
        player_id = -1
        status_changed.emit("Сервер не отвечает")
        connection_lost.emit()
        _hello_elapsed = 999.0

func register_account(login: String, password: String) -> void:
    if not is_welcomed:
        return
    _send_reliable({"type":"register", "login":login, "password":password})

func login_account(login: String, password: String) -> void:
    if not is_welcomed:
        return
    _send_reliable({"type":"login", "login":login, "password":password})

func send_chat(text: String) -> void:
    if not is_authenticated:
        return
    _send({"type":"chat", "text":text})

func purchase_item(category: String, item_id: String, mod_level: int = 0) -> void:
    if not is_authenticated:
        return
    _send_reliable({"type":"purchase", "category":category, "id":item_id, "mod":mod_level})

func upgrade_item(category: String, item_id: String, target_mod: int) -> void:
    if not is_authenticated:
        return
    _send_reliable({"type":"upgrade", "category":category, "id":item_id, "mod":clampi(target_mod, 1, 3)})

func equip_item(category: String, item_id: String, mod_level: int = 0) -> void:
    if not is_authenticated:
        return
    _send_reliable({"type":"equip", "category":category, "id":item_id, "mod":mod_level})

func request_battles() -> void:
    if not is_authenticated:
        return
    _send_reliable({"type":"list_battles"})

func request_profile_sync() -> void:
    if not is_authenticated:
        return
    if _profile_sync_seq >= 0 and _pending.has(_profile_sync_seq):
        return
    _profile_sync_seq = _send_reliable({"type":"get_profile"})

func create_battle(name: String, map_key: String, kill_limit: int, max_players: int = 10, min_rank: int = 0, max_rank: int = 26) -> void:
    if not is_authenticated:
        return
    _send_reliable({
        "type":"create_battle",
        "name":name,
        "map":map_key,
        "kill_limit":clampi(kill_limit, 1, 999),
        "max_players":clampi(max_players, 2, 32),
        "min_rank":clampi(min_rank, 0, 26),
        "max_rank":clampi(max_rank, 0, 26)
    })

func join_battle(battle_id: int) -> void:
    if not is_authenticated or battle_id <= 0:
        return
    _send_reliable({"type":"join_battle", "battle_id":battle_id})

func leave_battle() -> void:
    if not is_authenticated:
        return
    _send_reliable({"type":"leave_battle"})

func add_bot(battle_id: int) -> void:
    if not is_authenticated or battle_id <= 0:
        return
    _send_reliable({"type":"add_bot", "battle_id":battle_id})

func remove_bot(battle_id: int) -> void:
    if not is_authenticated or battle_id <= 0:
        return
    _send_reliable({"type":"remove_bot", "battle_id":battle_id})

func send_bot_state(bot_id: int, state: Dictionary) -> void:
    if not is_authenticated or map_id == "lobby" or bot_id <= 0:
        return
    var msg: Dictionary = state.duplicate(true)
    msg["type"] = "bot_state"
    msg["bot_id"] = bot_id
    _send(msg)

func send_bot_shot(bot_id: int, payload: Dictionary) -> int:
    if not is_authenticated or map_id == "lobby" or bot_id <= 0:
        return -1
    var msg: Dictionary = payload.duplicate(true)
    msg["type"] = "bot_shot"
    msg["bot_id"] = bot_id
    return _send_reliable(msg)

func send_state(state: Dictionary) -> void:
    if not is_authenticated or map_id == "lobby":
        return
    var msg: Dictionary = state.duplicate(true)
    msg["type"] = "state"
    _send(msg)

func send_shot(payload: Dictionary) -> int:
    if not is_authenticated or map_id == "lobby":
        return -1
    var msg: Dictionary = payload.duplicate(true)
    msg["type"] = "shot"
    return _send_reliable(msg)

func request_self_destruct() -> int:
    if not is_authenticated or map_id == "lobby":
        return -1
    return _send_reliable({"type":"self_destruct"})

func request_bot_self_destruct(bot_id: int) -> int:
    if not is_authenticated or map_id == "lobby" or bot_id <= 0:
        return -1
    return _send_reliable({"type":"bot_self_destruct", "bot_id":bot_id})

func request_supply_pickup(supply_id: int) -> void:
    if not is_authenticated or not map_id.begins_with("arena") or supply_id < 0:
        return
    _send({"type":"pickup_supply", "id":supply_id})

func _send_reliable(msg: Dictionary) -> int:
    var seq: int = _next_seq
    _next_seq += 1
    msg["seq"] = seq
    _pending[seq] = {"msg":msg.duplicate(true), "sent_ms":0, "tries":0}
    _transmit_pending(seq)
    return seq

func _retry_reliable() -> void:
    var now: int = Time.get_ticks_msec()
    for seq_value: Variant in _pending.keys():
        var seq: int = int(seq_value)
        var item_value: Variant = _pending.get(seq, {})
        if not (item_value is Dictionary):
            continue
        var item: Dictionary = item_value as Dictionary
        if now - int(item.get("sent_ms", 0)) >= 250:
            if int(item.get("tries", 0)) >= 16:
                _pending.erase(seq)
                continue
            _transmit_pending(seq)

func _transmit_pending(seq: int) -> void:
    if not _pending.has(seq):
        return
    var item_value: Variant = _pending.get(seq, {})
    if not (item_value is Dictionary):
        return
    var item: Dictionary = item_value as Dictionary
    var msg_value: Variant = item.get("msg", {})
    if msg_value is Dictionary:
        _send(msg_value as Dictionary)
    item["sent_ms"] = Time.get_ticks_msec()
    item["tries"] = int(item.get("tries", 0)) + 1
    _pending[seq] = item

func _send(msg: Dictionary) -> void:
    if _peer == null:
        return
    _peer.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _finish_seq(msg: Dictionary) -> void:
    var seq: int = int(msg.get("seq", -1))
    if seq >= 0:
        _pending.erase(seq)

func _dict_value(value: Variant) -> Dictionary:
    if value is Dictionary:
        return (value as Dictionary).duplicate(true)
    return {}

func _array_value(value: Variant) -> Array:
    if value is Array:
        return (value as Array).duplicate(true)
    return []

func _handle_message(msg: Dictionary) -> void:
    var kind: String = String(msg.get("type", ""))
    match kind:
        "welcome":
            player_id = int(msg.get("player_id", -1))
            is_welcomed = player_id >= 0
            map_id = String(msg.get("map", "lobby"))
            asset_port = int(msg.get("asset_port", port + 1))
            map_upload_token = String(msg.get("map_upload_token", ""))
            status_changed.emit("Сервер подключён")
            welcomed.emit(player_id)
        "protocol_error":
            status_changed.emit("Несовместимый протокол. Сервер ожидает v%d" % int(msg.get("expected", -1)))
        "auth_result":
            _finish_seq(msg)
            var auth_ok: bool = bool(msg.get("ok", false))
            var auth_profile: Dictionary = _dict_value(msg.get("profile", {}))
            var auth_catalog: Dictionary = _dict_value(msg.get("catalog", {}))
            var auth_history: Array = _array_value(msg.get("chat_history", []))
            if auth_ok:
                is_authenticated = true
                profile = auth_profile.duplicate(true)
                server_catalog = auth_catalog.duplicate(true)
                map_id = "lobby"
            auth_result.emit(auth_ok, String(msg.get("reason", "")), auth_profile, auth_catalog, auth_history)
        "profile":
            var profile_seq: int = int(msg.get("seq", -1))
            _finish_seq(msg)
            if profile_seq >= 0 and profile_seq == _profile_sync_seq:
                _profile_sync_seq = -1
                _profile_sync_elapsed = 0.0
            var incoming_profile: Dictionary = _dict_value(msg.get("profile", {}))
            if not incoming_profile.is_empty():
                profile = incoming_profile.duplicate(true)
                profile_received.emit(incoming_profile)
        "chat":
            chat_received.emit(msg)
        "purchase_result":
            _finish_seq(msg)
            var purchase_profile: Dictionary = _dict_value(msg.get("profile", {}))
            if not purchase_profile.is_empty():
                profile = purchase_profile.duplicate(true)
            purchase_result.emit(bool(msg.get("ok", false)), String(msg.get("reason", "")), purchase_profile)
        "upgrade_result":
            _finish_seq(msg)
            var upgrade_profile: Dictionary = _dict_value(msg.get("profile", {}))
            if not upgrade_profile.is_empty():
                profile = upgrade_profile.duplicate(true)
            upgrade_result.emit(bool(msg.get("ok", false)), String(msg.get("reason", "")), upgrade_profile)
        "equip_result":
            _finish_seq(msg)
            var equip_profile: Dictionary = _dict_value(msg.get("profile", {}))
            if not equip_profile.is_empty():
                profile = equip_profile.duplicate(true)
            equip_result.emit(bool(msg.get("ok", false)), String(msg.get("reason", "")), equip_profile)
        "battles":
            _finish_seq(msg)
            var incoming_maps: Array = _array_value(msg.get("maps", []))
            if not incoming_maps.is_empty():
                server_catalog["maps"] = incoming_maps.duplicate(true)
            battles_received.emit(_array_value(msg.get("battles", [])))
        "battle_created":
            _finish_seq(msg)
            battle_created.emit(
                bool(msg.get("ok", false)),
                _dict_value(msg.get("battle", {})),
                String(msg.get("reason", ""))
            )
        "battle_joined":
            _finish_seq(msg)
            var battle_ok: bool = bool(msg.get("ok", false))
            if battle_ok:
                map_id = String(msg.get("map", "arena"))
                current_map_key = String(msg.get("map_key", "arena"))
                current_map_asset = _dict_value(msg.get("map_asset", {}))
            battle_joined.emit(
                battle_ok,
                _dict_value(msg.get("build", {})),
                int(msg.get("spawn_index", -1)),
                _dict_value(msg.get("combat", {})),
                _dict_value(msg.get("match", {})),
                String(msg.get("reason", ""))
            )
        "battle_left":
            _finish_seq(msg)
            map_id = "lobby"
            current_map_key = "arena"
            current_map_asset.clear()
            battle_left.emit()
        "bot_result":
            _finish_seq(msg)
            bot_result.emit(bool(msg.get("ok", false)), String(msg.get("reason", "")))
        "bot_control":
            bot_control_received.emit(msg)
        "snapshot":
            var players: Array = _array_value(msg.get("players", []))
            var supplies: Array = _array_value(msg.get("supplies", []))
            snapshot_received.emit(players)
            supply_snapshot_received.emit(supplies)
        "shot":
            shot_received.emit(msg)
        "combat":
            combat_event.emit(msg)
        "respawn":
            var combat_value: Dictionary = _dict_value(msg.get("combat", {}))
            respawn_requested.emit(int(msg.get("spawn_index", 0)), combat_value)
        "match_state":
            match_state_received.emit(msg)
        "round_end":
            round_end_received.emit(msg)
        "round_start":
            round_start_received.emit(msg)
        "supply_event":
            supply_event_received.emit(msg)
        "session_replaced":
            is_authenticated = false
            profile.clear()
            server_catalog.clear()
            status_changed.emit("Аккаунт вошёл с другого клиента")
            connection_lost.emit()
        "ack":
            _pending.erase(int(msg.get("seq", -1)))
        "pong":
            pass
