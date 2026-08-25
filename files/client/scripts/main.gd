extends Node

const NetworkClientScript = preload("res://scripts/network_client.gd")
const TankScript = preload("res://scripts/tank.gd")
const PaintCatalogScript = preload("res://scripts/paint_catalog.gd")
const CombatCatalogScript = preload("res://scripts/combat_catalog.gd")
const SupplyDropScript = preload("res://scripts/supply_drop.gd")
const BonusSound: AudioStream = preload("res://assets/bonuses/bonus.mp3")
const ArenaEditableScene = preload("res://scenes/maps/arena_editable.tscn")
const CrystalTexture: Texture2D = preload("res://assets/ui/crystal.png")
const RANK_ICON_DIR := "res://assets/ui/ranks"
const RANK_SMALL_ICON_DIR := "res://assets/ui/ranks_small"
const BattleMapPreview: Texture2D = preload("res://assets/ui/battles/kungur.jpg")
const BattleTankPreview: Texture2D = preload("res://assets/ui/battles/wasp_preview.png")
const ClassicLobbyTexture: Texture2D = preload("res://assets/ui/classic/classic_battle_menu.png")
const ClassicCrystalClusterTexture: Texture2D = preload("res://assets/ui/classic/classic_crystals.png")
const ClassicGarageIconTexture: Texture2D = preload("res://assets/ui/classic/classic_garage_icon.png")
const ClassicBattlesIconTexture: Texture2D = preload("res://assets/ui/classic/classic_battles_icon.png")
const LEGACY_UI := "res://assets/ui/legacy/"

const SPAWNS: Array[Dictionary] = [
	{"p":Vector3(4.14, 10.0, 15.99), "yaw":-deg_to_rad(111.0)},
	{"p":Vector3(-32.27, 10.0, -46.85), "yaw":-deg_to_rad(-147.0)},
	{"p":Vector3(-81.92, 10.0, 30.58), "yaw":-deg_to_rad(-40.0)}
]
# Three virtual lanes around every editable Spawn_0..2 marker. This gives nine
# independent server spawn slots without modifying arena_editable.tscn or its
# baked LightmapGI data. Moving a base marker in the editor moves all its lanes.
const SPAWN_LATERAL_OFFSETS: Array[float] = [0.0, -5.2, 5.2]
const SPAWN_SLOT_COUNT: int = 9

var net: TankiNetworkClient
var tanks: Dictionary = {}
var local_build: Dictionary = {}
var local_spawned: bool = false
var profile: Dictionary = {}
var server_catalog: Dictionary = {}
var _hull_catalog: Array[Dictionary] = []
var _turret_catalog: Array[Dictionary] = []
var _paint_catalog: Array[Dictionary] = []
var _paint_previews: Dictionary = {}
var _economy: Dictionary = {}
var _catalog_ready: bool = false
var _pending_snapshot: Array = []
var _match_state: Dictionary = {}
var _in_battle: bool = false
var _world_root: Node3D

var _pending_auth_kind: String = ""
var _pending_auth_login: String = ""
var _pending_auth_password: String = ""

var _auth_screen: Control
var _auth_login: LineEdit
var _auth_password: LineEdit
var _auth_repeat: LineEdit
var _auth_host: LineEdit
var _auth_port: LineEdit
var _auth_status: Label

var _lobby_screen: Control
var _lobby_stage: Control
var _lobby_rank: Label
var _lobby_xp: ProgressBar
var _lobby_crystals: Label
var _lobby_loadout: Label
var _lobby_status: Label
var _play_button: Button
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _lobby_rank_icon: TextureRect
var _battle_map_card: PanelContainer
var _battle_map_title: Label
var _battle_browser_content: Control
var _lobby_search: LineEdit
var _battle_map_selected: bool = true
var _battle_list: VBoxContainer
var _battle_info_label: Label
var _battle_preview: TextureRect
var _battle_create_overlay: Control
var _battles: Array[Dictionary] = []
var _selected_battle_id: int = -1

var _garage_screen: Control
var _garage_grid: GridContainer
var _garage_title: Label
var _garage_crystals: Label
var _garage_category: String = "hull"
var _garage_tab_buttons: Dictionary = {}
var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_pivot: Node3D
var _preview_tank: Node

var _battle_hud: Control
var _battle_rank: Label
var _battle_crystals: Label
var _battle_kills: Label
var _battle_score: Label
var _battle_fund: Label
var _battle_leader_kills: Label
var _battle_kill_progress: ProgressBar
var _battle_hint: Label
var _battle_action_feed: VBoxContainer
var _battle_action_rows: Array[Dictionary] = []
var _battle_gold_notice: Label
var _battle_gold_notice_hide_at_ms: int = 0

var _profile_strip: Control
var _global_rank_icon: TextureRect
var _global_rank_name: Label
var _global_xp: ProgressBar
var _global_xp_text: Label
var _global_crystals: Label

var _round_overlay: Control
var _round_results: Label
var _round_countdown: Label
var _round_restart_deadline_ms: int = 0
var _supplies: Dictionary = {}
var _battle_supplies: Label
var _supply_probe_elapsed: float = 0.0

func _ready() -> void:
	_build_ui()
	net = NetworkClientScript.new()
	add_child(net)
	net.status_changed.connect(_on_status)
	net.welcomed.connect(_on_welcome)
	net.auth_result.connect(_on_auth_result)
	net.profile_received.connect(_on_profile_received)
	net.chat_received.connect(_on_chat_received)
	net.purchase_result.connect(_on_purchase_result)
	net.equip_result.connect(_on_equip_result)
	net.battle_joined.connect(_on_battle_joined)
	net.battle_left.connect(_on_battle_left)
	net.battles_received.connect(_on_battles_received)
	net.battle_created.connect(_on_battle_created)
	net.snapshot_received.connect(_on_snapshot)
	net.shot_received.connect(_on_shot)
	net.combat_event.connect(_on_combat_event)
	net.respawn_requested.connect(_on_respawn_requested)
	net.match_state_received.connect(_on_match_state)
	net.round_end_received.connect(_on_round_end)
	net.round_start_received.connect(_on_round_start)
	net.supply_snapshot_received.connect(_on_supply_snapshot)
	net.supply_event_received.connect(_on_supply_event)
	net.connection_lost.connect(_on_connection_lost)

	var endpoint: Array = _command_endpoint()
	_auth_host.text = String(endpoint[0])
	_auth_port.text = str(int(endpoint[1]))
	_show_auth()

func _process(delta: float) -> void:
	if _lobby_screen != null and _lobby_screen.visible:
		_update_lobby_stage_layout()
	_update_battle_messages()
	if _garage_screen != null and _garage_screen.visible and _preview_pivot != null and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += delta * 0.38
	if _round_overlay != null and _round_overlay.visible and _round_restart_deadline_ms > 0:
		var remaining_ms: int = maxi(0, _round_restart_deadline_ms - Time.get_ticks_msec())
		_round_countdown.text = "Новый бой через %.1f сек" % (float(remaining_ms) / 1000.0)
	if _in_battle:
		_supply_probe_elapsed += delta
		if _supply_probe_elapsed >= 0.18:
			_supply_probe_elapsed = 0.0
			_probe_supply_pickups()
		_refresh_supply_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		if _in_battle:
			_set_local_match_controls(false)
			_battle_hint.text = "Выход из боя…"
			net.leave_battle()
			get_viewport().set_input_as_handled()
		elif _garage_screen != null and _garage_screen.visible:
			_show_lobby()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)
	_auth_screen = _build_auth_screen(canvas)
	_lobby_screen = _build_lobby_screen(canvas)
	_garage_screen = _build_garage_screen(canvas)
	_battle_hud = _build_battle_hud(canvas)
	_round_overlay = _build_round_overlay(canvas)
	_profile_strip = _build_profile_strip(canvas)

func _background(parent: Control, opacity: float = 0.88) -> void:
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.035, 0.028, 0.025, opacity)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

func _panel_style(alpha: float = 0.90) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.058, 0.050, alpha)
	style.border_color = Color(0.46, 0.36, 0.27, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

func _button(text_value: String, min_size: Vector2 = Vector2(0, 44)) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 17)
	return button

func _classic_button_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.30, 0.29, 0.12, 0.96) if active else Color(0.070, 0.060, 0.050, 0.96)
	style.border_color = Color(0.62, 0.55, 0.23, 0.96) if active else Color(0.31, 0.27, 0.21, 0.94)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _classic_nav_button(text_value: String, active: bool = false) -> Button:
	var button := _button(text_value, Vector2(180, 58))
	button.add_theme_stylebox_override("normal", _classic_button_style(active))
	button.add_theme_stylebox_override("hover", _classic_button_style(true))
	button.add_theme_stylebox_override("pressed", _classic_button_style(true))
	button.add_theme_font_size_override("font_size", 18)
	return button

func _build_classic_nav(parent: Control, active: String) -> void:
	var panel := PanelContainer.new()
	panel.set_anchor(SIDE_LEFT, 0.0)
	panel.set_anchor(SIDE_TOP, 0.0)
	panel.set_anchor(SIDE_RIGHT, 1.0)
	panel.set_anchor(SIDE_BOTTOM, 0.0)
	panel.offset_left = 18.0
	panel.offset_top = 88.0
	panel.offset_right = -18.0
	panel.offset_bottom = 154.0
	panel.add_theme_stylebox_override("panel", _panel_style(0.96))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var battles := _classic_nav_button("БИТВЫ", active == "battles")
	battles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battles.pressed.connect(_show_lobby)
	row.add_child(battles)
	var garage := _classic_nav_button("ГАРАЖ", active == "garage")
	garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.pressed.connect(_garage_pressed)
	row.add_child(garage)
	var communities := _classic_nav_button("СООБЩЕСТВА", false)
	communities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	communities.disabled = true
	communities.tooltip_text = "Раздел будет добавлен позже"
	row.add_child(communities)

func _title(text_value: String, size: int = 24) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label

func _profile_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.030, 0.96)
	style.border_color = Color(0.25, 0.20, 0.14, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _xp_bar_background_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.17, 0.055, 0.98)
	style.border_color = Color(0.17, 0.125, 0.075, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _xp_bar_fill_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# Olive-gold, matching the 2011 rank progress strip instead of a flat yellow bar.
	style.bg_color = Color(0.57, 0.53, 0.075, 0.99)
	style.border_color = Color(0.83, 0.73, 0.16, 1.0)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _currency_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.043, 0.041, 0.97)
	style.border_color = Color(0.29, 0.27, 0.24, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _build_profile_strip(canvas: CanvasLayer) -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	canvas.add_child(root)

	# Classic profile cluster belongs in the upper-left corner, matching the old
	# Tanki layout and leaving the right side free for game information.
	var cluster := Control.new()
	cluster.anchor_left = 0.0
	cluster.anchor_right = 0.0
	cluster.offset_left = 8.0
	cluster.offset_right = 356.0
	cluster.offset_top = 8.0
	cluster.offset_bottom = 92.0
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cluster)

	_global_rank_icon = TextureRect.new()
	_global_rank_icon.position = Vector2(0, 2)
	_global_rank_icon.size = Vector2(64, 76)
	_global_rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_global_rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_global_rank_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(_global_rank_icon)

	_global_rank_name = Label.new()
	_global_rank_name.position = Vector2(70, 0)
	_global_rank_name.size = Vector2(278, 23)
	_global_rank_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_global_rank_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_global_rank_name.add_theme_font_size_override("font_size", 15)
	_global_rank_name.add_theme_color_override("font_color", Color(0.98, 0.95, 0.84))
	_global_rank_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_global_rank_name.add_theme_constant_override("shadow_offset_x", 1)
	_global_rank_name.add_theme_constant_override("shadow_offset_y", 1)
	_global_rank_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(_global_rank_name)

	var xp_frame := Control.new()
	xp_frame.position = Vector2(70, 24)
	xp_frame.size = Vector2(278, 31)
	xp_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cluster.add_child(xp_frame)

	_global_xp = ProgressBar.new()
	_global_xp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_global_xp.show_percentage = false
	_global_xp.min_value = 0.0
	_global_xp.max_value = 1.0
	_global_xp.value = 0.0
	_global_xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_global_xp.add_theme_stylebox_override("background", _xp_bar_background_style())
	_global_xp.add_theme_stylebox_override("fill", _xp_bar_fill_style())
	xp_frame.add_child(_global_xp)

	# Use a real Unicode coin instead of the temporary PNG created in v18.9.
	var coin := Label.new()
	coin.text = "🪙"
	coin.position = Vector2(6, 0)
	coin.size = Vector2(28, 31)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin.add_theme_font_size_override("font_size", 17)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_frame.add_child(coin)

	_global_xp_text = Label.new()
	_global_xp_text.text = "0 / 100"
	_global_xp_text.position = Vector2(35, 0)
	_global_xp_text.size = Vector2(235, 31)
	_global_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_global_xp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_global_xp_text.add_theme_font_size_override("font_size", 14)
	_global_xp_text.add_theme_color_override("font_color", Color(0.96, 0.96, 0.90))
	_global_xp_text.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_global_xp_text.add_theme_constant_override("shadow_offset_x", 1)
	_global_xp_text.add_theme_constant_override("shadow_offset_y", 1)
	_global_xp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_frame.add_child(_global_xp_text)

	# Crystals stay as their original blue icon, but the row is deliberately shorter
	# so the player identity and progress remain the main focus.
	var currency_panel := PanelContainer.new()
	currency_panel.position = Vector2(70, 58)
	currency_panel.custom_minimum_size = Vector2(128, 26)
	currency_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_panel.add_theme_stylebox_override("panel", _currency_panel_style())
	cluster.add_child(currency_panel)

	var currency_margin := MarginContainer.new()
	currency_margin.add_theme_constant_override("margin_left", 6)
	currency_margin.add_theme_constant_override("margin_right", 7)
	currency_margin.add_theme_constant_override("margin_top", 2)
	currency_margin.add_theme_constant_override("margin_bottom", 2)
	currency_panel.add_child(currency_margin)
	var currency_row := HBoxContainer.new()
	currency_row.add_theme_constant_override("separation", 5)
	currency_margin.add_child(currency_row)
	var crystal := Label.new()
	crystal.text = "💎"
	crystal.custom_minimum_size = Vector2(19, 19)
	crystal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crystal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crystal.add_theme_font_size_override("font_size", 16)
	crystal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_row.add_child(crystal)
	_global_crystals = Label.new()
	_global_crystals.text = "0"
	_global_crystals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_crystals.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_global_crystals.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_global_crystals.add_theme_font_size_override("font_size", 14)
	_global_crystals.add_theme_color_override("font_color", Color(0.94, 0.95, 0.96))
	_global_crystals.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_global_crystals.add_theme_constant_override("shadow_offset_x", 1)
	_global_crystals.add_theme_constant_override("shadow_offset_y", 1)
	_global_crystals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_row.add_child(_global_crystals)

	return root

func _format_ui_number(value: int) -> String:
	var raw: String = str(absi(value))
	var result: String = ""
	var group_count: int = 0
	for index in range(raw.length() - 1, -1, -1):
		if group_count > 0 and group_count % 3 == 0:
			result = " " + result
		result = raw.substr(index, 1) + result
		group_count += 1
	return ("-" if value < 0 else "") + result

func _refresh_profile_strip() -> void:
	if _profile_strip == null or profile.is_empty():
		return
	var rank_value: Variant = profile.get("rank", {})
	var rank: Dictionary = {}
	if rank_value is Dictionary:
		rank = (rank_value as Dictionary).duplicate(true)
	var rank_index: int = clampi(int(rank.get("index", 0)), 0, 26)
	var rank_number: int = rank_index + 1
	var rank_name: String = String(rank.get("name", "Новобранец"))
	var icon_path: String = "%s/rank_%02d.png" % [RANK_ICON_DIR, rank_number]
	var icon_value: Variant = load(icon_path)
	if icon_value is Texture2D:
		_global_rank_icon.texture = icon_value as Texture2D
	_global_rank_icon.tooltip_text = rank_name
	_global_rank_name.text = "%s, %s" % [rank_name, String(profile.get("login", "Player"))]
	_global_rank_icon.tooltip_text = _global_rank_name.text

	var xp: int = maxi(0, int(profile.get("xp", 0)))
	var min_xp: int = maxi(0, int(rank.get("min_xp", 0)))
	var next_xp: int = maxi(min_xp, int(rank.get("next_xp", min_xp)))
	_global_xp.min_value = 0.0
	_global_xp.max_value = 1.0
	if rank_index >= 26 or next_xp <= min_xp:
		_global_xp.value = 1.0
		_global_xp_text.text = "%s  •  МАРШАЛ" % _format_ui_number(xp)
		_global_xp.tooltip_text = "Достигнуто максимальное звание: Маршал"
	else:
		var progress: float = clampf(float(rank.get("progress", 0.0)), 0.0, 1.0)
		var local_xp: int = maxi(0, xp - min_xp)
		var local_need: int = maxi(1, next_xp - min_xp)
		_global_xp.value = progress
		_global_xp_text.text = "%s / %s" % [_format_ui_number(local_xp), _format_ui_number(local_need)]
		_global_xp.tooltip_text = "%s: %s из %s XP" % [rank_name, _format_ui_number(local_xp), _format_ui_number(local_need)]
	_global_crystals.text = _format_ui_number(maxi(0, int(profile.get("crystals", 0))))

func _legacy_texture(name: String) -> Texture2D:
	var value: Variant = load(LEGACY_UI + name)
	if value is Texture2D:
		return value as Texture2D
	return null

func _legacy_background(parent: Control) -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = _legacy_texture("bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

func _legacy_style(texture_name: String, margin: float = 7.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _legacy_texture(texture_name)
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = 5.0
	style.texture_margin_bottom = 5.0
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style

func _legacy_window(min_size: Vector2 = Vector2.ZERO, inner: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxTexture.new()
	style.texture = _legacy_texture("window_inner_bg.jpg" if inner else "window_bg.jpg")
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _legacy_button(text_value: String, big: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(180, 48 if big else 31)
	if big:
		button.add_theme_stylebox_override("normal", _legacy_style("big_normal.png"))
		button.add_theme_stylebox_override("hover", _legacy_style("big_hover.png"))
		button.add_theme_stylebox_override("pressed", _legacy_style("big_pressed.png"))
	else:
		button.add_theme_stylebox_override("normal", _legacy_style("button_normal.png"))
		button.add_theme_stylebox_override("hover", _legacy_style("button_hover.png"))
		button.add_theme_stylebox_override("pressed", _legacy_style("button_pressed.png"))
	button.add_theme_color_override("font_color", Color(0.88, 0.88, 0.86))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 13)
	return button

func _legacy_line(placeholder: String, secret: bool = false) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(280, 31)
	edit.add_theme_stylebox_override("normal", _legacy_style("input.png", 5.0))
	edit.add_theme_stylebox_override("focus", _legacy_style("input.png", 5.0))
	edit.add_theme_color_override("font_color", Color(0.93, 0.93, 0.91))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.55, 0.53))
	return edit

func _legacy_title(texture_name: String) -> TextureRect:
	var title := TextureRect.new()
	title.texture = _legacy_texture(texture_name)
	title.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return title

func _legacy_label(text_value: String, size: int = 13, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.66, 0.67, 0.64) if muted else Color(0.91, 0.91, 0.89))
	return label

func _legacy_icon(texture_name: String, tooltip: String, callback: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = _legacy_texture(texture_name)
	button.ignore_texture_size = false
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

func _legacy_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _build_auth_screen(canvas: CanvasLayer) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	_legacy_background(root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := _legacy_window(Vector2(490, 485))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	var title_center := CenterContainer.new()
	title_center.add_child(_legacy_title("title_login.png"))
	box.add_child(title_center)
	var subtitle := _legacy_label("TANKI 2.0 • multiplayer", 11, true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	_auth_login = _legacy_line("Логин")
	box.add_child(_auth_login)
	_auth_password = _legacy_line("Пароль", true)
	box.add_child(_auth_password)
	_auth_repeat = _legacy_line("Повтор пароля (для регистрации)", true)
	box.add_child(_auth_repeat)
	var endpoint := HBoxContainer.new()
	endpoint.add_theme_constant_override("separation", 6)
	box.add_child(endpoint)
	_auth_host = _legacy_line("Host")
	_auth_host.custom_minimum_size.x = 205
	_auth_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint.add_child(_auth_host)
	_auth_port = _legacy_line("Port")
	_auth_port.custom_minimum_size.x = 90
	endpoint.add_child(_auth_port)

	var enter := _legacy_button("ВОЙТИ В ИГРУ", true)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(_login_pressed)
	box.add_child(enter)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	box.add_child(actions)
	var register_button := _legacy_button("РЕГИСТРАЦИЯ")
	register_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register_button.pressed.connect(_register_pressed)
	actions.add_child(register_button)
	var reconnect := _legacy_button("ПЕРЕПОДКЛЮЧИТЬСЯ")
	reconnect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reconnect.pressed.connect(_login_pressed)
	actions.add_child(reconnect)

	_auth_status = _legacy_label("Введите данные аккаунта и подключитесь к серверу.", 11, true)
	_auth_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auth_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auth_status.custom_minimum_size.y = 45
	box.add_child(_auth_status)
	return root

func _battle_lobby_panel_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.047, 0.039, 0.98) if not active else Color(0.23, 0.235, 0.075, 0.98)
	style.border_color = Color(0.29, 0.245, 0.18, 0.98) if not active else Color(0.58, 0.60, 0.16, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style

func _battle_lobby_button(text_value: String, active: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.93, 0.90, 0.80))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.42))
	button.add_theme_stylebox_override("normal", _battle_lobby_panel_style(active))
	button.add_theme_stylebox_override("hover", _battle_lobby_panel_style(true))
	button.add_theme_stylebox_override("pressed", _battle_lobby_panel_style(true))
	return button

func _battle_map_card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.020, 0.019, 0.015, 0.98)
	style.border_color = Color(0.54, 0.63, 0.08, 1.0) if selected else Color(0.17, 0.18, 0.12, 0.98)
	style.border_width_left = 3 if selected else 2
	style.border_width_top = 3 if selected else 2
	style.border_width_right = 3 if selected else 2
	style.border_width_bottom = 3 if selected else 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _refresh_battle_map_selection() -> void:
	_refresh_battle_join_state()

func _apply_lobby_search_filter() -> void:
	_refresh_battle_join_state()

func _on_lobby_search_changed(_new_text: String) -> void:
	_rebuild_battle_list()

func _toggle_battle_map() -> void:
	_refresh_battle_join_state()

func _battle_join_pressed() -> void:
	if _play_button == null or _play_button.disabled:
		return
	# Short mechanical press: compress the tab, then spring it back before joining.
	_play_button.pivot_offset = _play_button.size * 0.5
	var tween := create_tween()
	tween.tween_property(_play_button, "scale", Vector2(0.965, 0.92), 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_play_button, "modulate", Color(1.08, 1.08, 0.82, 1.0), 0.055)
	tween.tween_property(_play_button, "scale", Vector2.ONE, 0.095).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_play_button, "modulate", Color.WHITE, 0.095)
	tween.tween_callback(_play_pressed)

func _lobby_hitbox_button(rect: Rect2, tooltip: String = "") -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = tooltip
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.90, 0.32, 0.045)
	hover.border_color = Color(0.90, 0.76, 0.18, 0.18)
	hover.border_width_left = 1
	hover.border_width_top = 1
	hover.border_width_right = 1
	hover.border_width_bottom = 1
	hover.corner_radius_top_left = 3
	hover.corner_radius_top_right = 3
	hover.corner_radius_bottom_left = 3
	hover.corner_radius_bottom_right = 3
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.78, 0.10, 0.075)
	pressed.border_color = Color(0.96, 0.79, 0.18, 0.30)
	pressed.border_width_left = 1
	pressed.border_width_top = 1
	pressed.border_width_right = 1
	pressed.border_width_bottom = 1
	pressed.corner_radius_top_left = 3
	pressed.corner_radius_top_right = 3
	pressed.corner_radius_bottom_left = 3
	pressed.corner_radius_bottom_right = 3
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	return button

func _update_lobby_stage_layout() -> void:
	if _lobby_stage == null or not is_instance_valid(_lobby_stage):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size := Vector2(749.0, 839.0)
	# Leave a small symmetric frame around the old-client artwork. Filling the whole
	# viewport made it look left-heavy even though the math was technically centered.
	var usable_size := viewport_size * 0.94
	var scale_value: float = min(usable_size.x / base_size.x, usable_size.y / base_size.y)
	scale_value = maxf(scale_value, 0.45)
	var target_size := base_size * scale_value
	_lobby_stage.scale = Vector2.ONE * scale_value
	_lobby_stage.position = Vector2(round((viewport_size.x - target_size.x) * 0.5), round((viewport_size.y - target_size.y) * 0.5))
	# Battle entries are tiles. The first one belongs in the upper-right corner of the
	# list area; future maps can be laid out leftward/downward from the same grid.
	if _battle_browser_content != null and is_instance_valid(_battle_browser_content) and _battle_map_card != null and is_instance_valid(_battle_map_card):
		_battle_map_card.position.x = _battle_browser_content.size.x - _battle_map_card.size.x
		_battle_map_card.position.y = 0.0

func _build_lobby_screen(canvas: CanvasLayer) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	_legacy_background(root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 7)
	root.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	margin.add_child(shell)

	var top_panel := _legacy_window(Vector2(0, 52))
	shell.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top_panel.add_child(top)
	_lobby_rank_icon = TextureRect.new()
	_lobby_rank_icon.custom_minimum_size = Vector2(34, 34)
	_lobby_rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lobby_rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_lobby_rank_icon)
	_lobby_rank = _legacy_label("Игрок", 14)
	_lobby_rank.custom_minimum_size.x = 150
	top.add_child(_lobby_rank)
	_lobby_xp = ProgressBar.new()
	_lobby_xp.custom_minimum_size = Vector2(180, 18)
	_lobby_xp.show_percentage = false
	top.add_child(_lobby_xp)
	var crystal_icon := TextureRect.new()
	crystal_icon.texture = _legacy_texture("crystals.png")
	crystal_icon.custom_minimum_size = Vector2(30, 30)
	crystal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crystal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(crystal_icon)
	_lobby_crystals = _legacy_label("0", 14)
	top.add_child(_lobby_crystals)
	top.add_child(_legacy_spacer())
	top.add_child(_legacy_icon("icon_battles.png", "Битвы", _show_lobby))
	top.add_child(_legacy_icon("icon_garage.png", "Гараж", _show_garage))
	var logout := _legacy_button("ВЫЙТИ")
	logout.custom_minimum_size.x = 100
	logout.pressed.connect(_logout_pressed)
	top.add_child(logout)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)
	shell.add_child(main)
	var left := _legacy_window(Vector2(720, 0))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 5)
	left.add_child(left_box)
	var title_center := CenterContainer.new()
	title_center.add_child(_legacy_title("title_battles.png"))
	left_box.add_child(title_center)

	_lobby_search = _legacy_line("Поиск битвы")
	_lobby_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_search.text_changed.connect(_on_lobby_search_changed)
	left_box.add_child(_lobby_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(scroll)
	_battle_list = VBoxContainer.new()
	_battle_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_battle_list)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	left_box.add_child(bottom)
	var create := _legacy_button("СОЗДАТЬ БИТВУ", true)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_show_create_battle)
	bottom.add_child(create)
	var refresh := _legacy_button("ОБНОВИТЬ")
	refresh.custom_minimum_size.x = 150
	refresh.pressed.connect(func(): net.request_battles())
	bottom.add_child(refresh)

	var right := _legacy_window(Vector2(390, 0))
	main.add_child(right)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 7)
	right.add_child(info)
	var info_title := CenterContainer.new()
	info_title.add_child(_legacy_title("title_battle_info.png"))
	info.add_child(info_title)
	_battle_preview = TextureRect.new()
	_battle_preview.texture = BattleMapPreview
	_battle_preview.custom_minimum_size = Vector2(360, 215)
	_battle_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_battle_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	info.add_child(_battle_preview)
	_battle_info_label = _legacy_label("Выберите битву из списка", 13)
	_battle_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(_battle_info_label)
	_play_button = _legacy_button("ВОЙТИ В БОЙ", true)
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_battle_join_pressed)
	info.add_child(_play_button)
	_lobby_status = _legacy_label("", 11, true)
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_lobby_status)

	var chat := _legacy_window(Vector2(0, 142))
	shell.add_child(chat)
	var chat_box := VBoxContainer.new()
	chat_box.add_theme_constant_override("separation", 3)
	chat.add_child(chat_box)
	var chat_title := HBoxContainer.new()
	chat_title.add_child(_legacy_title("title_chat.png"))
	chat_title.add_child(_legacy_spacer())
	chat_title.add_child(_legacy_label("Общий чат", 10, true))
	chat_box.add_child(chat_title)
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size.y = 62
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_box.add_child(_chat_log)
	var send_row := HBoxContainer.new()
	chat_box.add_child(send_row)
	_chat_input = _legacy_line("Сообщение...")
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(_chat_submitted)
	send_row.add_child(_chat_input)
	var send := _legacy_button("ОТПРАВИТЬ")
	send.custom_minimum_size.x = 145
	send.pressed.connect(_chat_send_pressed)
	send_row.add_child(send)

	_lobby_loadout = Label.new()
	_lobby_loadout.visible = false
	root.add_child(_lobby_loadout)
	_battle_map_card = null
	_battle_map_title = null
	_battle_browser_content = null
	_rebuild_battle_list()
	return root

func _build_garage_screen(canvas: CanvasLayer) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	_legacy_background(root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 7)
	root.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	margin.add_child(shell)

	var top_panel := _legacy_window(Vector2(0, 52))
	shell.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top_panel.add_child(top)
	var back := _legacy_button("← БИТВЫ")
	back.custom_minimum_size.x = 135
	back.pressed.connect(_show_lobby)
	top.add_child(back)
	var title_center := CenterContainer.new()
	title_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_center.add_child(_legacy_title("title_my_tank.png"))
	top.add_child(title_center)
	var crystal := TextureRect.new()
	crystal.texture = _legacy_texture("crystals.png")
	crystal.custom_minimum_size = Vector2(30, 30)
	crystal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crystal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(crystal)
	_garage_crystals = _legacy_label("0", 14)
	top.add_child(_garage_crystals)

	_garage_title = _legacy_label("ГАРАЖ", 13, true)
	_garage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(_garage_title)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)
	shell.add_child(main)
	var preview_panel := _legacy_window(Vector2(520, 0), true)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(preview_panel)
	_preview_container = SubViewportContainer.new()
	_preview_container.stretch = true
	_preview_container.custom_minimum_size = Vector2(500, 520)
	preview_panel.add_child(_preview_container)

	var inventory_panel := _legacy_window(Vector2(0, 0))
	inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(inventory_panel)
	var inventory := VBoxContainer.new()
	inventory.add_theme_constant_override("separation", 6)
	inventory_panel.add_child(inventory)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	inventory.add_child(tabs)
	var garage_tabs: Array[Dictionary] = [
		{"id":"hull", "name":"КОРПУСА"},
		{"id":"turret", "name":"БАШНИ"},
		{"id":"paint", "name":"ПОКРЫТИЯ"}
	]
	for tab_data: Dictionary in garage_tabs:
		var tab_id := String(tab_data["id"])
		var tab := _legacy_button(String(tab_data["name"]))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_garage_tab_pressed.bind(tab_id))
		_garage_tab_buttons[tab_id] = tab
		tabs.add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory.add_child(scroll)
	_garage_grid = GridContainer.new()
	_garage_grid.columns = 2
	_garage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_garage_grid.add_theme_constant_override("h_separation", 6)
	_garage_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_garage_grid)
	return root

func _battle_meter_bg(color: Color = Color(0.075, 0.070, 0.050, 0.94)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.29, 0.27, 0.18, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _battle_meter_fill() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.47, 0.055, 0.98)
	style.border_color = Color(0.39, 0.62, 0.10, 0.98)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _battle_hud_text(text_value: String = "") -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.88))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _battle_feed_text(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.88))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.98))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _battle_feed_rank_icon(rank_index: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_value: Variant = load("%s/rank_%02d.png" % [RANK_SMALL_ICON_DIR, clampi(rank_index, 0, 26) + 1])
	if icon_value is Texture2D:
		icon.texture = icon_value as Texture2D
	return icon

func _clear_battle_action_feed() -> void:
	for row_data: Dictionary in _battle_action_rows:
		var node_value: Variant = row_data.get("node", null)
		if node_value is Node and is_instance_valid(node_value as Node):
			(node_value as Node).queue_free()
	_battle_action_rows.clear()

func _push_battle_action(data: Dictionary) -> void:
	if _battle_action_feed == null or not _in_battle:
		return
	var event_kind := String(data.get("event", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if event_kind == "player_joined":
		row.add_child(_battle_feed_rank_icon(int(data.get("rank_index", 0))))
		row.add_child(_battle_feed_text("%s присоединился к игре" % String(data.get("login", "Player"))))
	elif event_kind == "player_left":
		row.add_child(_battle_feed_rank_icon(int(data.get("rank_index", 0))))
		row.add_child(_battle_feed_text("%s покинул битву" % String(data.get("login", "Player"))))
	elif event_kind == "destroyed":
		var killer_id := int(data.get("killer", -1))
		var victim_id := int(data.get("victim", -1))
		if killer_id < 0 or killer_id == victim_id:
			return
		row.add_child(_battle_feed_rank_icon(int(data.get("killer_rank_index", 0))))
		row.add_child(_battle_feed_text(String(data.get("killer_login", "Player"))))
		row.add_child(_battle_feed_text(" уничтожил "))
		row.add_child(_battle_feed_rank_icon(int(data.get("victim_rank_index", 0))))
		row.add_child(_battle_feed_text(String(data.get("victim_login", "Player"))))
	else:
		return
	_battle_action_feed.add_child(row)
	_battle_action_rows.append({"node": row, "expires": Time.get_ticks_msec() + 8000})
	while _battle_action_rows.size() > 6:
		var oldest: Dictionary = _battle_action_rows.pop_front()
		var oldest_node: Variant = oldest.get("node", null)
		if oldest_node is Node and is_instance_valid(oldest_node as Node):
			(oldest_node as Node).queue_free()

func _show_gold_pickup_notice(login: String, local_picker: bool) -> void:
	if _battle_gold_notice == null:
		return
	_battle_gold_notice.text = "%s взял золотой ящик!" % login
	_battle_gold_notice.add_theme_color_override("font_color", Color(0.20, 0.95, 0.32) if local_picker else Color(0.98, 0.86, 0.10))
	_battle_gold_notice.visible = true
	_battle_gold_notice_hide_at_ms = Time.get_ticks_msec() + 4800

func _update_battle_messages() -> void:
	var now_ms := Time.get_ticks_msec()
	for index in range(_battle_action_rows.size() - 1, -1, -1):
		var row_data: Dictionary = _battle_action_rows[index]
		if now_ms < int(row_data.get("expires", 0)):
			continue
		var node_value: Variant = row_data.get("node", null)
		if node_value is Node and is_instance_valid(node_value as Node):
			(node_value as Node).queue_free()
		_battle_action_rows.remove_at(index)
	if _battle_gold_notice != null and _battle_gold_notice.visible and _battle_gold_notice_hide_at_ms > 0 and now_ms >= _battle_gold_notice_hide_at_ms:
		_battle_gold_notice.visible = false
		_battle_gold_notice_hide_at_ms = 0

func _build_battle_hud(canvas: CanvasLayer) -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	# Short-lived battle action feed. The 12x12 rank marks are the original chat-size
	# insignia from the old client, intentionally tiny so the feed stays unobtrusive.
	_battle_action_feed = VBoxContainer.new()
	_battle_action_feed.position = Vector2(14, 104)
	_battle_action_feed.size = Vector2(510, 150)
	_battle_action_feed.add_theme_constant_override("separation", 2)
	_battle_action_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_battle_action_feed)

	# Gold-box pickup is global and deliberately separate from the kill/join feed.
	_battle_gold_notice = Label.new()
	_battle_gold_notice.anchor_left = 0.18
	_battle_gold_notice.anchor_right = 0.82
	_battle_gold_notice.offset_top = 18.0
	_battle_gold_notice.offset_bottom = 48.0
	_battle_gold_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_gold_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_battle_gold_notice.add_theme_font_size_override("font_size", 19)
	_battle_gold_notice.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.98))
	_battle_gold_notice.add_theme_constant_override("shadow_offset_x", 2)
	_battle_gold_notice.add_theme_constant_override("shadow_offset_y", 2)
	_battle_gold_notice.visible = false
	_battle_gold_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_battle_gold_notice)

	# Compact classic match block in the upper-right: leader kills, personal kill
	# progress and battle fund. It mirrors the tiny 2011 counters without covering
	# the playfield with the old large translucent statistics panel.
	var hud_cluster := VBoxContainer.new()
	hud_cluster.anchor_left = 1.0
	hud_cluster.anchor_right = 1.0
	hud_cluster.offset_left = -222.0
	hud_cluster.offset_right = -14.0
	hud_cluster.offset_top = 14.0
	hud_cluster.offset_bottom = 84.0
	hud_cluster.add_theme_constant_override("separation", 4)
	hud_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_cluster)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	hud_cluster.add_child(top_row)

	var leader_panel := PanelContainer.new()
	leader_panel.custom_minimum_size = Vector2(78, 30)
	leader_panel.add_theme_stylebox_override("panel", _battle_meter_bg(Color(0.070, 0.073, 0.060, 0.96)))
	top_row.add_child(leader_panel)
	_battle_leader_kills = _battle_hud_text("⬆ 0")
	leader_panel.add_child(_battle_leader_kills)

	var kill_frame := Control.new()
	kill_frame.custom_minimum_size = Vector2(126, 30)
	kill_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(kill_frame)
	_battle_kill_progress = ProgressBar.new()
	_battle_kill_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_kill_progress.show_percentage = false
	_battle_kill_progress.min_value = 0.0
	_battle_kill_progress.max_value = 15.0
	_battle_kill_progress.value = 0.0
	_battle_kill_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_kill_progress.add_theme_stylebox_override("background", _battle_meter_bg())
	_battle_kill_progress.add_theme_stylebox_override("fill", _battle_meter_fill())
	kill_frame.add_child(_battle_kill_progress)
	_battle_kills = _battle_hud_text("☠ 0 / 15")
	_battle_kills.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kill_frame.add_child(_battle_kills)

	var fund_panel := PanelContainer.new()
	fund_panel.custom_minimum_size = Vector2(126, 28)
	fund_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	fund_panel.add_theme_stylebox_override("panel", _battle_meter_bg(Color(0.075, 0.068, 0.052, 0.96)))
	hud_cluster.add_child(fund_panel)
	_battle_fund = _battle_hud_text("💰 0")
	fund_panel.add_child(_battle_fund)

	# Legacy variables remain valid for older refresh paths, but are deliberately
	# invisible: rank/crystals are already in the global profile strip and score is
	# no longer a separate combat widget.
	_battle_rank = Label.new()
	_battle_rank.visible = false
	root.add_child(_battle_rank)
	_battle_crystals = Label.new()
	_battle_crystals.visible = false
	root.add_child(_battle_crystals)
	_battle_score = Label.new()
	_battle_score.visible = false
	root.add_child(_battle_score)

	var supplies: PanelContainer = PanelContainer.new()
	supplies.position = Vector2(12, 625)
	supplies.custom_minimum_size = Vector2(380, 72)
	supplies.add_theme_stylebox_override("panel", _panel_style(0.62))
	root.add_child(supplies)
	var supplies_box: VBoxContainer = VBoxContainer.new()
	supplies.add_child(supplies_box)
	var supplies_title: Label = Label.new()
	supplies_title.text = "ПРИПАСЫ"
	supplies_box.add_child(supplies_title)
	_battle_supplies = Label.new()
	_battle_supplies.text = "[+] +75% HP     [БРОНЯ] —     [УРОН] —     [НИТРО] —"
	supplies_box.add_child(_battle_supplies)

	_battle_hint = Label.new()
	_battle_hint.position = Vector2(430, 676)
	_battle_hint.text = "W/S движение • A/D поворот • Z/X башня • C автовозврат • DELETE самоуничтожение • SPACE огонь • ESC выход"
	root.add_child(_battle_hint)
	return root

func _build_round_overlay(canvas: CanvasLayer) -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.58)
	root.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 470)
	panel.add_theme_stylebox_override("panel", _panel_style(0.96))
	center.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_title("БОЙ ОКОНЧЕН", 30))
	_round_results = Label.new()
	_round_results.custom_minimum_size = Vector2(560, 320)
	_round_results.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_round_results.add_theme_font_size_override("font_size", 17)
	box.add_child(_round_results)
	_round_countdown = _title("Новый бой через 10.0 сек", 20)
	box.add_child(_round_countdown)
	return root

func _command_endpoint() -> Array:
	var host: String = "127.0.0.1"
	var port: int = 9100
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			host = arg.trim_prefix("--server=")
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	return [host, port]

func _show_auth() -> void:
	_auth_screen.visible = true
	_lobby_screen.visible = false
	_garage_screen.visible = false
	_battle_hud.visible = false
	_round_overlay.visible = false
	if _profile_strip != null:
		_profile_strip.visible = false
	_destroy_preview()
	_clear_world()
	_clear_tanks()
	_in_battle = false
	local_spawned = false

func _show_lobby() -> void:
	if profile.is_empty():
		_show_auth()
		return
	_auth_screen.visible = false
	_lobby_screen.visible = true
	_garage_screen.visible = false
	_battle_hud.visible = false
	_round_overlay.visible = false
	if _profile_strip != null:
		_profile_strip.visible = false
	_destroy_preview()
	_refresh_profile_ui()
	_rebuild_battle_list()
	if net != null and net.is_authenticated:
		net.request_battles()

func _show_garage() -> void:
	_auth_screen.visible = false
	_lobby_screen.visible = false
	_garage_screen.visible = true
	_battle_hud.visible = false
	_round_overlay.visible = false
	if _profile_strip != null:
		_profile_strip.visible = false
	_refresh_garage()
	_rebuild_garage_preview()

func _login_pressed() -> void:
	_begin_auth("login")

func _register_pressed() -> void:
	if _auth_password.text != _auth_repeat.text:
		_auth_status.text = "Пароли не совпадают"
		return
	_begin_auth("register")

func _begin_auth(kind: String) -> void:
	var login: String = _auth_login.text.strip_edges()
	var password: String = _auth_password.text
	if login.length() < 3 or password.length() < 6:
		_auth_status.text = "Введите логин и пароль (минимум 6 символов)"
		return
	_pending_auth_kind = kind
	_pending_auth_login = login
	_pending_auth_password = password
	if net.is_welcomed:
		_send_pending_auth()
		return
	var port_value: int = int(_auth_port.text)
	if port_value <= 0:
		port_value = 9100
	_auth_status.text = "Подключение к серверу…"
	net.connect_to_server(_auth_host.text, port_value, "lobby")

func _send_pending_auth() -> void:
	if _pending_auth_kind == "register":
		_auth_status.text = "Создание аккаунта…"
		net.register_account(_pending_auth_login, _pending_auth_password)
	elif _pending_auth_kind == "login":
		_auth_status.text = "Вход…"
		net.login_account(_pending_auth_login, _pending_auth_password)

func _on_welcome(_player_id: int) -> void:
	_send_pending_auth()

func _on_auth_result(ok: bool, reason: String, new_profile: Dictionary, catalog: Dictionary, chat_history: Array) -> void:
	_pending_auth_kind = ""
	_pending_auth_password = ""
	if not ok:
		_auth_status.text = reason
		return
	profile = new_profile.duplicate(true)
	server_catalog = catalog.duplicate(true)
	_apply_server_catalog(server_catalog)
	_chat_log.text = ""
	for raw: Variant in chat_history:
		if raw is Dictionary:
			_append_chat(raw as Dictionary)
	_auth_status.text = "Загрузка покрытий с сервера…"
	var paints_ok: bool = await _download_server_paints()
	_catalog_ready = paints_ok
	if not paints_ok:
		_auth_status.text = "Не удалось загрузить покрытия (TCP %d)" % net.asset_port
		return
	_auth_password.text = ""
	_auth_repeat.text = ""
	_show_lobby()

func _apply_server_catalog(catalog: Dictionary) -> void:
	_hull_catalog = _dict_array(catalog.get("hulls", []))
	_turret_catalog = _dict_array(catalog.get("turrets", []))
	_paint_catalog = _dict_array(catalog.get("paints", []))
	_paint_previews.clear()
	var economy_value: Variant = catalog.get("economy", {})
	_economy = {}
	if economy_value is Dictionary:
		_economy = (economy_value as Dictionary).duplicate(true)
	PaintCatalogScript.configure_server(_paint_catalog)
	var combat_value: Variant = catalog.get("combat", {})
	if combat_value is Dictionary:
		CombatCatalogScript.configure(combat_value as Dictionary)

func _dict_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for raw: Variant in value:
			if raw is Dictionary:
				out.append((raw as Dictionary).duplicate(true))
	return out

func _download_server_paints() -> bool:
	if net == null or net.asset_port <= 0 or _paint_catalog.is_empty():
		return false
	var all_ok: bool = true
	for paint: Dictionary in _paint_catalog:
		var paint_id: String = String(paint.get("id", ""))
		if paint_id == "":
			all_ok = false
			continue
		if not PaintCatalogScript.has_texture(paint_id):
			var paint_url: String = "http://%s:%d/paints/%s" % [net.host, net.asset_port, paint_id]
			var texture: Texture2D = await _download_image_texture(
				paint_url, String(paint.get("sha256", "")), String(paint.get("format", "png"))
			)
			if texture == null:
				all_ok = false
				continue
			PaintCatalogScript.install_texture(paint_id, texture)
		if int(paint.get("preview_bytes", 0)) > 0:
			var preview_url: String = "http://%s:%d/paint-previews/%s" % [net.host, net.asset_port, paint_id]
			var preview: Texture2D = await _download_image_texture(
				preview_url, String(paint.get("preview_sha256", "")), String(paint.get("preview_format", "png"))
			)
			if preview != null:
				_paint_previews[paint_id] = preview
	return all_ok

func _download_image_texture(url: String, expected_hash: String, format_name: String) -> Texture2D:
	var request := HTTPRequest.new()
	add_child(request)
	var request_error: Error = request.request(url)
	if request_error != OK:
		request.queue_free()
		return null
	var completed: Array = await request.request_completed
	request.queue_free()
	if completed.size() < 4:
		return null
	var result_code: int = int(completed[0])
	var response_code: int = int(completed[1])
	var body_value: Variant = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not (body_value is PackedByteArray):
		return null
	var body: PackedByteArray = body_value as PackedByteArray
	var normalized_hash: String = expected_hash.to_lower()
	if normalized_hash != "" and _sha256_hex(body) != normalized_hash:
		push_error("Asset hash mismatch: " + url)
		return null
	var image := Image.new()
	var normalized_format := format_name.to_lower()
	var image_error: Error = ERR_FILE_UNRECOGNIZED
	if normalized_format == "png":
		image_error = image.load_png_from_buffer(body)
	elif normalized_format == "jpg" or normalized_format == "jpeg":
		image_error = image.load_jpg_from_buffer(body)
	elif normalized_format == "webp":
		image_error = image.load_webp_from_buffer(body)
	if image_error != OK:
		return null
	return ImageTexture.create_from_image(image)

func _sha256_hex(body: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	var start_error: Error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	context.update(body)
	return context.finish().hex_encode().to_lower()

func _on_profile_received(new_profile: Dictionary) -> void:
	profile = new_profile.duplicate(true)
	_refresh_profile_ui()
	if _garage_screen.visible:
		_refresh_garage()
		_rebuild_garage_preview()

func _refresh_profile_ui() -> void:
	if profile.is_empty():
		return
	_refresh_profile_strip()
	var login: String = String(profile.get("login", "Player"))
	var rank_value: Variant = profile.get("rank", {})
	var rank: Dictionary = {}
	if rank_value is Dictionary:
		rank = (rank_value as Dictionary).duplicate(true)
	var rank_name: String = String(rank.get("name", "Новобранец"))
	var xp: int = int(profile.get("xp", 0))
	var min_xp: int = int(rank.get("min_xp", 0))
	var next_xp: int = int(rank.get("next_xp", min_xp))
	_lobby_rank.text = "%s\n%s" % [rank_name, login]
	if _lobby_rank_icon != null:
		var lobby_rank_icon_value: Variant = load("%s/rank_%02d.png" % [RANK_ICON_DIR, clampi(int(rank.get("index", 0)), 0, 26) + 1])
		if lobby_rank_icon_value is Texture2D:
			_lobby_rank_icon.texture = lobby_rank_icon_value as Texture2D
	_lobby_xp.min_value = 0.0
	_lobby_xp.max_value = 1.0
	_lobby_xp.value = float(rank.get("progress", 1.0))
	_lobby_xp.tooltip_text = "Опыт: %d%s" % [xp, " / %d" % next_xp if next_xp > min_xp else ""]
	_lobby_crystals.text = _format_ui_number(maxi(0, int(profile.get("crystals", 0))))
	_garage_crystals.text = str(int(profile.get("crystals", 0)))
	var equipped: Dictionary = _equipped_build()
	_lobby_loadout.text = "Установлено:\n%s + %s\nПокрытие: %s" % [
		_catalog_name(_hull_catalog, String(equipped.get("hull", "")), int(equipped.get("hull_mod", 0))),
		_catalog_name(_turret_catalog, String(equipped.get("turret", "")), int(equipped.get("turret_mod", 0))),
		_paint_name(String(equipped.get("paint", "")))
	]
	_refresh_battle_map_selection()
	_refresh_battle_hud()

func _equipped_build() -> Dictionary:
	var value: Variant = profile.get("equipped", {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func _catalog_name(items: Array[Dictionary], item_id: String, mod_level: int) -> String:
	for item: Dictionary in items:
		if String(item.get("id", "")) == item_id and int(item.get("mod", 0)) == mod_level:
			return String(item.get("name", item_id.to_upper()))
	return "%s M%d" % [item_id.to_upper(), mod_level]

func _paint_name(paint_id: String) -> String:
	for paint: Dictionary in _paint_catalog:
		if String(paint.get("id", "")) == paint_id:
			return String(paint.get("name", paint_id))
	return paint_id

func _chat_submitted(text: String) -> void:
	_send_chat(text)

func _chat_send_pressed() -> void:
	_send_chat(_chat_input.text)

func _send_chat(text: String) -> void:
	var clean: String = text.strip_edges()
	if clean == "":
		return
	net.send_chat(clean)
	_chat_input.text = ""

func _on_chat_received(data: Dictionary) -> void:
	_append_chat(data)

func _append_chat(data: Dictionary) -> void:
	var login: String = String(data.get("login", "?"))
	var rank: String = String(data.get("rank", ""))
	var text: String = String(data.get("text", ""))
	if _chat_log.text != "":
		_chat_log.text += "\n"
	_chat_log.text += "%s%s: %s" % ["[%s] " % rank if rank != "" else "", login, text]

func _play_pressed() -> void:
	if not _catalog_ready or profile.is_empty():
		return
	if _selected_battle_id <= 0:
		_lobby_status.text = "Сначала выберите битву"
		return
	_play_button.disabled = true
	_lobby_status.text = "Подключение к выбранной битве…"
	net.join_battle(_selected_battle_id)

func _garage_pressed() -> void:
	_show_garage()

func _logout_pressed() -> void:
	net.close()
	profile.clear()
	server_catalog.clear()
	_battles.clear()
	_selected_battle_id = -1
	_catalog_ready = false
	_chat_log.text = ""
	_auth_status.text = "Вы вышли из аккаунта"
	_show_auth()

func _garage_tab_pressed(category: String) -> void:
	_garage_category = category
	_refresh_garage()

func _refresh_garage() -> void:
	if _garage_grid == null:
		return
	for child: Node in _garage_grid.get_children():
		child.queue_free()
	_garage_crystals.text = str(int(profile.get("crystals", 0)))
	var items: Array[Dictionary] = _hull_catalog
	var title_name: String = "КОРПУСА"
	if _garage_category == "turret":
		items = _turret_catalog
		title_name = "БАШНИ"
	elif _garage_category == "paint":
		items = _paint_catalog
		title_name = "ПОКРЫТИЯ"
	_garage_title.text = "ГАРАЖ • " + title_name
	for tab_id: Variant in _garage_tab_buttons.keys():
		var tab_value: Variant = _garage_tab_buttons.get(tab_id)
		if tab_value is Button:
			var tab := tab_value as Button
			var selected := String(tab_id) == _garage_category
			tab.add_theme_stylebox_override("normal", _legacy_style("button_pressed.png" if selected else "button_normal.png"))
			tab.add_theme_stylebox_override("hover", _legacy_style("button_hover.png"))
			tab.add_theme_stylebox_override("pressed", _legacy_style("button_pressed.png"))
	for item: Dictionary in items:
		_garage_grid.add_child(_garage_card(_garage_category, item))

func _garage_card(category: String, item: Dictionary) -> Control:
	var item_id: String = String(item.get("id", ""))
	var mod_level: int = int(item.get("mod", 0))
	var owned: bool = _owns_profile_item(category, item_id, mod_level)
	var equipped: bool = _is_equipped_item(category, item_id, mod_level)
	var panel := _legacy_window(Vector2(275, 205 if category == "paint" else 116), true)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	if category == "paint":
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(260, 100)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.texture = _paint_previews.get(item_id, null) as Texture2D
		box.add_child(preview)
	var name_label := _legacy_label(("✓ " if equipped else "") + String(item.get("name", item_id)), 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	if not owned:
		var price := _legacy_label("💎 %d" % int(item.get("price", _economy.get("item_price", 10))), 12, true)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(price)
	var action := _legacy_button("УСТАНОВЛЕНО" if equipped else ("УСТАНОВИТЬ" if owned else "КУПИТЬ"))
	action.disabled = equipped
	action.pressed.connect(_garage_item_pressed.bind(category, item_id, mod_level, owned))
	box.add_child(action)
	return panel

func _owns_profile_item(category: String, item_id: String, mod_level: int) -> bool:
	if category == "hull":
		var value: Variant = profile.get("owned_hulls", [])
		return value is Array and (value as Array).has("%s:%d" % [item_id, mod_level])
	if category == "turret":
		var value: Variant = profile.get("owned_turrets", [])
		return value is Array and (value as Array).has("%s:%d" % [item_id, mod_level])
	var paints: Variant = profile.get("owned_paints", [])
	return paints is Array and (paints as Array).has(item_id)

func _is_equipped_item(category: String, item_id: String, mod_level: int) -> bool:
	var equipped: Dictionary = _equipped_build()
	if category == "hull":
		return String(equipped.get("hull", "")) == item_id and int(equipped.get("hull_mod", -1)) == mod_level
	if category == "turret":
		return String(equipped.get("turret", "")) == item_id and int(equipped.get("turret_mod", -1)) == mod_level
	return String(equipped.get("paint", "")) == item_id

func _garage_item_pressed(category: String, item_id: String, mod_level: int, owned: bool) -> void:
	if owned:
		net.equip_item(category, item_id, mod_level)
		_garage_title.text = "ГАРАЖ • установка…"
	else:
		net.purchase_item(category, item_id, mod_level)
		_garage_title.text = "ГАРАЖ • покупка…"

func _on_purchase_result(_ok: bool, reason: String, new_profile: Dictionary) -> void:
	if not new_profile.is_empty():
		profile = new_profile.duplicate(true)
	_refresh_profile_ui()
	_refresh_garage()
	_garage_title.text = "ГАРАЖ • " + reason

func _on_equip_result(_ok: bool, reason: String, new_profile: Dictionary) -> void:
	if not new_profile.is_empty():
		profile = new_profile.duplicate(true)
	_refresh_profile_ui()
	_refresh_garage()
	_garage_title.text = "ГАРАЖ • " + reason
	_rebuild_garage_preview()

func _rebuild_garage_preview() -> void:
	_destroy_preview()
	if profile.is_empty() or not _catalog_ready:
		return
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "GarageViewport"
	_preview_viewport.own_world_3d = true
	_preview_viewport.transparent_bg = false
	_preview_viewport.size = Vector2i(960, 300)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_container.add_child(_preview_viewport)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.045, 0.038)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.43, 0.36)
	env.ambient_light_energy = 0.78
	env_node.environment = env
	_preview_viewport.add_child(env_node)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_color = Color(1.0, 0.78, 0.48)
	key.light_energy = 1.7
	_preview_viewport.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(-3.0, 2.5, 2.0)
	fill.omni_range = 9.0
	fill.light_color = Color(0.34, 0.52, 0.72)
	fill.light_energy = 2.2
	_preview_viewport.add_child(fill)
	_preview_pivot = Node3D.new()
	_preview_viewport.add_child(_preview_pivot)
	var tank: Node = TankScript.new()
	_preview_pivot.add_child(tank)
	tank.configure(-9000, _equipped_build(), false, net)
	if tank is RigidBody3D:
		(tank as RigidBody3D).freeze = true
	_preview_tank = tank
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(7.2, 4.2, 7.8)
	_preview_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.current = true

func _destroy_preview() -> void:
	_preview_tank = null
	_preview_pivot = null
	if _preview_viewport != null and is_instance_valid(_preview_viewport):
		_preview_viewport.queue_free()
	_preview_viewport = null

func _on_battles_received(items: Array) -> void:
	_battles.clear()
	for raw: Variant in items:
		if raw is Dictionary:
			_battles.append((raw as Dictionary).duplicate(true))
	var still_exists := false
	for battle: Dictionary in _battles:
		if int(battle.get("id", -1)) == _selected_battle_id:
			still_exists = true
			break
	if not still_exists:
		_selected_battle_id = int(_battles[0].get("id", -1)) if not _battles.is_empty() else -1
	_rebuild_battle_list()

func _on_battle_created(ok: bool, battle: Dictionary, reason: String) -> void:
	if not ok:
		_lobby_status.text = reason
		return
	_selected_battle_id = int(battle.get("id", -1))
	_lobby_status.text = "Битва создана. Выберите её и входите."
	if net != null:
		net.request_battles()

func _battle_by_id(battle_id: int) -> Dictionary:
	for battle: Dictionary in _battles:
		if int(battle.get("id", -1)) == battle_id:
			return battle
	return {}

func _rebuild_battle_list() -> void:
	if _battle_list == null or not is_instance_valid(_battle_list):
		return
	for child: Node in _battle_list.get_children():
		child.queue_free()
	var query := _lobby_search.text.strip_edges().to_lower() if _lobby_search != null else ""
	var visible_count := 0
	for battle: Dictionary in _battles:
		var name := String(battle.get("name", "Битва"))
		if query != "" and not name.to_lower().contains(query):
			continue
		visible_count += 1
		var battle_id := int(battle.get("id", -1))
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 33)
		row.text = "  %-28s  %-12s  %d/%d   ☠ %d" % [
			name,
			"Арена",
			int(battle.get("players", 0)),
			int(battle.get("max_players", 10)),
			int(battle.get("kill_limit", 15))
		]
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.07, 0.08, 0.075, 0.96)
		normal.border_color = Color(0.25, 0.27, 0.24)
		normal.set_border_width_all(1)
		var hover := normal.duplicate()
		hover.bg_color = Color(0.12, 0.16, 0.10, 0.98)
		var pressed := normal.duplicate()
		pressed.bg_color = Color(0.18, 0.24, 0.12, 1.0)
		row.add_theme_stylebox_override("normal", pressed if battle_id == _selected_battle_id else normal)
		row.add_theme_stylebox_override("hover", hover)
		row.add_theme_stylebox_override("pressed", pressed)
		row.pressed.connect(_select_battle.bind(battle_id))
		_battle_list.add_child(row)
	if visible_count == 0:
		_battle_list.add_child(_legacy_label("Нет битв. Создайте первую.", 12, true))
	_refresh_battle_info()

func _select_battle(battle_id: int) -> void:
	_selected_battle_id = battle_id
	_rebuild_battle_list()

func _refresh_battle_info() -> void:
	if _battle_info_label == null:
		return
	var battle := _battle_by_id(_selected_battle_id)
	if battle.is_empty():
		_battle_info_label.text = "Выберите битву из списка"
		_refresh_battle_join_state()
		return
	_battle_info_label.text = "%s\nКарта: Арена\nРежим: Deathmatch\nИгроки: %d / %d\nНеобходимо убийств для победы: %d\nСоздатель: %s" % [
		String(battle.get("name", "Битва")),
		int(battle.get("players", 0)),
		int(battle.get("max_players", 10)),
		int(battle.get("kill_limit", 15)),
		String(battle.get("owner", ""))
	]
	_refresh_battle_join_state()

func _refresh_battle_join_state() -> void:
	if _play_button == null:
		return
	var battle := _battle_by_id(_selected_battle_id)
	var full := not battle.is_empty() and int(battle.get("players", 0)) >= int(battle.get("max_players", 10))
	_play_button.disabled = not _catalog_ready or battle.is_empty() or full

func _show_create_battle() -> void:
	if _battle_create_overlay != null and is_instance_valid(_battle_create_overlay):
		_battle_create_overlay.queue_free()
	_battle_create_overlay = ColorRect.new()
	_battle_create_overlay.color = Color(0, 0, 0, 0.58)
	_battle_create_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_screen.add_child(_battle_create_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_create_overlay.add_child(center)
	var panel := _legacy_window(Vector2(530, 455))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	var title_center := CenterContainer.new()
	title_center.add_child(_legacy_title("title_create_battle.png"))
	box.add_child(title_center)
	var name := _legacy_line("Название битвы")
	name.text = "%s battle" % String(profile.get("login", "Player"))
	box.add_child(_legacy_label("Название:"))
	box.add_child(name)
	box.add_child(_legacy_label("Карта:"))
	var map_line := _legacy_line("Арена")
	map_line.text = "Арена"
	map_line.editable = false
	box.add_child(map_line)
	box.add_child(_legacy_label("Другие карты отключены: для создания доступна только Арена.", 11, true))
	var values := GridContainer.new()
	values.columns = 2
	box.add_child(values)
	values.add_child(_legacy_label("Игроков:"))
	var max_players := SpinBox.new()
	max_players.min_value = 2
	max_players.max_value = 32
	max_players.value = 10
	values.add_child(max_players)
	values.add_child(_legacy_label("Убийств для победы:"))
	var kill_limit := SpinBox.new()
	kill_limit.min_value = 1
	kill_limit.max_value = 999
	kill_limit.value = 25
	values.add_child(kill_limit)
	var preview := TextureRect.new()
	preview.texture = BattleMapPreview
	preview.custom_minimum_size = Vector2(480, 180)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	box.add_child(preview)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 7)
	box.add_child(buttons)
	var create := _legacy_button("СОЗДАТЬ", true)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(func():
		var battle_name := name.text.strip_edges()
		if battle_name == "":
			battle_name = "%s battle" % String(profile.get("login", "Player"))
		net.create_battle(battle_name, int(kill_limit.value), int(max_players.value))
		_lobby_status.text = "Создание битвы…"
		_battle_create_overlay.queue_free()
		_battle_create_overlay = null
	)
	buttons.add_child(create)
	var cancel := _legacy_button("ОТМЕНА")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		_battle_create_overlay.queue_free()
		_battle_create_overlay = null
	)
	buttons.add_child(cancel)

func _on_battle_joined(ok: bool, build: Dictionary, spawn_index: int, combat: Dictionary, match: Dictionary, reason: String) -> void:
	_play_button.disabled = false
	if not ok:
		_lobby_status.text = "Не удалось войти в бой: " + reason
		return
	_destroy_preview()
	_clear_tanks()
	_load_arena()
	_in_battle = true
	local_build = build.duplicate(true)
	local_spawned = true
	_auth_screen.visible = false
	_lobby_screen.visible = false
	_garage_screen.visible = false
	_battle_hud.visible = true
	_round_overlay.visible = false
	if _profile_strip != null:
		_profile_strip.visible = true
	var tank: Node = _ensure_tank(net.player_id, local_build, true)
	tank.teleport_spawn(_spawn_transform(spawn_index))
	tank.apply_combat_state(combat)
	_supply_probe_elapsed = 0.0
	_match_state = match.duplicate(true)
	_clear_battle_action_feed()
	if _battle_gold_notice != null:
		_battle_gold_notice.visible = false
	_battle_gold_notice_hide_at_ms = 0
	_set_local_match_controls(bool(_match_state.get("active", true)))
	_refresh_battle_hud()
	if not _pending_snapshot.is_empty():
		var delayed: Array = _pending_snapshot.duplicate(true)
		_pending_snapshot.clear()
		_on_snapshot(delayed)

func _load_arena() -> void:
	_clear_world()
	_world_root = Node3D.new()
	_world_root.name = "MapRoot_Arena"
	add_child(_world_root)
	var arena: Node = ArenaEditableScene.instantiate()
	_world_root.add_child(arena)

func _clear_world() -> void:
	_supplies.clear()
	if _world_root != null and is_instance_valid(_world_root):
		_world_root.queue_free()
	_world_root = null

func _spawn_transform(spawn_index: int) -> Transform3D:
	var safe_slot: int = clampi(spawn_index, 0, SPAWN_SLOT_COUNT - 1)

	# Prefer real editable markers first. Spawn_0..Spawn_8 can now be placed
	# anywhere in arena_editable.tscn and are used exactly as authored.
	if _world_root != null:
		var direct_marker: Node = _world_root.find_child("Spawn_%d" % safe_slot, true, false)
		if direct_marker is Marker3D:
			return (direct_marker as Marker3D).global_transform

	# Backward-compatible fallback for maps that still only contain Spawn_0..2:
	# slots 3..8 become lateral lanes around the three original markers.
	var base_index: int = safe_slot % SPAWNS.size()
	var lane_index: int = int(float(safe_slot) / float(SPAWNS.size()))
	var lateral_offset: float = SPAWN_LATERAL_OFFSETS[clampi(lane_index, 0, SPAWN_LATERAL_OFFSETS.size() - 1)]

	if _world_root != null:
		var base_marker: Node = _world_root.find_child("Spawn_%d" % base_index, true, false)
		if base_marker is Marker3D:
			var transform: Transform3D = (base_marker as Marker3D).global_transform
			var lateral: Vector3 = transform.basis.x
			lateral.y = 0.0
			lateral = lateral.normalized() if lateral.length_squared() > 0.0001 else Vector3.RIGHT
			transform.origin += lateral * lateral_offset
			return transform

	var fallback: Dictionary = SPAWNS[base_index]
	var fallback_position: Vector3 = fallback.get("p", Vector3.ZERO)
	var fallback_yaw: float = float(fallback.get("yaw", 0.0))
	var fallback_basis: Basis = Basis(Vector3.UP, fallback_yaw)
	fallback_position += fallback_basis.x.normalized() * lateral_offset
	return Transform3D(fallback_basis, fallback_position)

func _on_snapshot(players: Array) -> void:
	if not _in_battle:
		_pending_snapshot = players.duplicate(true)
		return
	var alive_ids: Dictionary = {}
	for raw: Variant in players:
		if not (raw is Dictionary):
			continue
		var state: Dictionary = raw as Dictionary
		var id: int = int(state.get("id", -1))
		var build_value: Variant = state.get("build", {})
		if id < 0 or not (build_value is Dictionary):
			continue
		var build: Dictionary = build_value as Dictionary
		alive_ids[id] = true
		var is_local: bool = id == net.player_id
		if is_local:
			if tanks.has(id):
				tanks[id].apply_combat_state(state)
				_refresh_supply_hud()
			continue
		var tank: Node = _ensure_tank(id, build, false)
		tank.apply_network_state(state)
	for id_value: Variant in tanks.keys().duplicate():
		var id: int = int(id_value)
		if not alive_ids.has(id) and id != net.player_id:
			if is_instance_valid(tanks[id]):
				tanks[id].queue_free()
			tanks.erase(id)

func _ensure_tank(id: int, build: Dictionary, is_local: bool) -> Node:
	if tanks.has(id):
		return tanks[id]
	var tank: Node = TankScript.new()
	add_child(tank)
	tank.configure(id, build, is_local, net)
	tanks[id] = tank
	return tank

func _on_shot(data: Dictionary) -> void:
	var shooter: int = int(data.get("shooter", -1))
	if shooter == net.player_id:
		return
	if tanks.has(shooter):
		tanks[shooter].play_remote_shot(data)

func _on_combat_event(data: Dictionary) -> void:
	var event_kind := String(data.get("event", ""))
	if event_kind == "player_joined" or event_kind == "player_left":
		_push_battle_action(data)
		return
	var victim: int = int(data.get("victim", -1))
	if victim >= 0 and tanks.has(victim):
		tanks[victim].play_combat_event(data)
	if event_kind == "destroyed":
		_push_battle_action(data)
	if victim == net.player_id and event_kind == "destroyed":
		_battle_hint.text = "УНИЧТОЖЕН • респаун через %.1f сек • ESC выход" % float(data.get("respawn_delay", 3.0))

func _on_respawn_requested(spawn_index: int, combat: Dictionary) -> void:
	if not _in_battle or not tanks.has(net.player_id):
		return
	tanks[net.player_id].revive_at(_spawn_transform(spawn_index), combat)
	_refresh_supply_hud()
	_set_local_match_controls(bool(_match_state.get("active", true)))
	_battle_hint.text = "W/S движение • A/D поворот • Z/X башня • C автовозврат • DELETE самоуничтожение • SPACE огонь • ESC выход"

func _on_supply_snapshot(supplies: Array) -> void:
	if not _in_battle or _world_root == null:
		return
	var alive_ids: Dictionary = {}
	for raw: Variant in supplies:
		if not (raw is Dictionary):
			continue
		var data: Dictionary = raw as Dictionary
		var supply_id: int = int(data.get("id", -1))
		if supply_id < 0:
			continue
		alive_ids[supply_id] = true
		var existing_value: Variant = _supplies.get(supply_id, null)
		if existing_value is Node and is_instance_valid(existing_value as Node):
			var existing: Node = existing_value as Node
			existing.call("update_authoritative", data)
		else:
			var created_value: Variant = SupplyDropScript.new()
			if not (created_value is Node3D):
				continue
			var node: Node3D = created_value as Node3D
			_world_root.add_child(node)
			node.call("configure", data)
			_supplies[supply_id] = node
	for id_value: Variant in _supplies.keys().duplicate():
		var supply_id: int = int(id_value)
		if alive_ids.has(supply_id):
			continue
		var node_value: Variant = _supplies.get(supply_id, null)
		if node_value is Node and is_instance_valid(node_value as Node):
			(node_value as Node).queue_free()
		_supplies.erase(supply_id)

func _on_supply_event(data: Dictionary) -> void:
	var event_kind: String = String(data.get("event", ""))
	if event_kind == "reset":
		for node_value: Variant in _supplies.values():
			if node_value is Node and is_instance_valid(node_value as Node):
				(node_value as Node).queue_free()
		_supplies.clear()
		return
	if event_kind == "spawn":
		return
	if event_kind != "pickup":
		return
	var picker_is_local: bool = int(data.get("player", -1)) == net.player_id
	if String(data.get("kind", "")) == "gold":
		_show_gold_pickup_notice(String(data.get("login", "Player")), picker_is_local)
	var supply_id: int = int(data.get("id", -1))
	if _supplies.has(supply_id):
		var node_value: Variant = _supplies.get(supply_id, null)
		if node_value is Node and is_instance_valid(node_value as Node):
			var node: Node = node_value as Node
			if node.has_method("play_pickup_effect"):
				node.call("play_pickup_effect", picker_is_local)
			else:
				node.queue_free()
		_supplies.erase(supply_id)
	if picker_is_local:
		_play_bonus_sound()
		var combat_value: Variant = data.get("combat", {})
		if combat_value is Dictionary and tanks.has(net.player_id):
			var tank_value: Variant = tanks.get(net.player_id, null)
			if tank_value is Node and is_instance_valid(tank_value as Node):
				(tank_value as Node).call("apply_combat_state", combat_value as Dictionary)
		_refresh_supply_hud()

func _probe_supply_pickups() -> void:
	if not _in_battle or not tanks.has(net.player_id):
		return
	var local_tank_value: Variant = tanks.get(net.player_id, null)
	if not (local_tank_value is Node3D):
		return
	var local_tank: Node3D = local_tank_value as Node3D
	if not is_instance_valid(local_tank):
		return
	if not bool(local_tank.get("combat_alive")):
		return
	for id_value: Variant in _supplies.keys():
		var supply_id: int = int(id_value)
		var node_value: Variant = _supplies.get(supply_id, null)
		if not (node_value is Node):
			continue
		var node: Node = node_value as Node
		if not is_instance_valid(node) or not bool(node.call("is_pickable")):
			continue
		var pickup_pos_value: Variant = node.call("pickup_position")
		if not (pickup_pos_value is Vector3):
			continue
		var pickup_pos: Vector3 = pickup_pos_value as Vector3
		var horizontal: Vector2 = Vector2(local_tank.global_position.x - pickup_pos.x, local_tank.global_position.z - pickup_pos.z)
		if horizontal.length() <= 3.9 and absf(local_tank.global_position.y - pickup_pos.y) <= 3.0:
			net.request_supply_pickup(supply_id)

func _play_bonus_sound() -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = BonusSound
	player.volume_db = 0.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _refresh_supply_hud() -> void:
	if _battle_supplies == null:
		return
	if not _in_battle or not tanks.has(net.player_id):
		_battle_supplies.text = "[+] +75% HP     [БРОНЯ] —     [УРОН] —     [НИТРО] —"
		return
	var tank_value: Variant = tanks.get(net.player_id, null)
	if not (tank_value is Node):
		return
	var tank: Node = tank_value as Node
	if not is_instance_valid(tank):
		return
	var armor: float = float(tank.get("combat_armor_time"))
	var damage: float = float(tank.get("combat_damage_time"))
	var nitro: float = float(tank.get("combat_nitro_time"))
	var armor_text: String = "%.0fс" % armor if armor > 0.05 else "—"
	var damage_text: String = "%.0fс" % damage if damage > 0.05 else "—"
	var nitro_text: String = "%.0fс" % nitro if nitro > 0.05 else "—"
	_battle_supplies.text = "[+] +75% HP     [БРОНЯ] " + armor_text + "     [УРОН] " + damage_text + "     [НИТРО] " + nitro_text
func _on_match_state(data: Dictionary) -> void:
	_match_state = data.duplicate(true)
	if _in_battle:
		_set_local_match_controls(bool(_match_state.get("active", true)))
		_refresh_battle_hud()

func _refresh_battle_hud() -> void:
	if profile.is_empty():
		return
	var rank_value: Variant = profile.get("rank", {})
	var rank: Dictionary = {}
	if rank_value is Dictionary:
		rank = (rank_value as Dictionary).duplicate(true)
	_battle_rank.text = "%s • %s" % [String(rank.get("name", "Новобранец")), String(profile.get("login", "Player"))]
	_battle_crystals.text = str(int(profile.get("crystals", 0)))

	var local_kills: int = 0
	var local_score: int = 0
	var leader_kills: int = 0
	var players_value: Variant = _match_state.get("players", [])
	if players_value is Array:
		var player_rows: Array = players_value as Array
		for raw: Variant in player_rows:
			if not (raw is Dictionary):
				continue
			var row: Dictionary = raw as Dictionary
			var row_kills: int = maxi(0, int(row.get("kills", 0)))
			leader_kills = maxi(leader_kills, row_kills)
			if int(row.get("id", -1)) == net.player_id:
				local_kills = row_kills
				local_score = int(row.get("score", 0))

	var kill_limit: int = maxi(1, int(_match_state.get("kill_limit", _economy.get("kill_limit", 15))))
	_battle_leader_kills.text = "⬆ %d" % leader_kills
	_battle_kills.text = "☠ %d / %d" % [local_kills, kill_limit]
	_battle_kill_progress.max_value = float(kill_limit)
	_battle_kill_progress.value = float(clampi(local_kills, 0, kill_limit))
	_battle_score.text = "Очки: %d" % local_score
	_battle_fund.text = "💰 %d" % int(_match_state.get("fund", 0))

func _on_round_end(data: Dictionary) -> void:
	if not _in_battle:
		return
	_set_local_match_controls(false)
	_round_overlay.visible = true
	var restart_in: float = float(data.get("restart_in", 10.0))
	_round_restart_deadline_ms = Time.get_ticks_msec() + int(restart_in * 1000.0)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Победитель: %s" % String(data.get("winner", "?")))
	lines.append("Фонд боя: %d кристаллов" % int(data.get("fund", 0)))
	lines.append("")
	lines.append("Место   Игрок                 Убийства    Очки      Награда")
	var results_value: Variant = data.get("results", [])
	if results_value is Array:
		var result_rows: Array = results_value as Array
		for raw: Variant in result_rows:
			if not (raw is Dictionary):
				continue
			var item: Dictionary = raw as Dictionary
			lines.append("%2d.     %-18s  %3d        %5d     💎 %d   +%d XP" % [
				int(item.get("place", 0)), String(item.get("login", "?")), int(item.get("kills", 0)),
				int(item.get("score", 0)), int(item.get("crystals", 0)), int(item.get("xp", 0))
			])
	_round_results.text = "\n".join(lines)

func _on_round_start(data: Dictionary) -> void:
	if not _in_battle:
		return
	_round_overlay.visible = false
	_round_restart_deadline_ms = 0
	_match_state["active"] = true
	_match_state["round_id"] = int(data.get("round_id", _match_state.get("round_id", 0)))
	_match_state["fund"] = 0
	_set_local_match_controls(true)
	_battle_hint.text = "НОВЫЙ БОЙ • до %d убийств" % int(data.get("kill_limit", 15))

func _set_local_match_controls(enabled: bool) -> void:
	if tanks.has(net.player_id) and is_instance_valid(tanks[net.player_id]):
		tanks[net.player_id].set_match_controls_enabled(enabled)

func _on_battle_left() -> void:
	_return_to_lobby_local()

func _return_to_lobby_local() -> void:
	_in_battle = false
	local_spawned = false
	local_build.clear()
	_match_state.clear()
	_pending_snapshot.clear()
	_round_overlay.visible = false
	_battle_hud.visible = false
	_clear_battle_action_feed()
	if _battle_gold_notice != null:
		_battle_gold_notice.visible = false
	_battle_gold_notice_hide_at_ms = 0
	_clear_tanks()
	_clear_world()
	_show_lobby()
	_lobby_status.text = "Вы вернулись из боя"

func _clear_tanks() -> void:
	for id_value: Variant in tanks.keys():
		var tank_value: Variant = tanks.get(id_value, null)
		if tank_value is Node and is_instance_valid(tank_value):
			(tank_value as Node).queue_free()
	tanks.clear()

func _on_status(text: String) -> void:
	if _auth_screen != null and _auth_screen.visible:
		_auth_status.text = text
	elif _lobby_screen != null and _lobby_screen.visible:
		_lobby_status.text = text

func _on_connection_lost() -> void:
	profile.clear()
	server_catalog.clear()
	_battles.clear()
	_selected_battle_id = -1
	_catalog_ready = false
	_pending_auth_kind = ""
	_auth_status.text = "Соединение потеряно. Войдите снова."
	_show_auth()
