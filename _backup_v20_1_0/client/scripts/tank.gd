extends RigidBody3D
class_name TankActor

const SheetEffectScript = preload("res://scripts/sheet_effect.gd")
const PaintCatalogScript = preload("res://scripts/paint_catalog.gd")
const TankPaintShader = preload("res://shaders/tank_paint.gdshader")
const CombatCatalogScript = preload("res://scripts/combat_catalog.gd")

var player_id: int = -1
var hull_id: String = "wasp"
var turret_id: String = "smoky"
var paint_id: String = "green"
var hull_mod: int = 2
var turret_mod: int = 2
var local_control: bool = false
var ai_control: bool = false
var _ai_target_id: int = -1
var _ai_retarget_time: float = 0.0
var _ai_avoid_time: float = 0.0
var _ai_avoid_sign: int = 1
var _ai_wander_time: float = 0.0
var _ai_wander_turn: int = 0
var _ai_supply_target_id: int = -1
var _ai_supply_retarget_time: float = 0.0
var _ai_progress_anchor: Vector3 = Vector3.ZERO
var _ai_progress_elapsed: float = 0.0
var _ai_recovery_time: float = 0.0
var _ai_recovery_turn: int = 1
var _ai_repath_cooldown: float = 0.0
# v19.1.2: a bot that remains on its side/roof is no longer allowed to fight forever.
# It stops firing immediately and asks the authoritative server to self-destruct after
# a short continuous overturned interval.
var _ai_overturned_time: float = 0.0
var _ai_self_destruct_requested: bool = false
var _config: Dictionary = {}
var network: TankiNetworkClient

var turret_yaw: float = 0.0
var current_speed: float = 0.0
var firing: bool = false
var _fire_down: bool = false
var _center_turret_down: bool = false
var _fire_cooldown: float = 0.0
var _reload_visual_ratio: float = 1.0
var _death_sound_played: bool = false
var _turret_centering: bool = false
var _turret_turn_velocity: float = 0.0
var _self_destruct_down: bool = false
var _state_elapsed: float = 0.0
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_rotation: Quaternion = Quaternion.IDENTITY
var _target_linear_velocity: Vector3 = Vector3.ZERO
var _target_angular_velocity: Vector3 = Vector3.ZERO
var _target_turret: float = 0.0
var _target_left_track: float = 0.0
var _target_right_track: float = 0.0
var _has_target: bool = false
var _last_moving: bool = false

var _visual_root: Node3D
var _running_gear_root: Node3D
var _body_rock_root: Node3D
var _turret_root: Node3D
var _camera_yaw_root: Node3D
var _camera_anchor_base: Vector3 = Vector3.ZERO
var _muzzle: Marker3D
var _camera: Camera3D
var _death_camera: Camera3D = null
# v18.18.26 cinematic respawn: the server tells us the reserved next spawn
# at destruction time, so the detached camera can fly there before respawn.
var _death_camera_path_ready: bool = false
var _death_camera_path_started_ms: int = 0
var _death_camera_respawn_delay: float = 3.0
var _death_camera_hold_seconds: float = 1.5
var _death_camera_start_transform: Transform3D = Transform3D.IDENTITY
var _respawn_camera_target_root: Node3D = null
var _respawn_camera_target: Camera3D = null
# v18.18.27 anti-flash handoff: keep the detached camera current for a few
# physics frames after respawn. This gives SpringArm3D and physics interpolation
# time to settle before the live camera becomes visible.
var _respawn_camera_handoff_frames: int = 0
var _spring: SpringArm3D
var _camera_rig: Node3D
var _flame_root: Node3D
var _flame_light: OmniLight3D
var _flame_fill_light: OmniLight3D
var _firebird_emit_elapsed: float = 0.0
var _idle_audio: AudioStreamPlayer3D
var _move_audio: AudioStreamPlayer3D
var _turret_audio: AudioStreamPlayer3D
var _oneshot_audio: AudioStreamPlayer3D
var _shot_audio: AudioStreamPlayer3D
var _death_audio: AudioStreamPlayer3D

var _left_track_speed: float = 0.0
var _right_track_speed: float = 0.0
var _track_drive_intensity: float = 0.0
var _left_track_visual_speed: float = 0.0
var _right_track_visual_speed: float = 0.0
var _left_track_mats: Array[ShaderMaterial] = []
var _right_track_mats: Array[ShaderMaterial] = []
var _left_track_uv_offset: float = 0.0
var _right_track_uv_offset: float = 0.0
var _left_track_deform: Array[float] = []
var _right_track_deform: Array[float] = []
var _left_wheels: Array[Node3D] = []
var _right_wheels: Array[Node3D] = []
var _wheel_local_pos: Dictionary = {}
var _wheel_local_rot: Dictionary = {}
var _wheel_visual_radius: Dictionary = {}
var _wheel_track_source_offset: Dictionary = {}
var _wheel_spin: Dictionary = {}
var _turn_velocity: float = 0.0
var _last_speed_for_rock: float = 0.0
var _rock_pitch: float = 0.0
var _rock_velocity: float = 0.0
var _rock_roll: float = 0.0
var _rock_roll_velocity: float = 0.0
var _last_yaw_rate_for_rock: float = 0.0
var _step_grace: float = 0.0
var _ground_contacts: int = 0
var _stuck_drive_time: float = 0.0
var _stuck_recovery_cooldown: float = 0.0
var _drive_input: int = 0
var _turn_input: int = 0
var _suspension_points: Array[Dictionary] = []
var _terrain_pitch_target: float = 0.0
var _terrain_pitch_bias: float = 0.0
var _virtual_ramp_strength: float = 0.0
var _rough_contact_factor: float = 0.0
var _support_normal: Vector3 = Vector3.UP

var combat_alive: bool = true
var match_controls_enabled: bool = true
var combat_hp: float = 1.0
var combat_max_hp: float = 1.0
var combat_fuel: float = 0.0
var combat_fuel_max: float = 0.0
var combat_burn: float = 0.0
var combat_burn_time: float = 0.0
var combat_nitro_time: float = 0.0
var combat_nitro_multiplier: float = 2.0
var combat_armor_time: float = 0.0
var combat_damage_time: float = 0.0
var _burn_emit_elapsed: float = 0.0
var _burn_light_elapsed: float = 0.0
var _last_combat_hp: float = 1.0
var _hud_layer: CanvasLayer
var _hud_hp_label: Label
var _hud_hp_fill_clip: Control
var _hud_weapon_label: Label
var _hud_weapon_fill_clip: Control
var _overhead_status_root: Node3D
var _overhead_hp_fill: MeshInstance3D
var _overhead_weapon_fill: MeshInstance3D
var _overhead_bar_width: float = 1.72
var _wreck_material_backups: Array[Dictionary] = []
var _turret_debris_spawned: bool = false
var _wreck_body_spawned: bool = false
var _wreck_body_debris: RigidBody3D = null
var _death_linear_velocity: Vector3 = Vector3.ZERO
var _death_angular_velocity: Vector3 = Vector3.ZERO
var _death_motion_captured: bool = false # v18.18.23 death momentum
var _wreck_fire_remaining: float = 0.0 # v18.18.26
var _wreck_fire_emit_elapsed: float = 0.0
var _wreck_fire_light_elapsed: float = 0.0

const MAX_SPEED := 8.0 # Original demo conMaxSpeed=800 cm/s.
const DRIVE_ACCEL := 1.82 # normalized track speed / sec
const COAST_DECEL := 0.52
const SERVICE_BRAKE := 2.35
const TURN_INPUT_SCALE := 0.44
const WORLD_GRAVITY := 9.8
const HudHealthOn: Texture2D = preload("res://assets/ui/combat/health_on.png")
const HudHealthOff: Texture2D = preload("res://assets/ui/combat/health_off.png")
const HudReloadOn: Texture2D = preload("res://assets/ui/combat/reload_on.png")
const HudReloadOff: Texture2D = preload("res://assets/ui/combat/reload_off.png")
const CAMERA_MIN_X := -38.0
const CAMERA_MAX_X := -6.0
const TURRET_CENTER_SPEED := 2.0
const TURRET_MANUAL_MAX_SPEED := 2.0
const TURRET_MANUAL_ACCEL := 7.0
const TRACK_DEFORM_SAMPLES := 10
const TERRAIN_PHYSICS_MASK := 1
const TERRAIN_VISUAL_MASK := 3
const DISCRETE_WORLD_RAY_LIMIT := 4096.0
const OVERTURNED_UP_DOT := 0.18
const BOT_OVERTURN_SELF_DESTRUCT_SECONDS := 1.80

func configure(id_: int, build_: Dictionary, is_local: bool, net: TankiNetworkClient, is_ai: bool = false) -> void:
	player_id = id_
	ai_control = is_ai
	hull_id = _normalize_hull(String(build_.get("hull", "wasp")))
	turret_id = _normalize_turret(String(build_.get("turret", "smoky")))
	hull_mod = clampi(int(build_.get("hull_mod", CombatCatalogScript.default_hull_mod(hull_id))), 0, 3)
	turret_mod = clampi(int(build_.get("turret_mod", CombatCatalogScript.default_weapon_mod(turret_id))), 0, 3)
	paint_id = String(build_.get("paint", "green"))
	local_control = is_local
	network = net
	_config = _compose_config()
	name = "Tank_%d" % player_id
	_build_body()
	_build_visuals()
	_rebuild_suspension_points()
	_build_audio()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not (local_control or ai_control)
	sleeping = false
	_initialize_combat_state()
	add_to_group("tanki_tank")
	if local_control:
		_build_camera()
		_build_combat_hud()

func _normalize_hull(value: String) -> String:
	var normalized := value.to_lower()
	return normalized if normalized == "wasp" or normalized == "viking" or normalized == "mamont" else "wasp"

func _normalize_turret(value: String) -> String:
	var normalized := value.to_lower()
	return normalized if normalized == "smoky" or normalized == "firebird" or normalized == "thunder" else "smoky"

func _compose_config() -> Dictionary:
	var cfg: Dictionary = _hull_cfg().duplicate(true)
	var turret: Dictionary = _turret_cfg()
	for key in turret.keys():
		cfg[key] = turret[key]
	# Release 20 separates logical M0..M3 from visual assets. The current project
	# only has one mesh set per module (e.g. Wasp M2), so all four logical levels
	# may point at that same model today. The server catalog can later bind a unique
	# asset_model/asset_texture_dir to every M-level without changing this script.
	var hull_visual: Dictionary = CombatCatalogScript.visual_spec("hull", hull_id, hull_mod)
	var turret_visual: Dictionary = CombatCatalogScript.visual_spec("turret", turret_id, turret_mod)
	var hull_model := String(hull_visual.get("asset_model", ""))
	var hull_textures := String(hull_visual.get("asset_texture_dir", ""))
	var turret_model := String(turret_visual.get("asset_model", ""))
	var turret_textures := String(turret_visual.get("asset_texture_dir", ""))
	if hull_model != "" and ResourceLoader.exists(hull_model):
		cfg["hull"] = hull_model
	if hull_textures != "" and ResourceLoader.exists(hull_textures + "/diffuse.png"):
		cfg["texture_dir"] = hull_textures
	if turret_model != "" and ResourceLoader.exists(turret_model):
		cfg["turret"] = turret_model
	if turret_textures != "" and ResourceLoader.exists(turret_textures + "/diffuse.png"):
		cfg["turret_texture_dir"] = turret_textures
	# v20.0.1: per-mod visual helpers. This lets legacy M0 geometry keep its
	# original turret seat / barrel length instead of inheriting M2 coordinates.
	var asset_mount_value: Variant = hull_visual.get("asset_mount", null)
	if asset_mount_value is Array and (asset_mount_value as Array).size() >= 3:
		var asset_mount: Array = asset_mount_value as Array
		cfg["turret_mount"] = Vector3(float(asset_mount[0]), float(asset_mount[1]), float(asset_mount[2]))
	var asset_muzzle_value: Variant = turret_visual.get("asset_muzzle", null)
	if asset_muzzle_value is Array and (asset_muzzle_value as Array).size() >= 3:
		var asset_muzzle: Array = asset_muzzle_value as Array
		cfg["muzzle"] = Vector3(float(asset_muzzle[0]), float(asset_muzzle[1]), float(asset_muzzle[2]))
	cfg["hull_label"] = String(hull_visual.get("name", "%s M%d" % [hull_id.to_upper(), hull_mod]))
	cfg["turret_label"] = String(turret_visual.get("name", "%s M%d" % [turret_id.to_upper(), turret_mod]))
	cfg["paint"] = PaintCatalogScript.resolve(paint_id)
	cfg["hull_mod"] = hull_mod
	cfg["turret_mod"] = turret_mod
	cfg["hull_combat"] = CombatCatalogScript.hull_spec(hull_id, hull_mod)
	cfg["weapon_combat"] = CombatCatalogScript.weapon_spec(turret_id, turret_mod)
	cfg["label"] = "%s + %s" % [String(cfg.get("hull_label", hull_id)), String(cfg.get("turret_label", turret_id))]
	return cfg

func _cfg() -> Dictionary:
	return _config

func _hull_cfg() -> Dictionary:
	match hull_id:
		"viking":
			return {
				"hull_label":"Viking M1",
				"hull":"res://assets/hulls/viking_m1.dae",
				"texture_dir":"res://assets/tank_textures/viking_m1",
				"tint":Color("#dccca8"),
				"size":Vector3(4.1,1.55,6.1),
				"turret_mount":Vector3(0.0070,1.6924,0.4725),
				"suspension_rest":0.42,
				"suspension_travel":0.17,
				"wheel_radius":0.33,
				"track_scroll_rate":0.88,
				"turn_in_place":1.72,
				"turn_running":0.86,
				"ground_probe_height":2.2,
				"ground_probe_depth":4.8,
				"step_height":0.94,
				"step_probe":0.70,
				"rock_strength":0.00105,
				"wheel_bias_y":0.10,
				"running_gear_drop":0.055,
				"track_ground_clearance":0.014,
				"track_collision_bottom":-0.020,
				"visual_wheel_extension":0.64,
				"physics_mass":3.6,
				"suspension_k":53.0,
				"suspension_damping":14.5,
				"suspension_force_cap":1.90,
				"suspension_lookahead":0.60,
				"drive_gain":2.65,
				"drive_force_limit":27.0,
				"launch_traction_boost":1.46,
				"climb_up_gain":9.5,
				"climb_forward_gain":16.5,
				"climb_pitch_gain":2.0,
				"pivot_track_scale":0.59,
				"pivot_torque_gain":0.55,
				"moving_turn_torque_gain":0.32,
				"moving_max_rate":1.38,
				"pivot_max_rate":1.10,
				"linear_damp":0.075,
				"angular_damp":0.82,
				"lateral_gain":2.20
			}
		"mamont":
			return {
				"hull_label":"Mamont M3",
				"hull":"res://assets/hulls/mamont_m3.dae",
				"texture_dir":"res://assets/tank_textures/mamont_m3",
				"tint":Color("#f0ede0"),
				"size":Vector3(4.7,1.75,7.2),
				"turret_mount":Vector3(0.0,2.2787,-1.0971),
				"suspension_rest":0.54,
				"suspension_travel":0.20,
				"wheel_radius":0.39,
				"track_scroll_rate":0.82,
				"turn_in_place":1.58,
				"turn_running":0.78,
				"ground_probe_height":2.5,
				"ground_probe_depth":5.3,
				"step_height":1.02,
				"step_probe":0.76,
				"rock_strength":0.00085,
				"wheel_bias_y":0.02,
				"running_gear_drop":0.065,
				"track_ground_clearance":0.016,
				"track_collision_bottom":0.005,
				"visual_wheel_extension":0.60,
				"physics_mass":5.6,
				"suspension_k":68.0,
				"suspension_damping":17.0,
				"suspension_force_cap":1.95,
				"suspension_lookahead":0.66,
				"drive_gain":2.15,
				"drive_force_limit":23.0,
				"launch_traction_boost":1.34,
				"climb_up_gain":8.0,
				"climb_forward_gain":14.0,
				"climb_pitch_gain":1.8,
				"pivot_track_scale":0.55,
				"pivot_torque_gain":0.51,
				"moving_turn_torque_gain":0.295,
				"moving_max_rate":1.22,
				"pivot_max_rate":0.98,
				"linear_damp":0.10,
				"angular_damp":0.98,
				"lateral_gain":2.38
			}
		_:
			return {
				"hull_label":"Wasp M2",
				"hull":"res://assets/hulls/wasp_m2.dae",
				"texture_dir":"res://assets/tank_textures/wasp_m2",
				"tint":Color("#d7d9cc"),
				"size":Vector3(3.0,1.35,4.8),
				"turret_mount":Vector3(0.0,2.2317,1.3210),
				"suspension_rest":0.34,
				"suspension_travel":0.18,
				"wheel_radius":0.28,
				"track_scroll_rate":0.95,
				"turn_in_place":1.85,
				"turn_running":0.95,
				"ground_probe_height":2.0,
				"ground_probe_depth":4.2,
				"step_height":0.82,
				"step_probe":0.62,
				"rock_strength":0.00125,
				"wheel_bias_y":0.00,
				"running_gear_drop":0.050,
				"track_ground_clearance":0.012,
				"track_collision_bottom":0.005,
				"visual_wheel_extension":0.66,
				"physics_mass":2.15,
				"suspension_k":42.0,
				"suspension_damping":12.0,
				"suspension_force_cap":1.85,
				"suspension_lookahead":0.54,
				"drive_gain":3.05,
				"drive_force_limit":31.0,
				"launch_traction_boost":1.58,
				"climb_up_gain":10.5,
				"climb_forward_gain":18.5,
				"climb_pitch_gain":2.2,
				"pivot_track_scale":0.62,
				"pivot_torque_gain":0.58,
				"moving_turn_torque_gain":0.34,
				"moving_max_rate":1.52,
				"pivot_max_rate":1.18,
				"linear_damp":0.060,
				"angular_damp":0.68,
				"lateral_gain":2.02
			}

func _turret_cfg() -> Dictionary:
	match turret_id:
		"firebird":
			return {
				"turret_label":"Firebird M1",
				"turret":"res://assets/turrets/firebird_m1.obj",
				"turret_texture_dir":"res://assets/tank_textures/firebird_m1",
				"weapon":"firebird",
				"muzzle":Vector3(0.0015,0.5230,-4.1959)
			}
		"thunder":
			return {
				"turret_label":"Thunder M3",
				"turret":"res://assets/turrets/thunder_m3.obj",
				"turret_texture_dir":"res://assets/tank_textures/thunder_m3",
				"weapon":"thunder",
				"muzzle":Vector3(0.0015,0.6696,-4.1718)
			}
		_:
			return {
				"turret_label":"Smoky M2",
				"turret":"res://assets/turrets/smoky_m2.obj",
				"turret_texture_dir":"res://assets/tank_textures/smoky_m2",
				"weapon":"smoky",
				"muzzle":Vector3(0.0015,0.4657,-3.7172)
			}

func _initialize_combat_state() -> void:
	var hull_stats_value: Variant = _cfg().get("hull_combat", {})
	var hull_stats: Dictionary = hull_stats_value if hull_stats_value is Dictionary else {}
	var weapon_stats_value: Variant = _cfg().get("weapon_combat", {})
	var weapon_stats: Dictionary = weapon_stats_value if weapon_stats_value is Dictionary else {}
	combat_max_hp = maxf(float(hull_stats.get("max_hp", 1.0)), 1.0)
	combat_hp = combat_max_hp
	_last_combat_hp = combat_hp
	combat_fuel_max = maxf(float(weapon_stats.get("fuel_max", 0.0)), 0.0)
	combat_fuel = combat_fuel_max
	_reload_visual_ratio = 1.0
	_death_sound_played = false
	combat_alive = true
	combat_burn = 0.0
	combat_burn_time = 0.0
	combat_nitro_time = 0.0
	combat_nitro_multiplier = 2.0
	combat_armor_time = 0.0
	combat_damage_time = 0.0

func _weapon_stats() -> Dictionary:
	var value: Variant = _cfg().get("weapon_combat", {})
	return value if value is Dictionary else {}

func _effective_weapon_range(stats: Dictionary) -> float:
	# range <= 0 is the v19.1 sentinel for map-unlimited Smoky/Thunder. Physics
	# queries still need a finite endpoint, so 4096 m is only an engine safety ray.
	var configured: float = float(stats.get("range", 0.0))
	return DISCRETE_WORLD_RAY_LIMIT if configured <= 0.0 else configured

func _status_bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Classic status bars behave like world-space HUD markers: the hull/turret must
	# never cover them when the camera angle gets low.
	mat.no_depth_test = true
	mat.render_priority = 20
	return mat

func _status_bar_mesh(width: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	node.mesh = quad
	node.material_override = _status_bar_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _build_overhead_status() -> void:
	if _overhead_status_root != null or player_id < 0:
		return
	_overhead_status_root = Node3D.new()
	_overhead_status_root.name = "TankStatusBars"
	var mount_y: float = _turret_root.position.y if _turret_root != null else float(_cfg()["size"].y)
	# Compact classic-style pair. The geometry borrows the layered dark/bronze frame
	# language from the old rank strip, but stays small enough not to clutter aim view.
	_overhead_status_root.position = Vector3(0.0, mount_y + 0.08, 0.0)
	add_child(_overhead_status_root)

	var hp_y: float = 0.060
	var weapon_y: float = -0.060
	var outer_width: float = _overhead_bar_width + 0.16
	var frame_width: float = _overhead_bar_width + 0.105
	var inner_width: float = _overhead_bar_width + 0.020

	# HP frame: near-black shadow -> bronze rim -> dark-green channel -> green fill.
	var hp_shadow := _status_bar_mesh(outer_width, 0.166, Color(0.020, 0.018, 0.015, 0.98))
	hp_shadow.position = Vector3(0.012, hp_y - 0.010, 0.030)
	_overhead_status_root.add_child(hp_shadow)
	var hp_frame := _status_bar_mesh(frame_width, 0.132, Color(0.33, 0.255, 0.105, 1.0))
	hp_frame.position = Vector3(0.0, hp_y, 0.020)
	_overhead_status_root.add_child(hp_frame)
	var hp_bg := _status_bar_mesh(inner_width, 0.092, Color(0.040, 0.145, 0.036, 1.0))
	hp_bg.position = Vector3(0.0, hp_y, 0.010)
	_overhead_status_root.add_child(hp_bg)
	_overhead_hp_fill = _status_bar_mesh(_overhead_bar_width, 0.066, Color(0.10, 0.90, 0.11, 1.0))
	_overhead_hp_fill.position = Vector3(0.0, hp_y, -0.005)
	_overhead_status_root.add_child(_overhead_hp_fill)

	# Reload/fuel frame uses the same silhouette, with a dark mustard channel and
	# bright yellow fill. Reload continues to grow from right to left.
	var weapon_shadow := _status_bar_mesh(outer_width, 0.158, Color(0.020, 0.018, 0.015, 0.98))
	weapon_shadow.position = Vector3(0.012, weapon_y - 0.010, 0.030)
	_overhead_status_root.add_child(weapon_shadow)
	var weapon_frame := _status_bar_mesh(frame_width, 0.126, Color(0.33, 0.255, 0.105, 1.0))
	weapon_frame.position = Vector3(0.0, weapon_y, 0.020)
	_overhead_status_root.add_child(weapon_frame)
	var weapon_bg := _status_bar_mesh(inner_width, 0.086, Color(0.30, 0.235, 0.030, 1.0))
	weapon_bg.position = Vector3(0.0, weapon_y, 0.010)
	_overhead_status_root.add_child(weapon_bg)
	_overhead_weapon_fill = _status_bar_mesh(_overhead_bar_width, 0.060, Color(1.0, 0.82, 0.045, 1.0))
	_overhead_weapon_fill.position = Vector3(0.0, weapon_y, -0.005)
	_overhead_status_root.add_child(_overhead_weapon_fill)
	_update_overhead_status()

func _set_status_fill(node: MeshInstance3D, ratio: float, y: float, fill_from_right: bool = false) -> void:
	if node == null:
		return
	var safe_ratio := clampf(ratio, 0.0, 1.0)
	node.scale.x = maxf(safe_ratio, 0.001)
	var anchor_sign: float = 1.0 if fill_from_right else -1.0
	node.position = Vector3(anchor_sign * _overhead_bar_width * (1.0 - safe_ratio) * 0.5, y, -0.005)
	node.visible = safe_ratio > 0.002

func _update_overhead_status() -> void:
	if _overhead_status_root == null:
		return
	_overhead_status_root.visible = combat_alive
	if not combat_alive:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Copy the camera basis instead of look_at(). This keeps local +X aligned with
		# screen-right at every viewing angle, so right-to-left reload is never mirrored.
		_overhead_status_root.global_basis = camera.global_basis.orthonormalized()
	var hp_ratio: float = combat_hp / maxf(combat_max_hp, 1.0)
	_set_status_fill(_overhead_hp_fill, hp_ratio, 0.060)
	var weapon := String(_cfg().get("weapon", "smoky"))
	var weapon_ratio: float = 1.0
	if weapon == "firebird":
		weapon_ratio = combat_fuel / maxf(combat_fuel_max, 1.0)
	else:
		weapon_ratio = _reload_visual_ratio
	_set_status_fill(_overhead_weapon_fill, weapon_ratio, -0.060, true)

func _combat_hud_label() -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 12.0
	label.offset_right = -12.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.92, 0.91, 0.84, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_lamp_meter(parent: Control, off_texture: Texture2D, on_texture: Texture2D) -> Control:
	var off_rect := TextureRect.new()
	off_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	off_rect.texture = off_texture
	off_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	off_rect.stretch_mode = TextureRect.STRETCH_SCALE
	off_rect.modulate = Color(0.95, 0.95, 0.95, 0.96)
	off_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(off_rect)

	var clip := Control.new()
	clip.position = Vector2.ZERO
	clip.size = parent.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(clip)

	var on_rect := TextureRect.new()
	on_rect.position = Vector2.ZERO
	on_rect.size = parent.size
	on_rect.texture = on_texture
	on_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	on_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# The supplied lamps are intentionally bright; dim them slightly in-game so they
	# match the old industrial HUD instead of blooming over dark maps.
	on_rect.modulate = Color(0.92, 0.92, 0.92, 0.96)
	on_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(on_rect)
	return clip

func _set_lamp_meter_ratio(clip: Control, ratio: float, full_width: float) -> void:
	if clip == null or not is_instance_valid(clip):
		return
	clip.size.x = full_width * clampf(ratio, 0.0, 1.0)

func _build_combat_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 25
	add_child(_hud_layer)

	var root := Control.new()
	root.anchor_left = 1.0
	root.anchor_top = 1.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -300.0
	root.offset_top = -136.0
	root.offset_right = -18.0
	root.offset_bottom = -68.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	var hp_frame := Control.new()
	hp_frame.position = Vector2(0.0, 0.0)
	hp_frame.size = Vector2(282.0, 30.0)
	hp_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_frame)
	_hud_hp_fill_clip = _build_lamp_meter(hp_frame, HudHealthOff, HudHealthOn)
	_hud_hp_label = _combat_hud_label()
	hp_frame.add_child(_hud_hp_label)

	var weapon_frame := Control.new()
	weapon_frame.position = Vector2(0.0, 36.0)
	weapon_frame.size = Vector2(282.0, 30.0)
	weapon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(weapon_frame)
	_hud_weapon_fill_clip = _build_lamp_meter(weapon_frame, HudReloadOff, HudReloadOn)
	_hud_weapon_label = _combat_hud_label()
	weapon_frame.add_child(_hud_weapon_label)
	_update_combat_hud()

func _update_combat_hud() -> void:
	if not local_control or _hud_hp_label == null:
		return
	var hp_ratio := clampf(combat_hp / maxf(combat_max_hp, 1.0), 0.0, 1.0)
	_hud_hp_label.text = "HP  %d / %d%s" % [int(round(combat_hp)), int(round(combat_max_hp)), "  • BURN" if combat_burn > 0.02 else ""]
	# Remaining health stays anchored on the left; incoming damage therefore removes
	# the lit green lamp from right to left.
	_set_lamp_meter_ratio(_hud_hp_fill_clip, hp_ratio, 282.0)
	var weapon: String = String(_cfg().get("weapon", "smoky"))
	if weapon == "firebird":
		var fuel_ratio: float = clampf(combat_fuel / maxf(combat_fuel_max, 1.0), 0.0, 1.0)
		_hud_weapon_label.text = "FIREBIRD  %d%%" % int(round(fuel_ratio * 100.0))
		_set_lamp_meter_ratio(_hud_weapon_fill_clip, fuel_ratio, 282.0)
	else:
		var ready: float = clampf(_reload_visual_ratio, 0.0, 1.0)
		_hud_weapon_label.text = "%s  %s" % [weapon.to_upper(), "READY" if ready >= 0.999 else "RELOAD %d%%" % int(round(ready * 100.0))]
		# Reload grows from left to right over the darker unlit lamp.
		_set_lamp_meter_ratio(_hud_weapon_fill_clip, ready, 282.0)

func apply_combat_state(state: Dictionary) -> void:
	var was_alive: bool = combat_alive
	var old_hp: float = combat_hp
	combat_max_hp = maxf(float(state.get("max_hp", combat_max_hp)), 1.0)
	combat_hp = clampf(float(state.get("hp", combat_hp)), 0.0, combat_max_hp)
	combat_fuel_max = maxf(float(state.get("fuel_max", combat_fuel_max)), 0.0)
	combat_fuel = clampf(float(state.get("fuel", combat_fuel)), 0.0, maxf(combat_fuel_max, 0.0))
	combat_burn = clampf(float(state.get("burn", 0.0)), 0.0, 1.0)
	combat_burn_time = maxf(float(state.get("burn_time", 0.0)), 0.0)
	var buffs_value: Variant = state.get("buffs", {})
	if buffs_value is Dictionary:
		var buffs: Dictionary = buffs_value as Dictionary
		combat_nitro_time = maxf(float(buffs.get("nitro", 0.0)), 0.0)
		combat_nitro_multiplier = maxf(float(buffs.get("nitro_speed_multiplier", combat_nitro_multiplier)), 1.0)
		combat_armor_time = maxf(float(buffs.get("armor", 0.0)), 0.0)
		combat_damage_time = maxf(float(buffs.get("damage", 0.0)), 0.0)
	combat_alive = bool(state.get("alive", combat_alive))
	if old_hp - combat_hp > 0.5:
		_last_combat_hp = combat_hp
	if was_alive != combat_alive:
		_set_combat_alive(combat_alive)
	_update_combat_hud()

func set_match_controls_enabled(enabled: bool) -> void:
	match_controls_enabled = enabled
	if local_control or ai_control:
		freeze = not combat_alive or not enabled
	if not enabled:
		_drive_input = 0
		_turn_input = 0
		_turret_turn_velocity = 0.0
		firing = false
		_left_track_speed = 0.0
		_right_track_speed = 0.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false

func _capture_death_motion() -> void:
	# v18.18.23 death momentum: snapshots can mark the tank dead before the explicit
	# destroyed event arrives. Capture motion exactly once, before freeze/zeroing, so
	# the detached wreck inherits the velocity the tank actually had while driving.
	if _death_motion_captured:
		return
	var captured_linear: Vector3 = linear_velocity if (local_control or ai_control) else _target_linear_velocity
	var captured_angular: Vector3 = angular_velocity if (local_control or ai_control) else _target_angular_velocity
	# Network interpolation can occasionally have no velocity sample while still
	# carrying a valid signed speed. Reconstruct forward/reverse motion in that case.
	if captured_linear.length_squared() < 0.01 and absf(current_speed) > 0.05:
		captured_linear = -global_basis.z.normalized() * current_speed
	_death_linear_velocity = captured_linear
	_death_angular_velocity = captured_angular
	_death_motion_captured = true

func _set_combat_alive(alive: bool) -> void:
	if not alive:
		_capture_death_motion()
	combat_alive = alive
	if _visual_root != null:
		_visual_root.visible = true
	if local_control or ai_control:
		freeze = not alive or not match_controls_enabled
	else:
		freeze = true
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not alive
	if not alive:
		firing = false
		_turret_turn_velocity = 0.0
		_play_death_sound_once()
		# The live network actor stops here; its pre-death velocity was already copied
		# into _death_linear_velocity and will be transferred to the physical wreck.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		if local_control:
			_freeze_camera_for_death()
		_enter_destroyed_visual()
	else:
		_death_sound_played = false
		_death_motion_captured = false
		_ai_overturned_time = 0.0
		_ai_self_destruct_requested = false
		_death_linear_velocity = Vector3.ZERO
		_death_angular_velocity = Vector3.ZERO
		# If a cinematic respawn path is active, revive_at() releases the camera
		# only after the live tank has been teleported to the reserved spawn.
		if local_control and not _death_camera_path_ready:
			_release_death_camera()
		_restore_live_visuals()

func revive_at(transform: Transform3D, combat: Dictionary) -> void:
	_set_combat_alive(true)
	_reload_visual_ratio = 1.0
	_fire_cooldown = 0.0
	_death_sound_played = false
	teleport_spawn(transform)
	# Respawn always starts with the turret centered on the hull.
	turret_yaw = 0.0
	_target_turret = 0.0
	_turret_centering = false
	_turret_turn_velocity = 0.0
	if _turret_root != null:
		_turret_root.rotation.y = 0.0
	apply_combat_state(combat)
	sleeping = false
	if local_control:
		# v18.18.27: do NOT switch cameras in the same physics frame as the
		# teleport. In the old flow the live SpringArm camera became current before
		# SpringArm3D had recomputed its extension, producing one close-up frame
		# inside the tank (visible as a screen flash in recordings).
		#
		# Snap the cinematic camera to the exact final target, move the live rig,
		# reset interpolation, then keep the cinematic camera current for three
		# physics frames while the hidden live SpringArm settles.
		if _death_camera != null and is_instance_valid(_death_camera):
			if _respawn_camera_target != null and is_instance_valid(_respawn_camera_target):
				_death_camera.global_transform = _respawn_camera_target.global_transform
				_death_camera.fov = _respawn_camera_target.fov
			_death_camera.reset_physics_interpolation()
		_update_stable_camera_pivot()
		_reset_live_camera_interpolation()
		if _death_camera != null and is_instance_valid(_death_camera):
			_respawn_camera_handoff_frames = 3
			_death_camera.current = true
			if _camera != null and is_instance_valid(_camera):
				_camera.current = false
		else:
			_release_death_camera()

func play_combat_event(data: Dictionary) -> void:
	var kind: String = String(data.get("event", ""))
	if kind == "hit":
		_spawn_confirmed_hit_fx(data)
		_apply_incoming_hit_impulse(data)
	elif kind == "destroyed":
		# The event may beat the next dead snapshot, so save movement here as well.
		_capture_death_motion()
		_play_death_sound_once()
		_enter_destroyed_visual()
		_spawn_destroyed_fx(data)
		_spawn_hull_debris(data)
		_start_wreck_fire(2.45)

func _event_vec3(data: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = data.get(key, null)
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback

func _spawn_confirmed_hit_fx(data: Dictionary) -> void:
	var impact: Vector3 = _event_vec3(data, "impact", global_position + Vector3.UP * 0.8)
	var weapon: String = String(data.get("weapon", "smoky"))
	if weapon == "thunder":
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", impact, 16, 39, 0.48, 1.65, 3.6, Vector3.UP * 0.32, Vector3.UP * 0.08, 0.98, 0.70, randf_range(-0.35, 0.35))
		_spawn_sheet_fx("res://assets/effects/fire_rgba.png", impact + Vector3.UP * 0.08, 32, 47, 0.30, 1.1, 2.2, Vector3.UP * 0.22, Vector3.ZERO, 0.94, 0.68, randf_range(-0.4, 0.4))
		_spawn_flash_light(impact, Color(1.0, 0.46, 0.12), 6.8, 7.5, 0.18)
	else:
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", impact, 40, 47, 0.24, 0.62, 1.35, Vector3.UP * 0.12, Vector3.ZERO, 0.92, 0.72, randf_range(-0.45, 0.45))
		_spawn_flash_light(impact, Color(1.0, 0.63, 0.28), 2.8, 4.0, 0.10)

func _apply_incoming_hit_impulse(data: Dictionary) -> void:
	# Only the owning client simulates the live rigid body. The resulting movement
	# is then replicated to everybody else by the normal state stream.
	if not (local_control or ai_control) or not combat_alive or freeze:
		return
	var weapon: String = String(data.get("weapon", "smoky"))
	if weapon == "firebird":
		return
	var impact: Vector3 = _event_vec3(data, "impact", global_position + Vector3.UP * 0.65)
	var origin: Vector3 = _event_vec3(data, "origin", impact + global_basis.z)
	var direction: Vector3 = impact - origin
	if direction.length_squared() < 0.0001:
		direction = -global_basis.z
	direction = direction.normalized()
	var direct: bool = String(data.get("damage_kind", "direct")) == "direct"
	var impulse_strength: float = 1.05 if weapon == "smoky" else 3.35
	if not direct:
		impulse_strength *= 0.48
	# Fixed world impulse is intentional: RigidBody3D naturally converts it to a
	# smaller delta-v on Viking/Mamont than on Wasp. Applying it at the hit point
	# also creates the requested yaw/roll when a shell strikes the side.
	var impulse: Vector3 = direction * impulse_strength + Vector3.UP * impulse_strength * 0.10
	var offset: Vector3 = impact - global_position
	apply_impulse(impulse, offset)
	if weapon == "thunder":
		_rock_velocity += clampf(direction.dot(-global_basis.z), -1.0, 1.0) * 0.10
	else:
		_rock_velocity += clampf(direction.dot(-global_basis.z), -1.0, 1.0) * 0.035
	_rock_velocity = clampf(_rock_velocity, -0.46, 0.46)
	sleeping = false

func _spawn_destroyed_fx(_data: Dictionary = {}) -> void:
	var center: Vector3 = global_position + Vector3.UP * 1.00
	# v18.18.23: the previous death effect stacked fourteen large, heavily dark-tinted
	# billboards. Their low-alpha halos accumulated into the grey plate / black box
	# visible around a destroyed tank. Use a compact explosion plus soft neutral smoke.
	# These are the same clean atlas ranges already used by normal hit effects.
	_spawn_sheet_fx(
		"res://assets/effects/smoky_rgba.png",
		center,
		16,
		31,
		0.54,
		1.35,
		3.35,
		Vector3.UP * 0.42,
		Vector3.UP * 0.06,
		0.96,
		0.66,
		randf_range(-0.26, 0.26),
		Color(1.0, 0.94, 0.84, 1.0)
	)
	_spawn_sheet_fx(
		"res://assets/effects/fire_rgba.png",
		center + Vector3.UP * 0.08,
		32,
		47,
		0.62,
		0.92,
		2.10,
		Vector3.UP * 0.34,
		Vector3.UP * 0.03,
		0.84,
		0.62,
		randf_range(-0.22, 0.22),
		Color(1.0, 0.94, 0.88, 1.0)
	)
	for smoke_index in range(3):
		var smoke_offset := Vector3(randf_range(-0.48, 0.48), randf_range(0.20, 0.66), randf_range(-0.48, 0.48))
		_spawn_sheet_fx(
			"res://assets/effects/smoky_rgba.png",
			center + smoke_offset,
			0,
			15,
			randf_range(1.15, 1.55),
			randf_range(0.82, 1.10),
			randf_range(1.85, 2.55),
			Vector3(randf_range(-0.12, 0.12), randf_range(0.58, 0.94), randf_range(-0.12, 0.12)),
			Vector3.UP * 0.02,
			randf_range(0.30, 0.40),
			0.30,
			randf_range(-0.10, 0.10),
			Color(0.72, 0.69, 0.65, 1.0)
		)
	_spawn_flash_light(center + Vector3.UP * 0.55, Color(1.0, 0.34, 0.05), 7.5, 8.0, 0.22, false)

func _enter_destroyed_visual() -> void:
	if _visual_root == null:
		return
	if _wreck_material_backups.is_empty():
		var corrosion_value: Variant = load("res://assets/effects/destroyed_corrosion.png")
		if corrosion_value is Texture2D:
			_apply_wreck_materials_recursive(_visual_root, corrosion_value as Texture2D)
	if _turret_root != null:
		if not _turret_debris_spawned:
			_spawn_turret_debris()
		_turret_root.visible = false
	if _wreck_body_spawned and _visual_root != null:
		_visual_root.visible = false

func _restore_live_visuals() -> void:
	for item in _wreck_material_backups:
		var mesh_value: Variant = item.get("mesh", null)
		var material_value: Variant = item.get("material", null)
		if mesh_value is MeshInstance3D and is_instance_valid(mesh_value):
			(mesh_value as MeshInstance3D).material_override = material_value as Material
	_wreck_material_backups.clear()
	_wreck_fire_remaining = 0.0
	_wreck_fire_emit_elapsed = 0.0
	_wreck_fire_light_elapsed = 0.0
	_turret_debris_spawned = false
	_wreck_body_spawned = false
	if _wreck_body_debris != null and is_instance_valid(_wreck_body_debris):
		_wreck_body_debris.queue_free()
	_wreck_body_debris = null
	if _visual_root != null:
		_visual_root.visible = true
	if _turret_root != null:
		_turret_root.visible = true

func _apply_wreck_materials_recursive(node: Node, _corrosion: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var old_material: Material = mesh_node.material_override
		if old_material != null:
			# Do not replace the paint texture with destroyed_corrosion.png. The paint
			# shader treats that image as a repeating camouflage source; on broad armour
			# surfaces it can collapse almost to black and make the wreck look like a cube.
			if old_material is ShaderMaterial:
				var source_shader_mat := old_material as ShaderMaterial
				if source_shader_mat.shader == TankPaintShader:
					_wreck_material_backups.append({"mesh":mesh_node, "material":old_material})
					var wreck_shader: ShaderMaterial = source_shader_mat.duplicate() as ShaderMaterial
					wreck_shader.set_shader_parameter("wreck_amount", 0.82)
					wreck_shader.set_shader_parameter("wreck_tint", Vector3(0.50, 0.39, 0.31))
					wreck_shader.set_shader_parameter("wreck_tex", _corrosion)
					wreck_shader.set_shader_parameter("wreck_scale", 1.12)
					wreck_shader.set_shader_parameter("wreck_texture_strength", 0.78)
					wreck_shader.set_shader_parameter("roughness_floor", 0.96)
					wreck_shader.set_shader_parameter("metallic_ceiling", 0.04)
					mesh_node.material_override = wreck_shader
			elif old_material is StandardMaterial3D:
				_wreck_material_backups.append({"mesh":mesh_node, "material":old_material})
				var wreck_standard: StandardMaterial3D = old_material.duplicate() as StandardMaterial3D
				# Keep the authored diffuse texture readable; only add a moderate char tint.
				wreck_standard.albedo_color *= Color(0.68, 0.58, 0.50, 1.0)
				wreck_standard.roughness = maxf(wreck_standard.roughness, 0.94)
				wreck_standard.metallic = minf(wreck_standard.metallic, 0.05)
				mesh_node.material_override = wreck_standard
	for child in node.get_children():
		_apply_wreck_materials_recursive(child, _corrosion)

func _spawn_turret_debris() -> void:
	if _turret_root == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	_turret_debris_spawned = true
	var debris := RigidBody3D.new()
	debris.name = "DestroyedTurret_%d" % player_id
	debris.mass = 1.05
	debris.gravity_scale = 1.0
	debris.linear_damp = 0.08
	debris.angular_damp = 0.11
	debris.collision_layer = 0
	debris.collision_mask = 1
	scene_root.add_child(debris)
	debris.global_transform = _turret_root.global_transform
	# Inherit the velocity of the tank before adding the explosion kick. This makes
	# a turret from a moving tank continue travelling instead of jumping straight up.
	debris.linear_velocity = _death_linear_velocity * 0.90
	debris.angular_velocity = _death_angular_velocity * 0.35
	# Do NOT use DUPLICATE_USE_INSTANTIATION here. Imported tank scenes contain
	# helper meshes (shadow/Box*/simple/body) hidden at runtime; reinstantiation
	# restores them and produces the giant square / black cube on death.
	var visual_copy: Node = _turret_root.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	debris.add_child(visual_copy)
	if visual_copy is Node3D:
		(visual_copy as Node3D).transform = Transform3D.IDENTITY
	var muzzle_copy: Node = visual_copy.get_node_or_null("Muzzle")
	if muzzle_copy != null:
		muzzle_copy.queue_free()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.75, 0.75, 2.15)
	collision.shape = shape
	debris.add_child(collision)
	var side: Vector3 = global_basis.x.normalized() * randf_range(-2.0, 2.0)
	var travel: Vector3 = Vector3(_death_linear_velocity.x, 0.0, _death_linear_velocity.z)
	var travel_kick: Vector3 = Vector3.ZERO
	if travel.length_squared() > 0.04:
		travel_kick = travel.normalized() * minf(travel.length() * 0.20, 1.5)
	var kick: Vector3 = Vector3.UP * randf_range(8.8, 12.5) + side + travel_kick
	debris.apply_central_impulse(kick * debris.mass)
	debris.apply_torque_impulse(Vector3(randf_range(-4.8, 4.8), randf_range(-3.2, 3.2), randf_range(-4.8, 4.8)))
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(debris.queue_free)

func _spawn_hull_debris(data: Dictionary) -> void:
	if _visual_root == null or _wreck_body_spawned:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	_wreck_body_spawned = true
	var debris := RigidBody3D.new()
	debris.name = "DestroyedHull_%d" % player_id
	debris.mass = maxf(mass * 0.78, 0.9)
	debris.gravity_scale = 1.0
	debris.linear_damp = 0.09
	debris.angular_damp = 0.13
	debris.collision_layer = 0
	debris.collision_mask = 1
	scene_root.add_child(debris)
	debris.global_transform = global_transform
	# Preserve pre-death motion first. Explosion impulse is then additive, so a tank
	# driving forward keeps travelling forward while being lifted off the ground.
	debris.linear_velocity = _death_linear_velocity * 0.92
	debris.angular_velocity = _death_angular_velocity * 0.55
	# Duplicate the CURRENT runtime tree instead of reinstantiating imported DAE.
	# Runtime visibility/material changes must survive into the wreck; otherwise
	# the source DAE's hidden shadow plane and helper Box meshes become visible.
	var visual_copy: Node = _visual_root.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	debris.add_child(visual_copy)
	if visual_copy is Node3D:
		(visual_copy as Node3D).transform = _visual_root.transform
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var size_value: Vector3 = _cfg()["size"]
	shape.size = Vector3(size_value.x * 0.82, size_value.y * 0.68, size_value.z * 0.82)
	collision.shape = shape
	collision.position = Vector3(0.0, size_value.y * 0.52, 0.0)
	debris.add_child(collision)
	var impact: Vector3 = _event_vec3(data, "impact", global_position + Vector3.UP * 0.7)
	var origin: Vector3 = _event_vec3(data, "origin", impact + global_basis.z * 2.0)
	var direction: Vector3 = impact - origin
	if direction.length_squared() < 0.0001:
		direction = -global_basis.z
	direction = direction.normalized()
	var weapon: String = String(data.get("weapon", "smoky"))
	var blast: float = 5.4
	if weapon == "thunder":
		blast = 11.8
	elif weapon == "firebird":
		blast = 4.2
	elif weapon == "self_destruct":
		blast = 8.6
		# A self-destruction has no attacker direction. Let the saved driving velocity
		# define horizontal travel instead of inventing a forward blast vector.
		direction = Vector3.ZERO
	var death_impulse: Vector3 = direction * blast + Vector3.UP * (5.4 + blast * 0.60)
	var travel: Vector3 = Vector3(_death_linear_velocity.x, 0.0, _death_linear_velocity.z)
	if travel.length_squared() > 0.04:
		# Small extra directional carry makes the movement readable even on heavy hulls;
		# most of the momentum still comes from debris.linear_velocity above.
		death_impulse += travel * debris.mass * 0.18
	var relative_hit: Vector3 = impact - global_position
	debris.apply_impulse(death_impulse, relative_hit)
	var hit_spin: Vector3 = relative_hit.cross(direction) * (0.90 + blast * 0.32)
	var blast_spin := Vector3(randf_range(-1.8, 1.8), randf_range(-1.15, 1.15), randf_range(-1.8, 1.8))
	debris.apply_torque_impulse(hit_spin + blast_spin)
	_wreck_body_debris = debris
	_visual_root.visible = false
	var timer := get_tree().create_timer(5.5)
	timer.timeout.connect(debris.queue_free)

func _build_body() -> void:
	var cfg: Dictionary = _cfg()
	var s: Vector3 = cfg["size"]
	mass = float(cfg["physics_mass"])
	gravity_scale = 1.0
	linear_damp = float(cfg.get("linear_damp", 0.12))
	angular_damp = float(cfg.get("angular_damp", 0.95))
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 24
	# Local player tanks must never remain asleep while controls are held.
	can_sleep = not (local_control or ai_control)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, s.y * 0.34, 0.0)

	var physical_material := PhysicsMaterial.new()
	physical_material.friction = 0.14
	physical_material.bounce = 0.0
	physics_material_override = physical_material

	# Track collision is a beveled convex prism rather than a vertical box. The
	# sloped lower nose lets a track physically ride over bricks/curbs instead of
	# hitting an invisible vertical bumper. Outer edges follow the visible tracks
	# more closely, so the hull also cannot sink deeply into walls.
	# Keep the physical envelope slightly inside the visible model. Arena contains
	# many tiny protruding triangles; a forgiving envelope prevents track corners
	# from hooking on decoration while still preserving real wall/vehicle collision.
	# Hull and belly also use beveled lower edges. A square belly can hook a single
	# brick triangle even when the tracks themselves are rounded.
	_add_beveled_box_collision("HullCollision", Vector3(s.x * 0.57, s.y * 0.48, s.z * 0.50), Vector3(0.0, s.y * 0.62, 0.01 * s.z), 0.10, 0.14)
	_add_track_collision("LeftTrackCollision", -1.0, s)
	_add_track_collision("RightTrackCollision", 1.0, s)
	_add_beveled_box_collision("BellyCollision", Vector3(s.x * 0.30, s.y * 0.065, s.z * 0.24), Vector3(0.0, s.y * 0.225, 0.02 * s.z), 0.22, 0.28)

func _add_box_collision(collision_name: String, shape_size: Vector3, local_position: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	var shape := BoxShape3D.new()
	shape.size = shape_size
	collision.shape = shape
	collision.position = local_position
	add_child(collision)

func _add_beveled_box_collision(collision_name: String, shape_size: Vector3, local_position: Vector3, side_inset: float, end_inset: float) -> void:
	var hx: float = shape_size.x * 0.5
	var hy: float = shape_size.y * 0.5
	var hz: float = shape_size.z * 0.5
	var lower_x: float = hx * (1.0 - clampf(side_inset, 0.0, 0.35))
	var lower_z: float = hz * (1.0 - clampf(end_inset, 0.0, 0.35))
	var points := PackedVector3Array([
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz),
		Vector3(-hx, hy, hz), Vector3(hx, hy, hz),
		Vector3(-lower_x, -hy, -lower_z), Vector3(lower_x, -hy, -lower_z),
		Vector3(-lower_x, -hy, lower_z), Vector3(lower_x, -hy, lower_z)
	])
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape.margin = 0.012
	collision.shape = shape
	collision.position = local_position
	add_child(collision)

func _add_track_collision(collision_name: String, side_sign: float, s: Vector3) -> void:
	# The original 2011 demo behaved as if the track nose was rounded rather than a
	# hard rectangular corner.  Build an elliptical end profile here so small brick
	# edges produce a gradually changing contact normal instead of solver-locking the
	# tank on one sharp vertex.  It is still one solid convex shape per track.
	var center_x: float = side_sign * s.x * 0.350
	var half_width: float = s.x * 0.122
	var x0: float = center_x - half_width
	var x1: float = center_x + half_width
	var front_tip: float = -s.z * 0.438
	var rear_tip: float = s.z * 0.425
	var bottom_y: float = float(_cfg().get("track_collision_bottom", 0.005)) + 0.055
	var top_y: float = s.y * 0.485
	var mid_y: float = (top_y + bottom_y) * 0.5
	var radius_y: float = (top_y - bottom_y) * 0.5
	var nose_radius_z: float = s.z * 0.185
	var tail_radius_z: float = s.z * 0.145
	var front_center_z: float = front_tip + nose_radius_z
	var rear_center_z: float = rear_tip - tail_radius_z
	var points := PackedVector3Array()
	var arc_angles: Array[float] = [90.0, 60.0, 30.0, 0.0, -30.0, -60.0, -90.0]
	for x_value_variant in [x0, x1]:
		var x_value: float = float(x_value_variant)
		for angle_deg in arc_angles:
			var angle_rad: float = deg_to_rad(angle_deg)
			points.append(Vector3(
				x_value,
				mid_y + sin(angle_rad) * radius_y,
				front_center_z - cos(angle_rad) * nose_radius_z
			))
		for angle_deg in arc_angles:
			var angle_rad: float = deg_to_rad(angle_deg)
			points.append(Vector3(
				x_value,
				mid_y + sin(angle_rad) * radius_y,
				rear_center_z + cos(angle_rad) * tail_radius_z
			))
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	# A smaller margin avoids invisible catches on the highly tessellated Arena
	# collision while CCD still protects the moving rigid body from tunnelling.
	shape.margin = 0.018
	collision.shape = shape
	add_child(collision)

func _build_visuals() -> void:
	var cfg: Dictionary = _cfg()
	var tint: Color = cfg["tint"]
	var hull_dir: String = String(cfg["texture_dir"])
	var turret_dir: String = String(cfg["turret_texture_dir"])
	var paint: Dictionary = cfg["paint"]
	var track_albedo := hull_dir + "/tracks_diffuse.png"
	var track_roughness := hull_dir + "/tracks_roughness.png"
	var track_metallic := hull_dir + "/tracks_metallic.png"
	var track_normal := hull_dir + "/tracks_detail_normal.png"

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.position.y = 0.03
	add_child(_visual_root)

	_running_gear_root = Node3D.new()
	_running_gear_root.name = "RunningGear"
	_visual_root.add_child(_running_gear_root)

	_body_rock_root = Node3D.new()
	_body_rock_root.name = "SprungBody"
	_running_gear_root.add_child(_body_rock_root)

	var turret_position: Vector3 = cfg["turret_mount"]
	var hull_resource: Resource = load(String(cfg["hull"]))
	if hull_resource is PackedScene:
		var imported: Node = (hull_resource as PackedScene).instantiate()
		_running_gear_root.add_child(imported)
		_prepare_hull_import(imported, hull_dir, paint, track_albedo, track_roughness, track_metallic, track_normal)
		var mount_node: Node = _find_named_recursive(imported, "mount")
		if mount_node is Node3D:
			turret_position = _body_rock_root.to_local((mount_node as Node3D).global_position)
		_move_hull_mesh_to_sprung_body(imported)
	else:
		_build_hull_fallback(cfg, tint, hull_dir, paint)

	_turret_root = Node3D.new()
	_turret_root.name = "Turret"
	_turret_root.position = turret_position
	_body_rock_root.add_child(_turret_root)

	var turret_resource: Resource = load(String(cfg["turret"]))
	if turret_resource is Mesh:
		var turret_mesh := MeshInstance3D.new()
		turret_mesh.name = "OriginalTurretMesh"
		turret_mesh.mesh = turret_resource as Mesh
		turret_mesh.material_override = _paint_material(turret_dir, paint, 0.72, 0.14, 0.30)
		_turret_root.add_child(turret_mesh)
	elif turret_resource is PackedScene:
		var turret_scene: Node = (turret_resource as PackedScene).instantiate()
		_turret_root.add_child(turret_scene)
		_apply_paint(turret_scene, turret_dir, paint, 0.72, 0.14, 0.30)
	else:
		_build_turret_fallback(tint, turret_dir, paint)

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = cfg["muzzle"]
	_turret_root.add_child(_muzzle)
	_build_flame()
	_build_muzzle_soot()
	_camera_anchor_base = to_local(_turret_root.global_position)

func _build_hull_fallback(cfg: Dictionary, tint: Color, texture_dir: String, paint: Dictionary) -> void:
	var fallback := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = cfg["size"]
	fallback.mesh = mesh
	var fallback_size: Vector3 = cfg["size"]
	fallback.position.y = fallback_size.y * 0.5
	fallback.material_override = _paint_material(texture_dir, paint, 0.76, 0.12, 0.26, tint)
	_body_rock_root.add_child(fallback)

func _build_turret_fallback(tint: Color, texture_dir: String, paint: Dictionary) -> void:
	var turret := MeshInstance3D.new()
	var turret_mesh := BoxMesh.new()
	turret_mesh.size = Vector3(1.8, 0.65, 2.2)
	turret.mesh = turret_mesh
	turret.position.y = 0.25
	turret.material_override = _paint_material(texture_dir, paint, 0.72, 0.14, 0.30, tint)
	_turret_root.add_child(turret)

func _material(
	color: Color,
	albedo_path: String = "",
	roughness_value: float = 0.70,
	metallic_value: float = 0.14,
	roughness_path: String = "",
	metallic_path: String = "",
	normal_path: String = "",
	normal_scale_value: float = 0.24
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness_value
	mat.metallic = metallic_value
	if albedo_path != "":
		var albedo_tex := load(albedo_path)
		if albedo_tex is Texture2D:
			mat.albedo_texture = albedo_tex
	if roughness_path != "":
		var rough_tex := load(roughness_path)
		if rough_tex is Texture2D:
			mat.roughness_texture = rough_tex
	if metallic_path != "":
		var metal_tex := load(metallic_path)
		if metal_tex is Texture2D:
			mat.metallic_texture = metal_tex
	if normal_path != "":
		var normal_tex := load(normal_path)
		if normal_tex is Texture2D:
			mat.normal_texture = normal_tex
			mat.normal_scale = normal_scale_value
	return mat

func _track_material(mesh_node: MeshInstance3D, albedo_path: String, roughness_path: String, metallic_path: String, normal_path: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scroll = 0.0;
uniform float track_z_min = -1.0;
uniform float track_z_max = 1.0;
uniform float track_y_min = -0.5;
uniform float track_y_max = 0.5;
uniform float deform_0 = 0.0;
uniform float deform_1 = 0.0;
uniform float deform_2 = 0.0;
uniform float deform_3 = 0.0;
uniform float deform_4 = 0.0;
uniform float deform_5 = 0.0;
uniform float deform_6 = 0.0;
uniform float deform_7 = 0.0;
uniform float deform_8 = 0.0;
uniform float deform_9 = 0.0;

float sample_deform(float t) {
	float x = clamp(t, 0.0, 1.0) * 9.0;
	int section = int(floor(min(x, 8.9999)));
	float f = smoothstep(0.0, 1.0, fract(x));
	if (section == 0) return mix(deform_0, deform_1, f);
	if (section == 1) return mix(deform_1, deform_2, f);
	if (section == 2) return mix(deform_2, deform_3, f);
	if (section == 3) return mix(deform_3, deform_4, f);
	if (section == 4) return mix(deform_4, deform_5, f);
	if (section == 5) return mix(deform_5, deform_6, f);
	if (section == 6) return mix(deform_6, deform_7, f);
	if (section == 7) return mix(deform_7, deform_8, f);
	return mix(deform_8, deform_9, f);
}

void vertex() {
	float z_span = max(track_z_max - track_z_min, 0.0001);
	float y_span = max(track_y_max - track_y_min, 0.0001);
	float t = clamp((VERTEX.z - track_z_min) / z_span, 0.0, 1.0);
	// Deform only the lower belt.  v17.7 also moved most of the front/rear wrap,
	// which stretched long triangles into the hull and produced the black "fingers"
	// visible under the tank.  The guarded end profile still lets the contact patch
	// climb a curb, but keeps the upper wrap and return run locked to the chassis.
	float lower_weight = 1.0 - smoothstep(track_y_min + y_span * 0.26, track_y_min + y_span * 0.64, VERTEX.y);
	float edge_distance = min(t, 1.0 - t);
	float end_guard = smoothstep(0.035, 0.155, edge_distance);
	float end_lower_weight = 1.0 - smoothstep(track_y_min + y_span * 0.16, track_y_min + y_span * 0.43, VERTEX.y);
	float deform_weight = mix(end_lower_weight * 0.34, lower_weight, end_guard);
	VERTEX.y += sample_deform(t) * deform_weight;
}

void fragment() {
	vec2 uv = UV * vec2(1.0, 2.2) + vec2(0.0, uv_scroll);
	ALBEDO = texture(albedo_tex, uv).rgb;
	float rough_sample = texture(roughness_tex, uv).r;
	ROUGHNESS = mix(0.82, 1.0, rough_sample);
	METALLIC = texture(metallic_tex, uv).r * 0.03;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.26;
	SPECULAR = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", load(albedo_path))
	mat.set_shader_parameter("roughness_tex", load(roughness_path))
	mat.set_shader_parameter("metallic_tex", load(metallic_path))
	mat.set_shader_parameter("normal_tex", load(normal_path))
	if mesh_node.mesh != null:
		var bounds: AABB = mesh_node.mesh.get_aabb()
		mat.set_shader_parameter("track_z_min", bounds.position.z)
		mat.set_shader_parameter("track_z_max", bounds.position.z + bounds.size.z)
		mat.set_shader_parameter("track_y_min", bounds.position.y)
		mat.set_shader_parameter("track_y_max", bounds.position.y + bounds.size.y)
	return mat

func _paint_material(texture_dir: String, paint: Dictionary, roughness_floor: float, metallic_ceiling: float, normal_depth: float, fallback_tint: Color = Color.WHITE) -> Material:
	var paint_texture_value: Variant = paint.get("texture_object", null)
	if not (paint_texture_value is Texture2D):
		return _material(
			fallback_tint,
			texture_dir + "/diffuse.png",
			roughness_floor,
			metallic_ceiling,
			texture_dir + "/roughness.png",
			texture_dir + "/metallic.png",
			texture_dir + "/detail_normal.png",
			normal_depth
		)
	var paint_texture: Texture2D = paint_texture_value
	var mat := ShaderMaterial.new()
	mat.shader = TankPaintShader
	mat.set_shader_parameter("base_tex", load(texture_dir + "/diffuse.png"))
	mat.set_shader_parameter("surface_tex", load(texture_dir + "/surface.png"))
	mat.set_shader_parameter("paint_tex", paint_texture)
	mat.set_shader_parameter("roughness_tex", load(texture_dir + "/roughness.png"))
	mat.set_shader_parameter("metallic_tex", load(texture_dir + "/metallic.png"))
	mat.set_shader_parameter("normal_tex", load(texture_dir + "/detail_normal.png"))
	mat.set_shader_parameter("wear_tex", load(texture_dir + "/wear_mask.png"))
	mat.set_shader_parameter("paint_scale", float(paint.get("scale", 2.55)))
	mat.set_shader_parameter("paint_strength", float(paint.get("strength", 0.76)))
	mat.set_shader_parameter("roughness_floor", roughness_floor)
	mat.set_shader_parameter("metallic_ceiling", metallic_ceiling)
	mat.set_shader_parameter("normal_depth", normal_depth)
	return mat

func _prepare_hull_import(
	node: Node,
	hull_texture_dir: String,
	paint: Dictionary,
	track_texture: String,
	track_roughness: String,
	track_metallic: String,
	track_normal: String
) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var part_name := String(mesh_node.name).to_lower()
		var is_hull := part_name == "hull"
		var is_track := part_name == "ltrack" or part_name == "rtrack"
		var is_wheel := part_name.begins_with("whl_") or part_name.begins_with("whr_")
		var is_render_part := is_hull or is_track or is_wheel
		mesh_node.visible = is_render_part
		# v17.9 gives the running gear a neutral droop reserve. Tracks and wheels are
		# lowered together, while the hull/turret stay where they were. On contact the
		# visual suspension can now compress upward instead of having to stretch the
		# belt down into the terrain to reach a low wheel.
		if is_track or is_wheel:
			mesh_node.position.y -= float(_cfg().get("running_gear_drop", 0.0))
		if is_render_part:
			if is_track:
				var tmat: ShaderMaterial = _track_material(mesh_node, track_texture, track_roughness, track_metallic, track_normal)
				mesh_node.material_override = tmat
				if part_name == "ltrack":
					_left_track_mats.append(tmat)
				else:
					_right_track_mats.append(tmat)
			else:
				mesh_node.material_override = _paint_material(hull_texture_dir, paint, 0.76, 0.12, 0.26)
		if is_wheel:
			var wheel := mesh_node as Node3D
			var key := wheel.get_instance_id()
			_wheel_local_pos[key] = wheel.position
			_wheel_local_rot[key] = wheel.rotation
			# The old code used the physics radius for visual ground clearance. Wasp and
			# Viking art wheels are visibly larger, so their mesh could sink through the
			# floor even when the suspension ray itself was correct. Cache the actual
			# imported wheel half-height and never use a smaller visual radius.
			var visual_radius: float = float(_cfg().get("wheel_radius", 0.30))
			if mesh_node.mesh != null:
				var wheel_bounds: AABB = mesh_node.mesh.get_aabb()
				visual_radius = maxf(visual_radius, wheel_bounds.size.y * 0.5)
			_wheel_visual_radius[key] = clampf(visual_radius, 0.18, 0.62)
			_wheel_spin[key] = 0.0
			if part_name.begins_with("whl_"):
				_left_wheels.append(wheel)
			else:
				_right_wheels.append(wheel)
	for child in node.get_children():
		_prepare_hull_import(child, hull_texture_dir, paint, track_texture, track_roughness, track_metallic, track_normal)

func _move_hull_mesh_to_sprung_body(node: Node) -> void:
	var hull_nodes: Array[Node3D] = []
	_collect_named_meshes(node, "hull", hull_nodes)
	for hull_node in hull_nodes:
		if hull_node != null and hull_node.get_parent() != _body_rock_root:
			hull_node.reparent(_body_rock_root, true)

func _collect_named_meshes(node: Node, wanted: String, out: Array[Node3D]) -> void:
	if node is MeshInstance3D and String(node.name).to_lower() == wanted:
		out.append(node as Node3D)
	for child in node.get_children():
		_collect_named_meshes(child, wanted, out)

func _apply_paint(node: Node, texture_dir: String, paint: Dictionary, roughness_floor: float, metallic_ceiling: float, normal_depth: float) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _paint_material(texture_dir, paint, roughness_floor, metallic_ceiling, normal_depth)
	for child in node.get_children():
		_apply_paint(child, texture_dir, paint, roughness_floor, metallic_ceiling, normal_depth)

func _find_named_recursive(node: Node, wanted: String) -> Node:
	if String(node.name).to_lower() == wanted.to_lower():
		return node
	for child in node.get_children():
		var found: Node = _find_named_recursive(child, wanted)
		if found != null:
			return found
	return null

func _is_primary_road_wheel(wheel: Node3D) -> bool:
	var wheel_name: String = String(wheel.name).to_lower()
	return wheel_name.begins_with("whl_1_") or wheel_name.begins_with("whr_1_")

func _primary_road_wheel_count() -> int:
	var count: int = 0
	for wheel in _left_wheels:
		if wheel != null and _is_primary_road_wheel(wheel):
			count += 1
	for wheel in _right_wheels:
		if wheel != null and _is_primary_road_wheel(wheel):
			count += 1
	return count

func _rebuild_suspension_points() -> void:
	_suspension_points.clear()
	var cfg: Dictionary = _cfg()
	var travel: float = float(cfg["suspension_travel"])
	var radius: float = float(cfg["wheel_radius"])
	var k: float = float(cfg["suspension_k"])
	var primary_count: int = _primary_road_wheel_count()
	var support_count: int = maxi(1, primary_count)
	var static_sag: float = (mass * WORLD_GRAVITY) / (float(support_count) * maxf(k, 1.0))

	_append_suspension_from_wheels(_left_wheels, -1.0, travel, radius, static_sag)
	_append_suspension_from_wheels(_right_wheels, 1.0, travel, radius, static_sag)

	if _suspension_points.is_empty():
		var s: Vector3 = cfg["size"]
		for side in [-1.0, 1.0]:
			for z_factor in [-0.34, -0.17, 0.0, 0.17, 0.34]:
				var wheel_center := Vector3(side * s.x * 0.31, radius + 0.08, float(z_factor) * s.z)
				var anchor := wheel_center + Vector3.UP * travel
				_suspension_points.append({
					"anchor": anchor,
					"side": side,
					"max_len": maxf(radius + travel + static_sag, anchor.y + static_sag),
					"static_sag": static_sag
				})

func _append_suspension_from_wheels(wheels: Array[Node3D], side: float, travel: float, radius: float, static_sag: float) -> void:
	for wheel in wheels:
		if wheel == null or not _is_primary_road_wheel(wheel):
			continue
		# Wheels are visually lowered in v17.9, but the rigid-body suspension geometry
		# must remain identical to v17.8. Add the visual drop back before building the
		# physics ray anchor so handling/collision behaviour does not silently change.
		var wheel_local: Vector3 = to_local(wheel.global_position) + Vector3.UP * float(_cfg().get("running_gear_drop", 0.0))
		var anchor: Vector3 = wheel_local + Vector3.UP * travel
		# v13 used only configured wheel radius as the ray length. Imported road-wheel
		# centres are higher than that, so the rays ended above the floor and the body
		# first had to sink into the map before suspension could see a contact.
		var neutral_floor_distance: float = maxf(radius + travel, anchor.y)
		_suspension_points.append({
			"anchor": anchor,
			"side": side,
			"max_len": neutral_floor_distance + static_sag,
			"static_sag": static_sag
		})

func teleport_spawn(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	# A respawn is a true teleport, not a movement sample. Without resetting
	# interpolation Godot may render one in-between frame between the death
	# position and the spawn position.
	reset_physics_interpolation()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_speed_for_rock = 0.0
	_last_yaw_rate_for_rock = 0.0
	sleeping = false

func _build_muzzle_soot() -> void:
	if _muzzle == null:
		return
	var tex := load("res://assets/textures/soot.png")
	if not (tex is Texture2D):
		return
	var weapon := String(_cfg()["weapon"])
	var diameter := 0.46
	if weapon == "firebird":
		diameter = 0.62
	elif weapon == "thunder":
		diameter = 0.86
	# Two almost-coplanar soot cards sit on the muzzle face. They are attached to
	# the barrel instead of the camera, so the stain reads as burnt metal rather
	# than a floating VFX sprite.
	for i in range(2):
		var soot := Sprite3D.new()
		soot.name = "MuzzleSoot_%d" % i
		soot.texture = tex as Texture2D
		soot.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		soot.shaded = true
		soot.transparent = true
		soot.double_sided = true
		soot.pixel_size = (diameter * (1.0 + float(i) * 0.20)) / 256.0
		soot.modulate = Color(0.34, 0.31, 0.28, 0.52 if i == 0 else 0.25)
		soot.position = Vector3(0.0, 0.0, 0.012 + float(i) * 0.008)
		soot.rotation.z = float(i) * 0.55
		_muzzle.add_child(soot)

func _build_flame() -> void:
	if String(_cfg().get("weapon", "")) != "firebird":
		return
	_flame_root = Node3D.new()
	_flame_root.name = "FlamethrowerEmitter"
	_muzzle.add_child(_flame_root)

	# Only Firebird actors own Firebird lights. Attach the two lights directly to
	# the actor as top-level nodes and update their world positions while firing.
	# This avoids imported-turret transform quirks and removes zero-energy OmniLights
	# from Smoky/Thunder tanks in the Compatibility renderer.
	_flame_light = OmniLight3D.new()
	_flame_light.name = "FlameLight"
	_flame_light.top_level = true
	_flame_light.light_color = Color(1.0, 0.43, 0.085)
	_flame_light.light_energy = 0.0
	_flame_light.omni_range = 9.5
	_flame_light.omni_attenuation = 0.42
	_flame_light.shadow_enabled = true
	_flame_light.shadow_bias = 0.035
	_flame_light.shadow_normal_bias = 0.62
	add_child(_flame_light)

	_flame_fill_light = OmniLight3D.new()
	_flame_fill_light.name = "FlameFillLight"
	_flame_fill_light.top_level = true
	_flame_fill_light.light_color = Color(1.0, 0.25, 0.035)
	_flame_fill_light.light_energy = 0.0
	_flame_fill_light.omni_range = 17.5
	_flame_fill_light.omni_attenuation = 0.56
	_flame_fill_light.shadow_enabled = true
	_flame_fill_light.shadow_bias = 0.040
	_flame_fill_light.shadow_normal_bias = 0.70
	add_child(_flame_fill_light)

func _build_audio() -> void:
	_idle_audio = _audio("res://assets/sounds/engineidle.mp3", true, -13.0)
	_move_audio = _audio("res://assets/sounds/move.mp3", true, -22.0)
	_turret_audio = _audio("res://assets/sounds/turret.mp3", true, -18.0)
	_oneshot_audio = _audio("", false, -8.0)
	var weapon_name: String = String(_cfg()["weapon"])
	var sound_folder: String = "flamethrower" if weapon_name == "firebird" else weapon_name
	var shot_path := "res://assets/sounds/%s/shot.mp3" % sound_folder
	_shot_audio = _audio(shot_path, weapon_name == "firebird", -5.0)
	_death_audio = _audio("res://assets/sounds/explosion-tnk.mp3", false, -4.0)
	if _idle_audio.stream != null:
		_idle_audio.play()

func _audio(path: String, loop: bool, volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = volume_db
	p.max_distance = 65.0
	if path != "":
		var s = load(path)
		if s is AudioStreamMP3:
			s.loop = loop
		p.stream = s
	add_child(p)
	return p

func _play_death_sound_once() -> void:
	if _death_sound_played:
		return
	_death_sound_played = true
	var stream_value: Variant = load("res://assets/sounds/explosion-tnk.mp3")
	if not (stream_value is AudioStream):
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	# Spawn the one-shot outside the tank node. The wreck/camera code can freeze or
	# duplicate the tank immediately after death; a scene-level player survives that
	# transition and reliably finishes the supplied destruction sound.
	var player := AudioStreamPlayer3D.new()
	player.stream = stream_value as AudioStream
	player.volume_db = -1.5
	player.max_distance = 90.0
	player.unit_size = 7.0
	scene_root.add_child(player)
	player.global_position = global_position + Vector3.UP * 0.65
	player.finished.connect(player.queue_free)
	player.play()

func _build_camera() -> void:
	# Stable camera pivot: parented to the tank yaw only, not to RunningGear or
	# SprungBody. This prevents suspension/rocking from making the player seasick.
	_camera_yaw_root = Node3D.new()
	_camera_yaw_root.name = "CameraYawPivot"
	_camera_yaw_root.top_level = true
	add_child(_camera_yaw_root)
	_update_stable_camera_pivot()
	_camera_rig = Node3D.new()
	_camera_rig.name = "CameraRig"
	_camera_rig.position = Vector3(0,1.1,1.0)
	_camera_yaw_root.add_child(_camera_rig)
	_spring = SpringArm3D.new()
	_spring.spring_length = 9.0
	_spring.margin = 0.25
	_spring.rotation.x = deg_to_rad(-16)
	_camera_rig.add_child(_spring)
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.current = true
	_spring.add_child(_camera)

func _freeze_camera_for_death() -> void:
	# Freeze the player's view in world space at the exact frame of destruction.
	# The wreck and turret may continue flying, but the camera no longer follows them.
	if _camera == null or not is_instance_valid(_camera):
		return
	if _death_camera != null and is_instance_valid(_death_camera):
		return
	var frozen := Camera3D.new()
	frozen.name = "DeathCamera"
	add_child(frozen)
	frozen.top_level = true
	frozen.global_transform = _camera.global_transform
	frozen.fov = _camera.fov
	frozen.near = _camera.near
	frozen.far = _camera.far
	frozen.cull_mask = _camera.cull_mask
	_camera.current = false
	frozen.current = true
	_death_camera = frozen
	_death_camera_start_transform = frozen.global_transform

func prepare_respawn_camera(spawn_transform: Transform3D, respawn_delay: float) -> void:
	# v18.18.26 cinematic respawn. The spawn transform is server-reserved at death
	# time, so this target is guaranteed to be the transform used by revive_at().
	if not local_control:
		return
	_death_camera_respawn_delay = maxf(respawn_delay, 0.5)
	_death_camera_hold_seconds = minf(1.5, maxf(0.0, _death_camera_respawn_delay - 0.30))
	_death_camera_path_started_ms = Time.get_ticks_msec()
	_death_camera_path_ready = true
	_build_respawn_camera_target(spawn_transform)
	if _death_camera != null and is_instance_valid(_death_camera):
		_death_camera_start_transform = _death_camera.global_transform

func _build_respawn_camera_target(spawn_transform: Transform3D) -> void:
	_clear_respawn_camera_target()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var target_root := Node3D.new()
	target_root.name = "RespawnCameraTarget_%d" % player_id
	target_root.top_level = true
	scene_root.add_child(target_root)
	var forward := -spawn_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var spawn_yaw := atan2(-forward.x, -forward.z)
	target_root.global_position = spawn_transform.origin + Vector3.UP * (_camera_anchor_base.y + 0.30)
	target_root.global_basis = Basis(Vector3.UP, spawn_yaw)

	var rig := Node3D.new()
	rig.position = _camera_rig.position if _camera_rig != null and is_instance_valid(_camera_rig) else Vector3(0, 1.1, 1.0)
	target_root.add_child(rig)
	var target_spring := SpringArm3D.new()
	target_spring.spring_length = _spring.spring_length if _spring != null and is_instance_valid(_spring) else 9.0
	target_spring.margin = _spring.margin if _spring != null and is_instance_valid(_spring) else 0.25
	target_spring.rotation = _spring.rotation if _spring != null and is_instance_valid(_spring) else Vector3(deg_to_rad(-16.0), 0.0, 0.0)
	rig.add_child(target_spring)
	var target_camera := Camera3D.new()
	target_camera.fov = _camera.fov if _camera != null and is_instance_valid(_camera) else 68.0
	target_camera.current = false
	target_spring.add_child(target_camera)
	_respawn_camera_target_root = target_root
	_respawn_camera_target = target_camera

func _update_death_camera_path() -> void:
	if not local_control or not _death_camera_path_ready or combat_alive:
		return
	if _death_camera == null or not is_instance_valid(_death_camera):
		return
	if _respawn_camera_target == null or not is_instance_valid(_respawn_camera_target):
		return
	var elapsed := float(Time.get_ticks_msec() - _death_camera_path_started_ms) / 1000.0
	if elapsed <= _death_camera_hold_seconds:
		return
	var flight_time := maxf(_death_camera_respawn_delay - _death_camera_hold_seconds, 0.20)
	var t := clampf((elapsed - _death_camera_hold_seconds) / flight_time, 0.0, 1.0)
	var smooth_t := t * t * (3.0 - 2.0 * t)
	var target_transform := _respawn_camera_target.global_transform
	var start_pos := _death_camera_start_transform.origin
	var target_pos := target_transform.origin
	var distance := start_pos.distance_to(target_pos)
	var arc_height := clampf(distance * 0.20, 4.0, 13.0)
	var position := start_pos.lerp(target_pos, smooth_t)
	position.y += sin(smooth_t * PI) * arc_height
	var start_q := _death_camera_start_transform.basis.get_rotation_quaternion()
	var target_q := target_transform.basis.get_rotation_quaternion()
	var rotation_q := start_q.slerp(target_q, smooth_t)
	_death_camera.global_transform = Transform3D(Basis(rotation_q), position)
	var target_fov := _respawn_camera_target.fov
	_death_camera.fov = lerpf(_death_camera.fov, target_fov, clampf(smooth_t * 0.10 + 0.02, 0.0, 1.0))

func _reset_live_camera_interpolation() -> void:
	# The camera rig is top-level and used to sit at the death location. Resetting
	# interpolation prevents the renderer from blending that old transform into the
	# newly teleported spawn transform for one rendered frame.
	if _camera_yaw_root != null and is_instance_valid(_camera_yaw_root):
		_camera_yaw_root.reset_physics_interpolation()
	if _camera_rig != null and is_instance_valid(_camera_rig):
		_camera_rig.reset_physics_interpolation()
	if _spring != null and is_instance_valid(_spring):
		_spring.reset_physics_interpolation()
	if _camera != null and is_instance_valid(_camera):
		_camera.reset_physics_interpolation()

func _update_respawn_camera_handoff() -> void:
	if _respawn_camera_handoff_frames <= 0:
		return
	if not local_control or not combat_alive:
		_respawn_camera_handoff_frames = 0
		return
	# Keep the stable cinematic view authoritative while the hidden live camera
	# gets a few real physics updates from SpringArm3D.
	if _death_camera != null and is_instance_valid(_death_camera):
		_death_camera.current = true
	if _camera != null and is_instance_valid(_camera):
		_camera.current = false
	_respawn_camera_handoff_frames -= 1
	if _respawn_camera_handoff_frames <= 0:
		_reset_live_camera_interpolation()
		_release_death_camera()

func _clear_respawn_camera_target() -> void:
	if _respawn_camera_target_root != null and is_instance_valid(_respawn_camera_target_root):
		_respawn_camera_target_root.queue_free()
	_respawn_camera_target_root = null
	_respawn_camera_target = null

func _release_death_camera() -> void:
	# Make the destination camera current FIRST. This avoids a transient viewport
	# state with no explicit current camera between the two assignments.
	if _camera != null and is_instance_valid(_camera):
		_camera.current = true
	if _death_camera != null and is_instance_valid(_death_camera):
		_death_camera.current = false
		_death_camera.queue_free()
	_death_camera = null
	_death_camera_path_ready = false
	_death_camera_path_started_ms = 0
	_respawn_camera_handoff_frames = 0
	_clear_respawn_camera_target()

func apply_network_state(state: Dictionary) -> void:
	var was_alive: bool = combat_alive
	apply_combat_state(state)
	var p = state.get("p", null)
	if p is Array and p.size() >= 3:
		_target_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		if not _has_target or (not was_alive and combat_alive):
			global_position = _target_position
		_has_target = true
	_target_yaw = float(state.get("yaw", rotation.y))
	var r = state.get("rot", null)
	if r is Array and r.size() >= 4:
		_target_rotation = Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
	else:
		_target_rotation = Quaternion(Vector3.UP, _target_yaw)
	var lv = state.get("lin_vel", null)
	if lv is Array and lv.size() >= 3:
		_target_linear_velocity = Vector3(float(lv[0]), float(lv[1]), float(lv[2]))
	var av = state.get("ang_vel", null)
	if av is Array and av.size() >= 3:
		_target_angular_velocity = Vector3(float(av[0]), float(av[1]), float(av[2]))
	_target_turret = float(state.get("turret", turret_yaw))
	current_speed = float(state.get("speed", current_speed))
	_target_left_track = float(state.get("left_track", current_speed / MAX_SPEED))
	_target_right_track = float(state.get("right_track", current_speed / MAX_SPEED))
	firing = bool(state.get("firing", false))

func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if String(_cfg().get("weapon", "smoky")) != "firebird" and _reload_visual_ratio < 1.0:
		# Restore the pre-v18.9 visual reload clock: the bar fills independently and
		# smoothly across the configured weapon reload duration.
		var visual_reload_time: float = maxf(float(_weapon_stats().get("reload", 1.0)), 0.05)
		_reload_visual_ratio = minf(1.0, _reload_visual_ratio + delta / visual_reload_time)
	combat_nitro_time = maxf(0.0, combat_nitro_time - delta)
	combat_armor_time = maxf(0.0, combat_armor_time - delta)
	combat_damage_time = maxf(0.0, combat_damage_time - delta)
	if (local_control or ai_control) and combat_alive and match_controls_enabled:
		if ai_control:
			_read_ai_controls(delta)
		else:
			_read_local_controls(delta)
		_apply_suspension_and_track_forces(delta)
		_apply_climb_assist(delta)
		_apply_obstacle_grip(delta)
		_apply_stuck_recovery(delta)
		current_speed = linear_velocity.dot(-global_basis.z.normalized())
		_state_elapsed += delta
		if _state_elapsed >= 0.05:
			_state_elapsed = 0.0
			_send_state()
	elif not local_control and not ai_control:
		_remote_interpolation(delta)
	else:
		_drive_input = 0
		_turn_input = 0
		_turret_turn_velocity = 0.0
		firing = false

	_update_sprung_body_rock(delta)
	_update_visual_pose(delta)
	_update_visual_track_speeds(delta)
	_update_wheel_suspension(delta)
	_update_track_animation(delta)
	_turret_root.rotation.y = turret_yaw
	_update_overhead_status()
	_update_stable_camera_pivot()
	_update_death_camera_path()
	_update_respawn_camera_handoff()
	_update_audio_and_fx()

func _read_local_controls(delta: float) -> void:
	# Once the chassis is lying on its side/roof, driving and weapons are disabled.
	# DELETE remains available as the only escape, matching the bot rule below.
	if _is_overturned():
		_drive_input = 0
		_turn_input = 0
		_turret_turn_velocity = 0.0
		firing = false
		_left_track_speed = move_toward(_left_track_speed, 0.0, delta * 3.0)
		_right_track_speed = move_toward(_right_track_speed, 0.0, delta * 3.0)
		var overturned_self_destruct: bool = Input.is_key_pressed(KEY_DELETE)
		if overturned_self_destruct and not _self_destruct_down and network != null:
			network.request_self_destruct()
		_self_destruct_down = overturned_self_destruct
		_update_combat_hud()
		return

	_drive_input = 0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		_drive_input += 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		_drive_input -= 1
	_turn_input = 0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		_turn_input += 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		_turn_input -= 1

	var cfg: Dictionary = _cfg()
	var steering_scale: float = TURN_INPUT_SCALE
	if _drive_input == 0:
		steering_scale = float(cfg.get("pivot_track_scale", 0.70))
	var turn_command: float = float(_turn_input) * steering_scale
	var left_target: float = clampf(float(_drive_input) - turn_command, -1.0, 1.0)
	var right_target: float = clampf(float(_drive_input) + turn_command, -1.0, 1.0)
	_left_track_speed = _approach_track_speed(_left_track_speed, left_target, _drive_input, delta)
	_right_track_speed = _approach_track_speed(_right_track_speed, right_target, _drive_input, delta)
	if _turn_input != 0:
		# Moving steering is deliberately more authoritative than in v18.1, while
		# standstill pivot has been reduced in the per-hull config below. This shifts
		# some of the old "spin like a top" authority into useful cornering speed.
		var steering_response: float = clampf(delta * 5.8, 0.0, 1.0)
		_left_track_speed = lerpf(_left_track_speed, left_target, steering_response)
		_right_track_speed = lerpf(_right_track_speed, right_target, steering_response)
	else:
		_damp_track_differential(delta)

	var turret_input: int = 0
	if Input.is_key_pressed(KEY_Z):
		turret_input += 1
	if Input.is_key_pressed(KEY_X):
		turret_input -= 1
	if turret_input != 0:
		_turret_centering = false
		var turret_direction: float = float(turret_input)
		# Direction reversal behaves like an immediate stop followed by a new ramp.
		# Releasing Z/X also stops instantly; only spin-up is softened for comfort.
		if absf(_turret_turn_velocity) > 0.001 and signf(_turret_turn_velocity) != signf(turret_direction):
			_turret_turn_velocity = 0.0
		var turret_target_speed: float = turret_direction * TURRET_MANUAL_MAX_SPEED
		_turret_turn_velocity = move_toward(_turret_turn_velocity, turret_target_speed, TURRET_MANUAL_ACCEL * delta)
		turret_yaw += _turret_turn_velocity * delta
	else:
		_turret_turn_velocity = 0.0

	# C starts a smooth auto-return instead of snapping the turret to zero.
	# Manual Z/X input immediately cancels the return.
	var center_pressed: bool = Input.is_key_pressed(KEY_C)
	if center_pressed and not _center_turret_down:
		_turret_centering = true
	_center_turret_down = center_pressed
	if _turret_centering and turret_input == 0:
		var center_delta: float = angle_difference(turret_yaw, 0.0)
		var center_step: float = TURRET_CENTER_SPEED * delta
		if absf(center_delta) <= center_step:
			turret_yaw = 0.0
			_target_turret = 0.0
			_turret_centering = false
		else:
			turret_yaw += clampf(center_delta, -center_step, center_step)

	# DELETE is a reliable server-authoritative self-destruct request. It is edge
	# triggered so holding the key cannot queue multiple requests.
	var self_destruct_pressed: bool = Input.is_key_pressed(KEY_DELETE)
	if self_destruct_pressed and not _self_destruct_down and network != null:
		network.request_self_destruct()
	_self_destruct_down = self_destruct_pressed

	_handle_fire()
	if _spring != null:
		if Input.is_key_pressed(KEY_PAGEUP):
			_spring.rotation.x = clampf(_spring.rotation.x - delta * 0.6, deg_to_rad(CAMERA_MIN_X), deg_to_rad(CAMERA_MAX_X))
		if Input.is_key_pressed(KEY_PAGEDOWN):
			_spring.rotation.x = clampf(_spring.rotation.x + delta * 0.6, deg_to_rad(CAMERA_MIN_X), deg_to_rad(CAMERA_MAX_X))

func _body_up_dot() -> float:
	var up_axis: Vector3 = global_basis.y
	if up_axis.length_squared() < 0.0001:
		return 1.0
	return up_axis.normalized().dot(Vector3.UP)

func _is_overturned() -> bool:
	# 0.18 ~= 80 degrees of tilt. Normal ramps and steep climb assists are far above
	# this threshold, while a tank lying on its side or roof is decisively below it.
	return _body_up_dot() < OVERTURNED_UP_DOT

func _target_hit_center_world(target: TankActor) -> Vector3:
	var target_size: Vector3 = target._cfg().get("size", Vector3(3.0, 1.4, 4.8))
	var target_up: Vector3 = target.global_basis.y
	if target_up.length_squared() < 0.0001:
		target_up = Vector3.UP
	else:
		target_up = target_up.normalized()
	# The physical hull collision is offset along LOCAL +Y. Using target.local up
	# keeps aim/hit sampling attached to the armor even when the chassis is inverted.
	return target.global_position + target_up * target_size.y * 0.62

func _target_hit_samples_world(target: TankActor) -> Array[Vector3]:
	var target_size: Vector3 = target._cfg().get("size", Vector3(3.0, 1.4, 4.8))
	var up: Vector3 = target.global_basis.y.normalized()
	var right: Vector3 = target.global_basis.x.normalized()
	var forward: Vector3 = -target.global_basis.z.normalized()
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var center: Vector3 = _target_hit_center_world(target)
	return [
		center,
		center + up * target_size.y * 0.30,
		center - up * target_size.y * 0.22,
		center + right * target_size.x * 0.22,
		center - right * target_size.x * 0.22,
		center + forward * target_size.z * 0.14,
		center - forward * target_size.z * 0.14,
	]

func _ai_target() -> TankActor:
	if _ai_target_id > 0:
		for node in get_tree().get_nodes_in_group("tanki_tank"):
			if node is TankActor and (node as TankActor).player_id == _ai_target_id and (node as TankActor).combat_alive:
				return node as TankActor
	_ai_target_id = -1
	return null

func _ai_choose_target() -> TankActor:
	var best: TankActor = null
	var best_score: float = INF
	for node in get_tree().get_nodes_in_group("tanki_tank"):
		if not (node is TankActor):
			continue
		var candidate := node as TankActor
		if candidate == self or not candidate.combat_alive:
			continue
		var dist: float = global_position.distance_to(candidate.global_position)
		# A little randomness stops a pack of bots from switching to exactly the same
		# target every think tick while still strongly preferring nearby enemies.
		var score: float = dist + randf_range(0.0, 7.0)
		if score < best_score:
			best_score = score
			best = candidate
	if best != null:
		_ai_target_id = best.player_id
	return best

func _ai_obstacle_clearance(direction: Vector3, max_distance: float = 7.5) -> float:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.001:
		return max_distance
	planar = planar.normalized()
	var side := Vector3(-planar.z, 0.0, planar.x)
	var hull_size: Vector3 = _cfg().get("size", Vector3(3.2, 1.5, 5.2))
	var lane_offset: float = maxf(0.45, hull_size.x * 0.27)
	var probe_height: float = maxf(0.88, hull_size.y * 0.68)
	var space := get_world_3d().direct_space_state
	var nearest: float = max_distance
	for lane_factor in [-0.72, 0.0, 0.72]:
		var origin := global_position + Vector3.UP * probe_height + side * lane_offset * float(lane_factor)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + planar * max_distance)
		query.exclude = [get_rid()]
		query.collision_mask = TERRAIN_PHYSICS_MASK
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		if _tank_from_collider(hit.get("collider", null)) != null:
			continue
		# v19.1.1 slope-safe obstacle sensing: a horizontal probe naturally intersects
		# the rising face of a ramp. Upward-facing, driveable geometry is terrain under
		# the tracks, not a wall to reverse from. Real walls have a much smaller Y normal.
		var normal_value: Variant = hit.get("normal", Vector3.ZERO)
		if normal_value is Vector3:
			var hit_normal: Vector3 = (normal_value as Vector3).normalized()
			if hit_normal.dot(Vector3.UP) >= 0.56:
				continue
		var hit_pos_value: Variant = hit.get("position", origin + planar * max_distance)
		if hit_pos_value is Vector3:
			nearest = minf(nearest, origin.distance_to(hit_pos_value as Vector3))
	return nearest

func _ai_has_forward_obstacle() -> bool:
	return _ai_obstacle_clearance(-global_basis.z, 6.2) < 5.35

func _ai_choose_avoid_sign() -> int:
	var forward := -global_basis.z.normalized()
	var left_dir := forward.rotated(Vector3.UP, deg_to_rad(38.0))
	var right_dir := forward.rotated(Vector3.UP, deg_to_rad(-38.0))
	var left_clear: float = _ai_obstacle_clearance(left_dir, 9.0)
	var right_clear: float = _ai_obstacle_clearance(right_dir, 9.0)
	if absf(left_clear - right_clear) < 0.65:
		return -1 if randf() < 0.5 else 1
	# Tank steering convention: positive _turn_input turns toward local left.
	return 1 if left_clear > right_clear else -1

func _ai_line_of_sight(target: TankActor) -> bool:
	if _muzzle == null or target == null:
		return false
	var samples: Array[Vector3] = _target_hit_samples_world(target)
	var space := get_world_3d().direct_space_state
	for aim_point in samples:
		var delta_to: Vector3 = aim_point - _muzzle.global_position
		if delta_to.length_squared() < 0.01:
			return true
		var query := PhysicsRayQueryParameters3D.create(_muzzle.global_position, aim_point + delta_to.normalized() * 0.22)
		query.exclude = [get_rid()]
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_tank: TankActor = _tank_from_collider(hit.get("collider", null))
		if hit_tank == target:
			return true
	return false

func _ai_supply_node() -> Node3D:
	if _ai_supply_target_id < 0:
		return null
	for node in get_tree().get_nodes_in_group("tanki_supply"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if int((node as Node).get("supply_id")) != _ai_supply_target_id:
			continue
		if (node as Node).has_method("ai_is_available") and not bool((node as Node).call("ai_is_available")):
			break
		return node as Node3D
	_ai_supply_target_id = -1
	return null

func _ai_choose_supply() -> Node3D:
	var hp_ratio: float = combat_hp / maxf(combat_max_hp, 1.0)
	var best: Node3D = null
	var best_score: float = INF
	for node in get_tree().get_nodes_in_group("tanki_supply"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var supply := node as Node
		if supply.has_method("ai_is_available") and not bool(supply.call("ai_is_available")):
			continue
		var kind: String = String(supply.call("ai_kind")) if supply.has_method("ai_kind") else String(supply.get("supply_kind"))
		# Bots have no account economy. Never route them toward gold or crystals.
		if kind == "gold" or kind == "crystal":
			continue
		var nav_value: Variant = supply.call("ai_target_position") if supply.has_method("ai_target_position") else (node as Node3D).global_position
		if not (nav_value is Vector3):
			continue
		var nav_pos: Vector3 = nav_value as Vector3
		var planar_distance: float = Vector2(global_position.x - nav_pos.x, global_position.z - nav_pos.z).length()
		var score: float = planar_distance
		match kind:
			"medkit":
				if hp_ratio >= 0.92:
					continue
				score -= (1.0 - hp_ratio) * 72.0
				if hp_ratio < 0.48:
					score -= 22.0
			"armor":
				if combat_armor_time > 5.0:
					continue
				score += 5.0
			"damage":
				if combat_damage_time > 5.0:
					continue
				score += 2.0
			"nitro":
				if combat_nitro_time > 5.0:
					continue
				score += 7.0
			_:
				continue
		var interest_limit: float = 92.0 if kind == "medkit" and hp_ratio < 0.62 else 58.0
		if planar_distance > interest_limit:
			continue
		if score < best_score:
			best_score = score
			best = node as Node3D
	if best != null:
		_ai_supply_target_id = int((best as Node).get("supply_id"))
	return best

func _ai_supply_navigation_position(supply: Node3D) -> Vector3:
	if supply == null:
		return global_position
	var value: Variant = (supply as Node).call("ai_target_position") if (supply as Node).has_method("ai_target_position") else supply.global_position
	if value is Vector3:
		return value
	return supply.global_position

func _ai_apply_tracks(delta: float) -> void:
	var cfg: Dictionary = _cfg()
	var steering_scale: float = TURN_INPUT_SCALE
	if _drive_input == 0:
		steering_scale = float(cfg.get("pivot_track_scale", 0.70))
	var turn_command: float = float(_turn_input) * steering_scale
	var left_target: float = clampf(float(_drive_input) - turn_command, -1.0, 1.0)
	var right_target: float = clampf(float(_drive_input) + turn_command, -1.0, 1.0)
	_left_track_speed = _approach_track_speed(_left_track_speed, left_target, _drive_input, delta)
	_right_track_speed = _approach_track_speed(_right_track_speed, right_target, _drive_input, delta)
	if _turn_input != 0:
		var steering_response: float = clampf(delta * 5.8, 0.0, 1.0)
		_left_track_speed = lerpf(_left_track_speed, left_target, steering_response)
		_right_track_speed = lerpf(_right_track_speed, right_target, steering_response)
	else:
		_damp_track_differential(delta)

func _ai_on_traversable_slope() -> bool:
	if _ground_contacts <= 0 or _support_normal.length_squared() < 0.01:
		return false
	var upness: float = _support_normal.normalized().dot(Vector3.UP)
	# Roughly 0..55 degree upward-facing support. Near-flat ground uses normal timing.
	return upness >= 0.57 and upness < 0.985

func _ai_apply_stuck_brain(delta: float) -> bool:
	_ai_repath_cooldown = maxf(0.0, _ai_repath_cooldown - delta)
	if _ai_recovery_time > 0.0:
		_ai_recovery_time = maxf(0.0, _ai_recovery_time - delta)
		# First reverse away from a true collision, then leave on another heading.
		if _ai_recovery_time > 0.58:
			_drive_input = -1
			_turn_input = _ai_recovery_turn
		else:
			_drive_input = 1
			_turn_input = -_ai_recovery_turn
		return true

	if absf(float(_drive_input)) < 0.5:
		_ai_progress_anchor = global_position
		_ai_progress_elapsed = 0.0
		return false

	_ai_progress_elapsed += delta
	var movement: Vector3 = global_position - _ai_progress_anchor
	var planar_progress: float = Vector2(movement.x, movement.z).length()
	var effective_progress: float = sqrt(planar_progress * planar_progress + movement.y * movement.y * 0.55)
	var on_slope: bool = _ai_on_traversable_slope()
	var progress_goal: float = 0.72 if on_slope else 1.25
	if effective_progress >= progress_goal:
		_ai_progress_anchor = global_position
		_ai_progress_elapsed = 0.0
		return false

	# Climbing is naturally slower. v19.1.0 treated normal uphill progress as being
	# stuck after only 1.55 s, which caused reverse/forward oscillation on ramps.
	var stuck_timeout: float = 4.0 if on_slope else 1.55
	if _ai_progress_elapsed < stuck_timeout or _ai_repath_cooldown > 0.0:
		return false
	var moving_speed_limit: float = 0.70 if on_slope else 2.15
	if linear_velocity.length() > moving_speed_limit:
		_ai_progress_anchor = global_position
		_ai_progress_elapsed = 0.0
		return false

	# On a traversable ramp, only run the reverse manoeuvre when there is also a
	# genuine steep/vertical obstacle close ahead. Otherwise keep climbing.
	if on_slope and _ai_obstacle_clearance(-global_basis.z, 3.2) > 1.45:
		_ai_progress_anchor = global_position
		_ai_progress_elapsed = 0.0
		return false

	_ai_recovery_turn = _ai_choose_avoid_sign()
	_ai_recovery_time = randf_range(1.25, 1.75)
	_ai_repath_cooldown = 2.2
	_ai_progress_elapsed = 0.0
	_ai_progress_anchor = global_position
	_ai_target_id = -1
	_ai_supply_target_id = -1
	_ai_retarget_time = 0.0
	_ai_supply_retarget_time = 0.0
	_drive_input = -1
	_turn_input = _ai_recovery_turn
	return true

func _read_ai_controls(delta: float) -> void:
	# A tank on its side/roof cannot meaningfully aim or drive. Do not let an inverted
	# Firebird continue burning targets through the floor: stop all combat immediately,
	# then self-destruct only if the bad orientation persists (brief rolls are ignored).
	if _is_overturned():
		_ai_overturned_time += delta
		_drive_input = 0
		_turn_input = 0
		_turret_turn_velocity = 0.0
		firing = false
		_ai_apply_tracks(delta)
		if _ai_overturned_time >= BOT_OVERTURN_SELF_DESTRUCT_SECONDS and not _ai_self_destruct_requested and network != null:
			_ai_self_destruct_requested = true
			network.request_bot_self_destruct(player_id)
		return
	_ai_overturned_time = 0.0

	_ai_retarget_time -= delta
	_ai_supply_retarget_time -= delta
	_ai_avoid_time = maxf(0.0, _ai_avoid_time - delta)
	_ai_wander_time = maxf(0.0, _ai_wander_time - delta)
	var target := _ai_target()
	if target == null or _ai_retarget_time <= 0.0:
		target = _ai_choose_target()
		_ai_retarget_time = randf_range(0.28, 0.62)
	var supply := _ai_supply_node()
	if supply == null or _ai_supply_retarget_time <= 0.0:
		supply = _ai_choose_supply()
		_ai_supply_retarget_time = randf_range(0.55, 1.05)

	_drive_input = 0
	_turn_input = 0
	var aim_ready := false
	var target_distance := INF
	var desired_turret: float = turret_yaw
	var enemy_visible: bool = false
	if target != null:
		var aim_point: Vector3 = _target_hit_center_world(target)
		var delta_world := aim_point - global_position
		target_distance = delta_world.length()
		var local_delta := global_basis.inverse() * delta_world
		desired_turret = atan2(-local_delta.x, -local_delta.z)
		var turret_error := angle_difference(turret_yaw, desired_turret)
		var turret_step := TURRET_MANUAL_MAX_SPEED * 0.82 * delta
		turret_yaw += clampf(turret_error, -turret_step, turret_step)
		_target_turret = turret_yaw
		enemy_visible = _ai_line_of_sight(target)

	# Decide where to DRIVE. A critical medkit wins over pursuit; ordinary buffs are
	# opportunistic and are ignored while an enemy is already on top of the bot.
	var nav_position: Vector3 = target.global_position if target != null else global_position
	var using_supply := false
	if supply != null:
		var supply_pos := _ai_supply_navigation_position(supply)
		var supply_distance := Vector2(global_position.x - supply_pos.x, global_position.z - supply_pos.z).length()
		var supply_kind: String = String((supply as Node).call("ai_kind")) if (supply as Node).has_method("ai_kind") else ""
		var critical_medkit: bool = supply_kind == "medkit" and combat_hp / maxf(combat_max_hp, 1.0) < 0.68
		if critical_medkit or target == null or (target_distance > 13.0 and supply_distance < 46.0):
			nav_position = supply_pos
			using_supply = true

	var nav_delta_world: Vector3 = nav_position - global_position
	var nav_local := global_basis.inverse() * nav_delta_world
	var nav_planar := Vector2(nav_local.x, nav_local.z)
	var nav_distance: float = nav_planar.length()
	if nav_distance > 0.7:
		var body_angle := absf(atan2(nav_planar.x, -nav_planar.y)) if nav_planar.length_squared() > 0.001 else 0.0
		if absf(nav_local.x) > maxf(0.58, absf(nav_local.z) * 0.085):
			_turn_input = 1 if nav_local.x < 0.0 else -1
		if body_angle > deg_to_rad(76.0):
			_drive_input = 0
		elif using_supply:
			_drive_input = 1 if nav_distance > 2.0 else 0
		elif target_distance > 10.5:
			_drive_input = 1
		elif target_distance < 4.8:
			_drive_input = -1

	var ai_on_slope: bool = _ai_on_traversable_slope()
	# v19.1.2: once the tracks are actually supported by a driveable ramp, obstacle
	# avoidance must not fight the climb. A ramp edge can present a near-vertical
	# triangle to a forward ray for a frame or two; the old reverse manoeuvre then
	# made bots oscillate backwards/forwards on perfectly climbable slopes.
	if ai_on_slope and _ai_avoid_time > 0.0:
		_ai_avoid_time = 0.0
	if _ai_has_forward_obstacle() and _drive_input > 0 and not ai_on_slope:
		if _ai_avoid_time <= 0.0:
			_ai_avoid_time = randf_range(0.95, 1.55)
			_ai_avoid_sign = _ai_choose_avoid_sign()
	if _ai_avoid_time > 0.0:
		_turn_input = _ai_avoid_sign
		# Back off briefly if the obstacle is very close, then arc around it.
		var forward_clear: float = _ai_obstacle_clearance(-global_basis.z, 5.0)
		_drive_input = -1 if forward_clear < 2.15 and _ai_avoid_time > 0.72 else 1

	_ai_apply_stuck_brain(delta)

	if target != null:
		var weapon_stats: Dictionary = _weapon_stats()
		var max_range: float = _effective_weapon_range(weapon_stats)
		aim_ready = absf(angle_difference(turret_yaw, desired_turret)) < deg_to_rad(8.5) and target_distance <= max_range * 0.995 and enemy_visible

	_ai_apply_tracks(delta)
	var weapon: String = String(_cfg().get("weapon", "smoky"))
	if weapon == "firebird":
		firing = aim_ready and combat_fuel > 0.25
	else:
		firing = false
		if aim_ready and _fire_cooldown <= 0.0:
			_fire_cooldown = maxf(float(_weapon_stats().get("reload", 1.0)), 0.05) * randf_range(0.96, 1.10)
			_reload_visual_ratio = 0.0
			_perform_discrete_shot()

func assume_ai_authority(state: Dictionary, spawn_transform: Transform3D, combat: Dictionary) -> void:
	ai_control = true
	local_control = false
	freeze = false
	match_controls_enabled = true
	var p = state.get("p", null)
	if p is Array and (p as Array).size() >= 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	else:
		global_transform = spawn_transform
	var r = state.get("rot", null)
	if r is Array and (r as Array).size() >= 4:
		global_basis = Basis(Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized())
	var lv = state.get("lin_vel", null)
	if lv is Array and (lv as Array).size() >= 3:
		linear_velocity = Vector3(float(lv[0]), float(lv[1]), float(lv[2]))
	var av = state.get("ang_vel", null)
	if av is Array and (av as Array).size() >= 3:
		angular_velocity = Vector3(float(av[0]), float(av[1]), float(av[2]))
	turret_yaw = float(state.get("turret", 0.0))
	_target_turret = turret_yaw
	apply_combat_state(combat)
	reset_physics_interpolation()
	sleeping = false
	# v19.0.2: publish the initial authoritative bot transform immediately.
	# Waiting for the normal 50 ms state timer races the 20 Hz server snapshot;
	# an immediate packet also lets remote clients see the bot on the next snapshot.
	_state_elapsed = 0.0
	_ai_progress_anchor = global_position
	_ai_progress_elapsed = 0.0
	_ai_recovery_time = 0.0
	_ai_overturned_time = 0.0
	_ai_self_destruct_requested = false
	_send_state()

func _approach_track_speed(current: float, target: float, move_input: int, delta: float) -> float:
	if is_equal_approx(target, current):
		return target
	var rate := DRIVE_ACCEL
	if move_input == 0 and absf(target) < 0.001:
		rate = COAST_DECEL
	elif absf(target) < absf(current):
		rate = COAST_DECEL
	if target * current < -0.01:
		rate = SERVICE_BRAKE
	return move_toward(current, target, rate * delta)

func _damp_track_differential(delta: float) -> void:
	var average := (_left_track_speed + _right_track_speed) * 0.5
	var differential := (_right_track_speed - _left_track_speed) * 0.5
	differential = move_toward(differential, 0.0, 1.82 * delta)
	_left_track_speed = clampf(average - differential, -1.0, 1.0)
	_right_track_speed = clampf(average + differential, -1.0, 1.0)

func _apply_suspension_and_track_forces(_delta: float) -> void:
	if _suspension_points.is_empty():
		return
	var cfg: Dictionary = _cfg()
	var spring_k: float = float(cfg["suspension_k"])
	var spring_damping: float = float(cfg["suspension_damping"])
	var drive_gain: float = float(cfg["drive_gain"])
	var lateral_gain: float = float(cfg["lateral_gain"])
	var suspension_force_cap: float = float(cfg.get("suspension_force_cap", 1.9))
	var lookahead: float = float(cfg.get("suspension_lookahead", 0.58))
	var suspension_travel: float = float(cfg["suspension_travel"])
	var step_height: float = float(cfg["step_height"])
	var up: Vector3 = global_basis.y.normalized()
	var down: Vector3 = -up
	var forward_raw: Vector3 = -global_basis.z.normalized()
	var side_raw: Vector3 = global_basis.x.normalized()
	var average_track_command: float = (_left_track_speed + _right_track_speed) * 0.5
	var direction_sign: float = signf(average_track_command)
	var space := get_world_3d().direct_space_state
	var contacts: Array[Dictionary] = []
	var average_normal: Vector3 = Vector3.ZERO

	# Keep the normal road-wheel ray, but let the leading half of the track sample
	# a little ahead. A low step then compresses the suspension before the rigid
	# collision prism reaches its vertical face, so the chassis rides onto it.
	for point in _suspension_points:
		var anchor_local: Vector3 = point["anchor"]
		var anchor_world: Vector3 = global_transform * anchor_local
		var max_len: float = float(point["max_len"])
		var selected_hit: Dictionary = {}
		var selected_distance: float = INF
		var preview_contact: bool = false

		var query := PhysicsRayQueryParameters3D.create(anchor_world, anchor_world + down * (max_len + 0.20))
		query.exclude = [get_rid()]
		query.collision_mask = TERRAIN_PHYSICS_MASK
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			selected_hit = hit
			var direct_pos: Vector3 = hit["position"]
			selected_distance = anchor_world.distance_to(direct_pos)

		if absf(direction_sign) > 0.01:
			var leading_amount: float = -anchor_local.z * direction_sign
			if leading_amount > -0.05:
				var preview_anchor: Vector3 = anchor_world + forward_raw * direction_sign * lookahead
				var preview_query := PhysicsRayQueryParameters3D.create(preview_anchor, preview_anchor + down * (max_len + step_height + 0.20))
				preview_query.exclude = [get_rid()]
				preview_query.collision_mask = TERRAIN_PHYSICS_MASK
				var preview_hit := space.intersect_ray(preview_query)
				if not preview_hit.is_empty():
					var preview_pos: Vector3 = preview_hit["position"]
					var preview_normal: Vector3 = preview_hit["normal"]
					preview_normal = preview_normal.normalized()
					var preview_distance: float = preview_anchor.distance_to(preview_pos)
					var rise_relative: float = (preview_pos - global_position).dot(up)
					if preview_normal.dot(up) > 0.42 and rise_relative <= step_height + 0.12 and preview_distance < selected_distance - 0.025:
						selected_hit = preview_hit
						selected_distance = preview_distance
						preview_contact = true

		if selected_hit.is_empty():
			continue
		var hit_pos: Vector3 = selected_hit["position"]
		var hit_normal: Vector3 = selected_hit["normal"]
		hit_normal = hit_normal.normalized()
		var compression: float = maxf(0.0, max_len - selected_distance)
		compression = minf(compression, suspension_travel + float(point["static_sag"]) + 0.045)
		if preview_contact:
			compression *= 0.72
		if compression <= 0.0:
			continue
		contacts.append({
			"position": hit_pos,
			"normal": hit_normal,
			"compression": compression,
			"side": float(point["side"]),
			"preview": preview_contact
		})
		average_normal += hit_normal

	_ground_contacts = contacts.size()
	if _ground_contacts <= 0:
		_rough_contact_factor = move_toward(_rough_contact_factor, 0.0, 0.18)
		return

	# Detect uneven/one-track support. A tank can be almost level while one caterpillar
	# is sitting on a curb, so average body tilt alone is not enough to activate grip.
	var left_count: int = 0
	var right_count: int = 0
	var left_compression: float = 0.0
	var right_compression: float = 0.0
	var min_compression: float = INF
	var max_compression: float = 0.0
	var preview_count: int = 0
	for rough_contact in contacts:
		var rough_compression: float = float(rough_contact["compression"])
		min_compression = minf(min_compression, rough_compression)
		max_compression = maxf(max_compression, rough_compression)
		if bool(rough_contact["preview"]):
			preview_count += 1
		if float(rough_contact["side"]) < 0.0:
			left_count += 1
			left_compression += rough_compression
		else:
			right_count += 1
			right_compression += rough_compression
	var left_average: float = left_compression / float(maxi(left_count, 1))
	var right_average: float = right_compression / float(maxi(right_count, 1))
	var compression_spread: float = (max_compression - min_compression) / maxf(suspension_travel, 0.01)
	var side_spread: float = absf(left_average - right_average) / maxf(suspension_travel, 0.01)
	var one_track_weight: float = 1.0 if left_count == 0 or right_count == 0 else 0.0
	var preview_weight: float = float(preview_count) / float(maxi(contacts.size(), 1))
	var rough_target: float = clampf(compression_spread * 0.58 + side_spread * 0.72 + preview_weight * 0.60 + one_track_weight * 0.82, 0.0, 1.0)
	_rough_contact_factor = lerpf(_rough_contact_factor, rough_target, 0.42)

	average_normal = average_normal.normalized() if average_normal.length_squared() > 0.001 else Vector3.UP
	_support_normal = average_normal
	var contact_count: int = maxi(1, contacts.size())
	var static_share: float = mass * WORLD_GRAVITY / float(contact_count)
	var max_spring_per_contact: float = static_share * suspension_force_cap

	for contact in contacts:
		var hit_pos: Vector3 = contact["position"]
		var offset: Vector3 = hit_pos - global_position
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(offset)
		var compression: float = float(contact["compression"])
		var suspension_speed: float = point_velocity.dot(up)
		var damping_gain: float = spring_damping
		if compression > suspension_travel * 0.72:
			damping_gain *= 1.30
		if bool(contact["preview"]):
			damping_gain *= 1.15
		var spring_force: float = compression * spring_k - suspension_speed * damping_gain
		spring_force = clampf(spring_force, 0.0, max_spring_per_contact)
		var force_axis: Vector3 = up.lerp(contact["normal"], 0.18).normalized()
		apply_force(force_axis * spring_force, offset)

		var side: Vector3 = side_raw.slide(average_normal)
		if side.length_squared() > 0.001:
			side = side.normalized()
			var lateral_speed: float = point_velocity.dot(side)
			var grip_force: float = -lateral_speed * mass * lateral_gain / float(contact_count)
			apply_force(side * grip_force, offset)

	var forward: Vector3 = forward_raw.slide(average_normal)
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
		var nitro_multiplier: float = combat_nitro_multiplier if combat_nitro_time > 0.05 else 1.0
		var effective_max_speed: float = MAX_SPEED * nitro_multiplier
		var target_speed: float = average_track_command * effective_max_speed
		var forward_speed: float = linear_velocity.dot(forward)
		var drive_force_limit: float = float(cfg.get("drive_force_limit", 12.0))
		if nitro_multiplier > 1.0:
			drive_force_limit *= 1.72
		var drive_force: float = (target_speed - forward_speed) * mass * drive_gain

		# High breakaway traction at low speed, fading out before cruising speed.
		var speed_ratio: float = clampf(absf(forward_speed) / maxf(effective_max_speed, 0.1), 0.0, 1.0)
		var launch_boost: float = float(cfg.get("launch_traction_boost", 1.40))
		var low_speed_weight: float = 1.0 - smoothstep(0.08, 0.58, speed_ratio)
		drive_force *= lerpf(1.0, launch_boost, low_speed_weight)

		# Extra bite only while the requested travel direction points uphill.
		var travel_sign: float = signf(target_speed)
		var uphill_amount: float = maxf(forward.dot(Vector3.UP) * travel_sign, 0.0)
		drive_force *= 1.0 + uphill_amount * 0.70

		drive_force = clampf(drive_force, -mass * drive_force_limit, mass * drive_force_limit)
		apply_central_force(forward * drive_force)

	var differential: float = (_right_track_speed - _left_track_speed) * 0.5
	if absf(differential) > 0.001:
		var average_track: float = absf(average_track_command)
		var turn_gain: float = float(cfg.get("moving_turn_torque_gain", 0.19))
		if average_track < 0.08:
			turn_gain = float(cfg.get("pivot_torque_gain", 0.58))
		else:
			# Keep useful yaw authority as speed rises instead of making a fast tank feel
			# unwilling to turn. The track differential still limits the final rate.
			turn_gain *= lerpf(1.04, 1.16, clampf(average_track, 0.0, 1.0))
		var hull_size: Vector3 = cfg["size"]
		var max_rate: float = float(cfg.get("pivot_max_rate", 1.15))
		if average_track >= 0.08:
			max_rate = float(cfg.get("moving_max_rate", max_rate))
		var yaw_rate: float = angular_velocity.dot(average_normal)
		if absf(yaw_rate) < max_rate or signf(yaw_rate) != signf(differential):
			var turn_torque: float = differential * mass * WORLD_GRAVITY * hull_size.x * turn_gain * 1.16
			apply_torque(average_normal * turn_torque)

func _apply_climb_assist(delta: float) -> void:
	# Convert a reachable vertical step into a *virtual rounded ramp*.  We sample the
	# walkable top ahead of five lanes across the tracks and begin lifting before the
	# collision nose reaches the hard map edge.  Walls remain walls: only upward-facing
	# surfaces within this hull's configured step_height are accepted.
	_terrain_pitch_target = 0.0
	_virtual_ramp_strength = move_toward(_virtual_ramp_strength, 0.0, delta * 4.0)
	var average_track: float = (_left_track_speed + _right_track_speed) * 0.5
	if _ground_contacts <= 0 or absf(average_track) < 0.08:
		return
	var local_up: Vector3 = global_basis.y.normalized()
	if local_up.dot(Vector3.UP) < 0.42:
		return

	var cfg: Dictionary = _cfg()
	var s: Vector3 = cfg["size"]
	var step_height: float = float(cfg["step_height"])
	var direction_sign: float = signf(average_track)
	var travel: Vector3 = -global_basis.z.normalized() * direction_sign
	var side: Vector3 = global_basis.x.normalized()
	var space := get_world_3d().direct_space_state

	# Current support height gives us the zero of the virtual profile.
	var base_from: Vector3 = global_position + local_up * (s.y * 0.70 + 0.65)
	var base_to: Vector3 = global_position - local_up * (s.y * 0.55 + 0.65)
	var base_query := PhysicsRayQueryParameters3D.create(base_from, base_to)
	base_query.exclude = [get_rid()]
	base_query.collision_mask = TERRAIN_PHYSICS_MASK
	var base_hit := space.intersect_ray(base_query)
	if base_hit.is_empty():
		return
	var base_pos: Vector3 = base_hit["position"]

	var reach: float = float(cfg["step_probe"]) + 0.92
	var front_offset: float = s.z * 0.355
	var probe_distances: Array[float] = [0.18, reach * 0.46, reach * 0.82]
	var lanes: Array[float] = [-0.31, -0.155, 0.0, 0.155, 0.31]
	var best_rise: float = 0.0
	var best_distance: float = reach
	var best_lane: float = 0.0

	for distance_value in probe_distances:
		for lane_value in lanes:
			var sample_center: Vector3 = global_position + travel * (front_offset + distance_value) + side * (s.x * lane_value)
			var ray_from: Vector3 = sample_center + local_up * (step_height + 0.48)
			var ray_to: Vector3 = sample_center - local_up * 0.30
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
			query.exclude = [get_rid()]
			query.collision_mask = TERRAIN_PHYSICS_MASK
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var hit_normal: Vector3 = hit["normal"]
			hit_normal = hit_normal.normalized()
			if hit_normal.dot(local_up) < 0.55:
				continue
			var hit_pos: Vector3 = hit["position"]
			var rise: float = (hit_pos - base_pos).dot(local_up)
			if rise < 0.055 or rise > step_height + 0.10:
				continue
			# Prefer the nearest useful top.  A farther sample may be higher, but the
			# rounded profile should start reacting to the first reachable edge.
			var score: float = rise * 1.35 + (reach - distance_value) * 0.22
			var best_score: float = best_rise * 1.35 + (reach - best_distance) * 0.22
			if best_rise <= 0.0 or score > best_score:
				best_rise = rise
				best_distance = distance_value
				best_lane = lane_value

	if best_rise <= 0.0:
		return

	var height_weight: float = clampf((best_rise - 0.04) / maxf(step_height * 0.72, 0.01), 0.08, 1.0)
	var distance_weight: float = clampf(1.0 - best_distance / maxf(reach, 0.01), 0.18, 1.0)
	var strength: float = clampf(height_weight * 0.72 + distance_weight * 0.52, 0.16, 1.0)
	_virtual_ramp_strength = maxf(_virtual_ramp_strength, strength)

	var travel_speed: float = linear_velocity.dot(travel)
	var upward_speed: float = linear_velocity.dot(local_up)
	var desired_up_speed: float = clampf(0.28 + best_rise * 1.75 + maxf(travel_speed, 0.0) * 0.085, 0.30, 1.55)
	var up_error: float = desired_up_speed - upward_speed
	var climb_up_gain: float = float(cfg.get("climb_up_gain", 8.0))
	var climb_forward_gain: float = float(cfg.get("climb_forward_gain", 14.0))
	var lift_force: float = mass * (WORLD_GRAVITY * 0.42 + up_error * climb_up_gain * 0.72) * strength
	lift_force = clampf(lift_force, 0.0, mass * 18.0)
	var forward_force: float = mass * climb_forward_gain * (0.38 + strength * 0.30)

	# Apply the lift toward the approaching end, so the rigid chassis itself pitches
	# over the edge.  A small lateral offset follows whichever track found the top.
	var force_offset: Vector3 = travel * (s.z * 0.285) + side * (s.x * best_lane * 0.32)
	apply_force(local_up * lift_force + travel * forward_force, force_offset)

	# Physics uses the softened layer, but chassis/wheel animation should still read
	# the authored obstacle height. Re-sample the exact chosen lane on layers 1+2;
	# in Arena the untouched layer-2 probe is encountered first, while other maps
	# transparently fall back to their ordinary layer-1 collision.
	var visual_rise: float = best_rise
	var visual_base_query := PhysicsRayQueryParameters3D.create(base_from, base_to)
	visual_base_query.exclude = [get_rid()]
	visual_base_query.collision_mask = TERRAIN_VISUAL_MASK
	var visual_base_hit := space.intersect_ray(visual_base_query)
	if not visual_base_hit.is_empty():
		var visual_center: Vector3 = global_position + travel * (front_offset + best_distance) + side * (s.x * best_lane)
		var visual_from: Vector3 = visual_center + local_up * (step_height + 0.48)
		var visual_to: Vector3 = visual_center - local_up * 0.30
		var visual_query := PhysicsRayQueryParameters3D.create(visual_from, visual_to)
		visual_query.exclude = [get_rid()]
		visual_query.collision_mask = TERRAIN_VISUAL_MASK
		var visual_hit := space.intersect_ray(visual_query)
		if not visual_hit.is_empty():
			var visual_normal: Vector3 = Vector3(visual_hit["normal"]).normalized()
			if visual_normal.dot(local_up) > 0.50:
				var visual_base_pos: Vector3 = visual_base_hit["position"]
				var visual_hit_pos: Vector3 = visual_hit["position"]
				var authored_rise: float = (visual_hit_pos - visual_base_pos).dot(local_up)
				if authored_rise > 0.0 and authored_rise <= step_height + 0.16:
					visual_rise = authored_rise
	var ramp_angle: float = atan2(visual_rise, maxf(best_distance + 0.42, 0.20))
	_terrain_pitch_target = direction_sign * clampf(ramp_angle * 0.20, 0.012, 0.060)

func _apply_obstacle_grip(_delta: float) -> void:
	# Flat-ground friction stays intentionally low so the tank does not feel heavy.
	# On steps/slopes, however, caterpillar tracks should bite instead of skating
	# sideways off the obstacle. Apply anisotropic grip only while terrain is rough.
	if _ground_contacts <= 0:
		return
	var body_up: Vector3 = global_basis.y.normalized()
	var normal: Vector3 = _support_normal.normalized()
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	var support_tilt: float = clampf(1.0 - normal.dot(body_up), 0.0, 1.0)
	var body_tilt: float = clampf(1.0 - body_up.dot(Vector3.UP), 0.0, 1.0)
	var obstacle_factor: float = maxf(_rough_contact_factor, maxf(_virtual_ramp_strength, maxf(support_tilt * 3.8, body_tilt * 2.2)))
	if obstacle_factor < 0.045:
		return
	obstacle_factor = clampf(obstacle_factor, 0.0, 1.0)

	var forward: Vector3 = (-global_basis.z.normalized()).slide(normal)
	var side: Vector3 = global_basis.x.normalized().slide(normal)
	if forward.length_squared() < 0.001 or side.length_squared() < 0.001:
		return
	forward = forward.normalized()
	side = side.normalized()
	var tangent_velocity: Vector3 = linear_velocity - normal * linear_velocity.dot(normal)
	var lateral_speed: float = tangent_velocity.dot(side)
	# Caterpillar cleats should strongly resist sideways skating once even one track
	# is riding an obstacle. This is deliberately much stronger than flat-ground grip.
	var side_gain: float = lerpf(10.0, 34.0, obstacle_factor)
	apply_central_force(side * (-lateral_speed * mass * side_gain))
	var roll_rate: float = angular_velocity.dot(forward)
	apply_torque(forward * (-roll_rate * mass * lerpf(0.55, 1.85, obstacle_factor)))

	var drive_command: float = (_left_track_speed + _right_track_speed) * 0.5
	var forward_speed: float = tangent_velocity.dot(forward)
	if absf(drive_command) < 0.08:
		# Hill-hold while the player is not asking for movement.
		var hold_gain: float = lerpf(6.0, 19.0, obstacle_factor)
		apply_central_force(forward * (-forward_speed * mass * hold_gain))
	else:
		# Never let gravity/solver motion pull the tank opposite the commanded track
		# direction while it is climbing an obstacle.
		var intended_sign: float = signf(drive_command)
		var signed_speed: float = forward_speed * intended_sign
		if signed_speed < 0.0:
			var bite_gain: float = lerpf(8.0, 23.0, obstacle_factor)
			apply_central_force(forward * intended_sign * (-signed_speed * mass * bite_gain))

func _apply_stuck_recovery(delta: float) -> void:
	# Emergency fallback for decorative collision triangles that still manage to
	# solver-lock the rounded tracks.  Normal traversal is handled by the virtual
	# ramp above; this only wakes up after commanded motion stops making progress.
	_stuck_recovery_cooldown = maxf(0.0, _stuck_recovery_cooldown - delta)
	var drive_command: float = (_left_track_speed + _right_track_speed) * 0.5
	var turn_command: float = (_right_track_speed - _left_track_speed) * 0.5
	if _ground_contacts <= 0 or (absf(drive_command) < 0.18 and absf(turn_command) < 0.18):
		_stuck_drive_time = maxf(0.0, _stuck_drive_time - delta * 4.0)
		return

	var body_up: Vector3 = global_basis.y.normalized()
	if body_up.dot(Vector3.UP) < 0.30:
		_stuck_drive_time = 0.0
		return

	var forward: Vector3 = -global_basis.z.normalized()
	var drive_stuck: bool = false
	if absf(drive_command) >= 0.18:
		var travel: Vector3 = forward * signf(drive_command)
		var progress_speed: float = linear_velocity.dot(travel)
		drive_stuck = progress_speed < 0.62 and linear_velocity.length() < 1.85

	var yaw_rate: float = absf(angular_velocity.dot(body_up))
	var turn_stuck: bool = absf(turn_command) >= 0.18 and yaw_rate < 0.21
	if drive_stuck or turn_stuck:
		_stuck_drive_time += delta
	else:
		_stuck_drive_time = maxf(0.0, _stuck_drive_time - delta * 4.2)

	if _stuck_drive_time < 0.14:
		return

	sleeping = false
	var strength: float = clampf((_stuck_drive_time - 0.14) / 0.42, 0.0, 1.0)
	if absf(drive_command) >= 0.18:
		var travel: Vector3 = forward * signf(drive_command)
		var hull_size: Vector3 = _cfg()["size"]
		var force_offset: Vector3 = travel * (hull_size.z * 0.30)
		var forward_force: float = mass * lerpf(19.0, 46.0, strength)
		var lift_force: float = mass * lerpf(4.2, 14.5, strength)
		apply_force(travel * forward_force + body_up * lift_force, force_offset)

	if absf(turn_command) >= 0.18:
		apply_torque(body_up * signf(turn_command) * mass * lerpf(5.0, 12.5, strength))

	if _stuck_drive_time > 0.48 and _stuck_recovery_cooldown <= 0.0:
		var impulse: Vector3 = body_up * 0.28 * mass
		if absf(drive_command) >= 0.18:
			impulse += forward * signf(drive_command) * 0.58 * mass
		apply_central_impulse(impulse)
		if absf(turn_command) >= 0.18:
			apply_torque_impulse(body_up * signf(turn_command) * mass * 0.66)
		_stuck_recovery_cooldown = 0.28

func _update_sprung_body_rock(delta: float) -> void:
	if _body_rock_root == null:
		return
	var cfg: Dictionary = _cfg()
	var body_forward: Vector3 = -global_basis.z.normalized()
	var body_up: Vector3 = global_basis.y.normalized()
	var velocity_source: Vector3 = linear_velocity if (local_control or ai_control) else _target_linear_velocity
	var angular_source: Vector3 = angular_velocity if (local_control or ai_control) else _target_angular_velocity
	var forward_speed: float = velocity_source.dot(body_forward)
	var longitudinal_accel: float = (forward_speed - _last_speed_for_rock) / maxf(delta, 0.0001)
	_last_speed_for_rock = forward_speed
	var yaw_rate: float = angular_source.dot(body_up)
	var yaw_accel: float = (yaw_rate - _last_yaw_rate_for_rock) / maxf(delta, 0.0001)
	_last_yaw_rate_for_rock = yaw_rate
	var lateral_accel: float = yaw_rate * forward_speed

	# Visual sprung-mass motion. Longitudinal acceleration keeps the classic pitch.
	# Cornering now loads the suspension visibly: sustained lateral acceleration gives
	# body roll, and the yaw-acceleration term adds a short transient so turn-in/exit
	# feels like a sprung tank rather than a rigid box rotating around Y.
	_terrain_pitch_bias = lerpf(_terrain_pitch_bias, _terrain_pitch_target, clampf(delta * 7.5, 0.0, 1.0))
	var accel_pitch: float = clampf(longitudinal_accel * float(cfg.get("rock_strength", 0.0010)) * 1.82, -0.030, 0.030)
	var pitch_target: float = clampf(accel_pitch + _terrain_pitch_bias, -0.068, 0.068)
	var speed_weight: float = clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0)
	# The sprung mass must lean OUTSIDE the turn. The previous sign made the hull
	# lean into the corner (forward+right -> right roll), which is backwards.
	# Negating lateral/yaw acceleration gives the expected inertial load transfer:
	# forward+right -> left roll, forward+left -> right roll.
	var roll_target: float = clampf(-lateral_accel * 0.0072, -0.032, 0.032)
	roll_target += clampf(-yaw_accel * absf(forward_speed) * 0.00042, -0.009, 0.009)
	if local_control and _turn_input != 0:
		# A small intent term starts loading the suspension before the heavy rigid body
		# has reached its final yaw rate. It uses the same OUTSIDE-turn sign as the
		# physical lateral acceleration above. At standstill it is intentionally tiny.
		var intent_strength: float = lerpf(0.0038, 0.0105, speed_weight)
		roll_target -= float(_turn_input) * intent_strength
	roll_target = clampf(roll_target, -0.040, 0.040)

	var pitch_accel: float = (pitch_target - _rock_pitch) * 39.0 - _rock_velocity * 9.2
	_rock_velocity += pitch_accel * delta
	_rock_pitch += _rock_velocity * delta
	_rock_pitch = clampf(_rock_pitch, -0.070, 0.070)

	var roll_accel: float = (roll_target - _rock_roll) * 34.0 - _rock_roll_velocity * 7.4
	_rock_roll_velocity += roll_accel * delta
	_rock_roll += _rock_roll_velocity * delta
	_rock_roll = clampf(_rock_roll, -0.045, 0.045)

func _update_stable_camera_pivot() -> void:
	if _camera_yaw_root == null:
		return
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var body_yaw := atan2(-forward.x, -forward.z)
	_camera_yaw_root.global_position = global_position + Vector3.UP * (_camera_anchor_base.y + 0.30)
	_camera_yaw_root.global_basis = Basis(Vector3.UP, body_yaw + turret_yaw)

func _remote_interpolation(delta: float) -> void:
	if _has_target:
		global_position = global_position.lerp(_target_position, clampf(delta * 10.0, 0.0, 1.0))
		var current_q := global_basis.get_rotation_quaternion()
		var blended := current_q.slerp(_target_rotation, clampf(delta * 12.0, 0.0, 1.0))
		global_basis = Basis(blended)
		turret_yaw = lerp_angle(turret_yaw, _target_turret, clampf(delta * 14.0, 0.0, 1.0))
	_left_track_speed = lerpf(_left_track_speed, _target_left_track, clampf(delta * 8.0, 0.0, 1.0))
	_right_track_speed = lerpf(_right_track_speed, _target_right_track, clampf(delta * 8.0, 0.0, 1.0))

func _handle_fire() -> void:
	if _is_overturned():
		firing = false
		_fire_down = Input.is_key_pressed(KEY_SPACE)
		_update_combat_hud()
		return
	var pressed: bool = Input.is_key_pressed(KEY_SPACE)
	var weapon: String = String(_cfg()["weapon"])
	var weapon_stats: Dictionary = _weapon_stats()
	if weapon == "firebird":
		firing = pressed and combat_fuel > 0.25 and combat_alive
	else:
		firing = false
		if pressed and _fire_cooldown <= 0.0 and combat_alive:
			_fire_cooldown = maxf(float(weapon_stats.get("reload", 1.0)), 0.05)
			_reload_visual_ratio = 0.0
			_perform_discrete_shot()
	_fire_down = pressed
	_update_combat_hud()

func _perform_discrete_shot() -> void:
	if _muzzle == null or _is_overturned():
		return
	if _shot_audio.stream != null:
		_shot_audio.play()
	var origin: Vector3 = _muzzle.global_position
	var direction: Vector3 = -_turret_root.global_basis.z.normalized()
	var weapon_stats: Dictionary = _weapon_stats()
	var shot_range: float = _effective_weapon_range(weapon_stats)
	var end: Vector3 = origin + direction * shot_range
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_rid()]
	# If a muzzle ends up under/inside terrain (most visibly on an overturned tank),
	# the ray must hit that terrain instead of treating the interior as empty space.
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var claimed_target_id: int = -1
	var world_blocked: bool = false
	if not hit.is_empty():
		end = hit["position"]
		var hit_tank: TankActor = _tank_from_collider(hit.get("collider", null))
		if hit_tank != null:
			claimed_target_id = hit_tank.player_id
		else:
			world_blocked = true

	var weapon: String = String(_cfg()["weapon"])
	# v19.1.1 hit fix: the raw barrel ray is allowed to touch floor/terrain first,
	# because Tanki-style vertical auto-aim has its OWN strict physics LOS checks.
	# v19.1.0 blocked auto-aim whenever the raw ray saw any world geometry; on many
	# slopes and platform edges that made perfectly visible tanks impossible to hit.
	# If strict auto-aim really sees the tank, it supersedes that raw world hit.
	if claimed_target_id < 0:
		var autoaim: Dictionary = _find_discrete_autoaim_target(origin, direction, shot_range, weapon)
		if not autoaim.is_empty():
			claimed_target_id = int(autoaim.get("target_id", -1))
			var impact_value: Variant = autoaim.get("impact", end)
			if impact_value is Vector3:
				end = impact_value as Vector3
			world_blocked = false

	var splash_targets: Array[int] = []
	if weapon == "thunder":
		splash_targets = _visible_splash_target_ids(end, direction, float(weapon_stats.get("splash_radius", 0.0)))

	_spawn_shot_fx(origin, end, weapon)
	_apply_weapon_recoil(direction, weapon, origin)
	if network != null:
		var shot_payload := {
			"origin":_v3(origin),
			"end":_v3(end),
			"target_id":claimed_target_id,
			"world_blocked":world_blocked,
			"splash_targets":splash_targets,
		}
		if ai_control:
			network.send_bot_shot(player_id, shot_payload)
		else:
			network.send_shot(shot_payload)

func _tank_from_collider(value: Variant) -> TankActor:
	# CollisionObject3D is normally the TankActor itself, but walking parents makes
	# hit registration robust if a future hull uses child Area/physics proxy nodes.
	if value is TankActor:
		return value as TankActor
	if value is Node:
		var current: Node = value as Node
		while current != null:
			if current is TankActor:
				return current as TankActor
			current = current.get_parent()
	return null

func _visible_splash_target_ids(impact: Vector3, shot_direction: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	if radius <= 0.05:
		return result
	var safe_direction: Vector3 = shot_direction.normalized() if shot_direction.length_squared() > 0.001 else Vector3.FORWARD
	# Keep the LOS origin on the shooter's side of an impacted wall. This makes the
	# wall itself block Thunder splash instead of letting the blast start inside it.
	var los_origin: Vector3 = impact - safe_direction * 0.18 + Vector3.UP * 0.05
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("tanki_tank"):
		if not (node is TankActor):
			continue
		var target := node as TankActor
		if not target.combat_alive:
			continue
		var target_size: Vector3 = target._cfg().get("size", Vector3(3.0, 1.4, 4.8))
		var target_center: Vector3 = _target_hit_center_world(target)
		if impact.distance_to(target_center) >= radius + target_size.x * 0.35:
			continue
		# Thunder can hurt its shooter. The impact point is always on the shooter's
		# side of the first world collision, so a close blast has a valid path back
		# into our own hull and does not need a ray that excludes our body RID.
		if target == self:
			result.append(target.player_id)
			continue
		var samples: Array[Vector3] = _target_hit_samples_world(target)
		var visible := false
		for point in samples:
			var delta_to: Vector3 = point - los_origin
			var los_query := PhysicsRayQueryParameters3D.create(los_origin, point + delta_to.normalized() * 0.18)
			los_query.exclude = [get_rid()]
			los_query.hit_from_inside = true
			var los_hit := space.intersect_ray(los_query)
			if not los_hit.is_empty():
				var los_tank: TankActor = _tank_from_collider(los_hit.get("collider", null))
				if los_tank == target:
					visible = true
					break
		if visible:
			result.append(target.player_id)
	return result

func _find_discrete_autoaim_target(origin: Vector3, forward: Vector3, shot_range: float, weapon: String) -> Dictionary:
	var result: Dictionary = {}
	var flat_forward := Vector2(forward.x, forward.z)
	if flat_forward.length_squared() < 0.0001:
		return result
	flat_forward = flat_forward.normalized()
	var yaw_limit_deg: float = 10.5 if weapon == "smoky" else 15.0
	var pitch_limit_deg: float = 46.0 if weapon == "smoky" else 54.0
	var best_score: float = INF
	var space := get_world_3d().direct_space_state

	for node in get_tree().get_nodes_in_group("tanki_tank"):
		if not (node is TankActor):
			continue
		var target := node as TankActor
		if target == self or not target.combat_alive:
			continue
		var target_size: Vector3 = target._cfg().get("size", Vector3(3.0, 1.4, 4.8))
		var target_center: Vector3 = _target_hit_center_world(target)
		var base_delta: Vector3 = target_center - origin
		var flat_delta := Vector2(base_delta.x, base_delta.z)
		var flat_distance: float = flat_delta.length()
		if flat_distance < 0.05:
			continue
		var center_distance: float = base_delta.length()
		if center_distance > shot_range + target_size.z * 0.55:
			continue
		var flat_unit: Vector2 = flat_delta / flat_distance
		var yaw_dot: float = clampf(flat_forward.dot(flat_unit), -1.0, 1.0)
		var yaw_deg: float = rad_to_deg(acos(yaw_dot))
		if yaw_deg > yaw_limit_deg:
			continue
		var pitch_deg: float = absf(rad_to_deg(atan2(base_delta.y, flat_distance)))
		if pitch_deg > pitch_limit_deg:
			continue

		# Sample the target in its LOCAL orientation. World-UP height samples break as
		# soon as the victim is on its side or roof and were the main reason overturned
		# tanks could become strangely unhittable.
		for aim_point in _target_hit_samples_world(target):
			var aim_delta: Vector3 = aim_point - origin
			if aim_delta.length() > shot_range + target_size.z * 0.75:
				continue
			var los_query := PhysicsRayQueryParameters3D.create(origin, aim_point + aim_delta.normalized() * 0.25)
			los_query.exclude = [get_rid()]
			los_query.hit_from_inside = true
			var los_hit: Dictionary = space.intersect_ray(los_query)
			if los_hit.is_empty():
				continue
			var los_tank: TankActor = _tank_from_collider(los_hit.get("collider", null))
			if los_tank == target:
				var impact_value: Variant = los_hit.get("position", aim_point)
				var impact: Vector3 = aim_point
				if impact_value is Vector3:
					impact = impact_value as Vector3
				var vertical_cost: float = absf(impact.y - origin.y) * 0.030
				var score: float = yaw_deg * 1.55 + vertical_cost + center_distance * 0.0035
				if score < best_score:
					best_score = score
					result = {"target_id":target.player_id, "impact":impact}

	return result

func _apply_weapon_recoil(direction: Vector3, weapon: String, _origin: Vector3) -> void:
	if not (local_control or ai_control) or weapon == "firebird":
		return
	var kick_speed: float = 0.16 if weapon == "smoky" else 0.52
	# Per request, lighter hulls receive a smaller physical reaction. The impulse
	# is expressed as desired delta-v * mass so each hull's result is predictable.
	var hull_factor: float = _weapon_recoil_hull_factor()
	var recoil_direction: Vector3 = -direction.normalized()
	var impulse: Vector3 = recoil_direction * mass * kick_speed * hull_factor
	# Translation is physical. Pitch/roll are handled by the sprung-body spring below
	# so a sideways turret can rock the hull without applying unstable muzzle torque.
	apply_central_impulse(impulse)
	_apply_visual_weapon_rock(direction, weapon, hull_factor)
	sleeping = false

func _weapon_recoil_hull_factor() -> float:
	if hull_id == "viking":
		return 0.84
	if hull_id == "mamont":
		return 1.0
	return 0.68

func _apply_visual_weapon_rock(direction: Vector3, weapon: String, hull_factor: float = 1.0) -> void:
	if weapon == "firebird" or direction.length_squared() < 0.0001:
		return
	var shot_direction: Vector3 = direction.normalized()
	var body_forward: Vector3 = -global_basis.z.normalized()
	var body_right: Vector3 = global_basis.x.normalized()
	var forward_alignment: float = clampf(shot_direction.dot(body_forward), -1.0, 1.0)
	var side_alignment: float = clampf(shot_direction.dot(body_right), -1.0, 1.0)

	var pitch_kick: float = 0.12 if weapon == "smoky" else 0.34
	_rock_velocity += pitch_kick * hull_factor * forward_alignment
	_rock_velocity = clampf(_rock_velocity, -0.42, 0.42)

	# Only a substantially side-facing gun creates roll. Near exactly 90 degrees the
	# effect is strongest, and its sign follows whether the barrel points left/right.
	var side_weight: float = smoothstep(0.28, 0.88, absf(side_alignment))
	var roll_kick: float = (0.115 if weapon == "smoky" else 0.28) * hull_factor
	_rock_roll_velocity += side_alignment * side_weight * roll_kick
	_rock_roll_velocity = clampf(_rock_roll_velocity, -0.46, 0.46)

func play_remote_shot(data: Dictionary) -> void:
	var a = data.get("origin", [])
	var b = data.get("end", [])
	if not (a is Array and b is Array and a.size() >= 3 and b.size() >= 3):
		return
	if _shot_audio != null and _shot_audio.stream != null:
		_shot_audio.play()
	var shot_origin := Vector3(float(a[0]), float(a[1]), float(a[2]))
	var shot_end := Vector3(float(b[0]), float(b[1]), float(b[2]))
	var remote_weapon: String = String(data.get("weapon", _cfg()["weapon"]))
	if remote_weapon != "firebird":
		_fire_cooldown = maxf(float(_weapon_stats().get("reload", 1.0)), 0.05)
		_reload_visual_ratio = 0.0
	_spawn_shot_fx(shot_origin, shot_end, remote_weapon)
	var remote_direction: Vector3 = shot_end - shot_origin
	if remote_direction.length_squared() > 0.0001:
		_apply_visual_weapon_rock(remote_direction.normalized(), remote_weapon, _weapon_recoil_hull_factor())

func _spawn_shot_fx(origin: Vector3, end: Vector3, weapon: String) -> void:
	var direction := (end - origin).normalized()
	if direction.length_squared() < 0.1:
		direction = -_turret_root.global_basis.z.normalized()

	if weapon == "smoky":
		# Make the original demo VFX read at gameplay distance: larger muzzle flash,
		# much fatter smoke trail, and a noticeably larger impact blast.
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.12, 56, 58, 0.10, 1.55, 2.85, direction * 0.25, Vector3.ZERO, 1.0, 0.72, randf_range(-0.5, 0.5))
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.24, 40, 47, 0.16, 1.70, 2.90, direction * 2.1, Vector3.UP * 0.18, 1.0, 0.64, 0.35)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.30, 0, 15, 0.92, 0.92, 2.45, direction * 0.85 + Vector3.UP * 0.95, Vector3.UP * 0.16, 0.78, 0.20, -0.18)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end, 16, 31, 0.40, 1.85, 3.55, Vector3.UP * 0.15, Vector3.UP * 0.12, 1.0, 0.70, 0.20)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end + Vector3.UP * 0.15, 0, 15, 1.10, 1.10, 3.05, Vector3.UP * 1.05, Vector3.UP * 0.06, 0.78, 0.16, -0.15)
		_spawn_muzzle_flash_light(origin, direction, Color(1.0, 0.70, 0.32), 3.4, 5.6, 0.12)
		_spawn_flash_light(end, Color(1.0, 0.42, 0.10), 2.2, 4.4, 0.14)
	else:
		# Thunder must feel like a heavy shell: huge muzzle bloom and a much bigger impact cloud.
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.14, 56, 58, 0.13, 2.80, 5.10, direction * 0.30, Vector3.ZERO, 1.0, 0.75, randf_range(-0.35, 0.35))
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.24, 40, 47, 0.20, 2.55, 4.55, direction * 2.5, Vector3.UP * 0.22, 1.0, 0.66, 0.42)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.34, 0, 15, 1.05, 1.05, 2.90, direction * 0.90 + Vector3.UP * 1.05, Vector3.UP * 0.15, 0.82, 0.18, -0.16)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end, 16, 39, 0.70, 3.50, 7.20, Vector3.UP * 0.24, Vector3.UP * 0.16, 1.0, 0.74, 0.25)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end + Vector3.UP * 0.18, 56, 58, 0.18, 2.85, 4.70, Vector3.ZERO, Vector3.ZERO, 0.94, 0.80, 0.0)
		_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end + Vector3.UP * 0.28, 0, 15, 1.65, 2.10, 5.90, Vector3.UP * 1.15, Vector3.UP * 0.04, 0.84, 0.14, -0.12)
		_spawn_muzzle_flash_light(origin, direction, Color(1.0, 0.73, 0.36), 5.8, 8.0, 0.15)
		_spawn_flash_light(end, Color(1.0, 0.35, 0.08), 8.2, 11.0, 0.24)

func _spawn_sheet_fx(
	texture_path: String,
	position: Vector3,
	first_frame: int,
	last_frame: int,
	life: float,
	start_size: float,
	end_size: float,
	velocity: Vector3 = Vector3.ZERO,
	acceleration: Vector3 = Vector3.ZERO,
	alpha: float = 1.0,
	fade_start: float = 0.55,
	spin_speed: float = 0.0,
	color: Color = Color.WHITE
) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var fx = SheetEffectScript.new()
	root.add_child(fx)
	fx.global_position = position
	fx.setup(texture_path, first_frame, last_frame, life, start_size, end_size, velocity, acceleration, alpha, fade_start, spin_speed, color)

func _spawn_muzzle_flash_light(position: Vector3, direction: Vector3, color: Color, energy: float, range_m: float, life: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	# A short-lived point light gives the same readable muzzle flash without the
	# hard trapezoid/rectangle that a wide SpotLight can project onto Arena floors.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m * 0.72
	light.omni_attenuation = 0.72
	light.shadow_enabled = true
	light.shadow_bias = 0.035
	light.shadow_normal_bias = 0.65
	root.add_child(light)
	var safe_direction: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	light.global_position = position + safe_direction * 0.32
	var tween := get_tree().create_tween()
	tween.tween_property(light, "light_energy", 0.0, life)
	tween.tween_callback(light.queue_free)

func _spawn_flash_light(position: Vector3, color: Color, energy: float, range_m: float, life: float, shadows: bool = true) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	# Death flashes are spawned very close to/inside the wreck. Shadow cubemaps from
	# that position can create a black box around the hull and rectangular light tiles
	# on Compatibility-renderer map geometry. Normal weapon flashes keep shadows.
	light.shadow_enabled = shadows
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 0.75
	root.add_child(light)
	light.global_position = position
	var tween := get_tree().create_tween()
	tween.tween_property(light, "light_energy", 0.0, life)
	tween.tween_callback(light.queue_free)

func _emit_firebird_stream(delta: float) -> void:
	if _muzzle == null:
		return
	_firebird_emit_elapsed += delta
	# v19.1: the damage range grew from 18 m to 28 m. Use a longer-lived, faster
	# plume, but emit slightly less often so the extra visible length does not explode
	# particle count on bot-heavy matches.
	var interval := 0.042
	while _firebird_emit_elapsed >= interval:
		_firebird_emit_elapsed -= interval
		var forward := -_turret_root.global_basis.z.normalized()
		var side := _turret_root.global_basis.x.normalized()
		var up := Vector3.UP
		var base_origin := _muzzle.global_position + forward * 0.26 + up * 0.02

		var core_jitter := side * randf_range(-0.12, 0.12) + up * randf_range(-0.03, 0.13)
		var core_origin := base_origin + core_jitter
		var core_velocity := forward * randf_range(20.0, 25.5) + up * randf_range(0.30, 1.10) + side * randf_range(-0.30, 0.30)
		_spawn_sheet_fx("res://assets/effects/fire_rgba.png", core_origin, 32, 47, randf_range(0.82, 1.06), randf_range(1.25, 1.58), randf_range(3.15, 4.10), core_velocity, Vector3.UP * 0.22, randf_range(0.92, 1.0), 0.72, randf_range(-0.38, 0.38))

		var halo_origin := base_origin + side * randf_range(-0.22, 0.22) + up * randf_range(0.00, 0.15)
		var halo_velocity := forward * randf_range(17.0, 22.5) + up * randf_range(0.35, 1.20) + side * randf_range(-0.42, 0.42)
		_spawn_sheet_fx("res://assets/effects/firebird_rgba_clean.png", halo_origin, 16, 31, randf_range(0.88, 1.16), randf_range(1.05, 1.38), randf_range(2.70, 3.55), halo_velocity, Vector3.UP * 0.18, randf_range(0.88, 0.98), 0.68, randf_range(-0.46, 0.46))

		if randf() < 0.38:
			var tongue_origin := base_origin + forward * randf_range(0.25, 0.75) + side * randf_range(-0.18, 0.18) + up * randf_range(0.00, 0.11)
			var tongue_velocity := forward * randf_range(15.0, 20.0) + up * randf_range(0.20, 0.78)
			_spawn_sheet_fx("res://assets/effects/firebird_rgba_clean.png", tongue_origin, 48, 63, randf_range(0.72, 0.96), randf_range(0.84, 1.08), randf_range(2.00, 2.75), tongue_velocity, Vector3.UP * 0.12, randf_range(0.84, 0.96), 0.68, randf_range(-0.52, 0.52))

		if randf() < 0.24:
			var smoke_origin := base_origin + forward * randf_range(0.55, 1.55) + up * randf_range(0.30, 0.52)
			var smoke_velocity := forward * randf_range(6.0, 9.5) + up * randf_range(0.90, 1.55)
			_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", smoke_origin, 0, 15, randf_range(1.25, 1.65), randf_range(0.88, 1.15), randf_range(2.45, 3.35), smoke_velocity, Vector3.UP * 0.04, randf_range(0.36, 0.52), 0.24, randf_range(-0.15, 0.15), Color(0.28, 0.24, 0.22, 1.0))


func _send_state() -> void:
	if network == null:
		return
	var q := global_basis.get_rotation_quaternion().normalized()
	var aim: Vector3 = -_turret_root.global_basis.z.normalized() if _turret_root != null else -global_basis.z.normalized()
	var fire_targets: Array[int] = []
	if _is_overturned():
		firing = false
	elif firing and String(_cfg()["weapon"]) == "firebird":
		fire_targets = _firebird_target_ids(aim)
	var payload := {
		"p":_v3(global_position),
		"yaw":_body_heading_yaw(),
		"rot":[q.x, q.y, q.z, q.w],
		"lin_vel":_v3(linear_velocity),
		"ang_vel":_v3(angular_velocity),
		"turret":turret_yaw,
		"aim":_v3(aim),
		"speed":current_speed,
		"left_track":_left_track_speed,
		"right_track":_right_track_speed,
		"firing":firing,
		"fire_targets":fire_targets
	}
	if ai_control:
		network.send_bot_state(player_id, payload)
	else:
		network.send_state(payload)

func _firebird_target_ids(aim: Vector3) -> Array[int]:
	var result: Array[int] = []
	if _muzzle == null:
		return result
	var weapon_stats: Dictionary = _weapon_stats()
	var max_range: float = maxf(float(weapon_stats.get("range", 28.0)), 1.0)
	var cone_deg: float = clampf(float(weapon_stats.get("cone_deg", 26.0)), 1.0, 80.0)
	var origin: Vector3 = _muzzle.global_position
	var space := get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("tanki_tank"):
		if not (node is TankActor):
			continue
		var target := node as TankActor
		if target == self or not target.combat_alive:
			continue
		var target_cfg: Dictionary = target._cfg()
		var target_size: Vector3 = target_cfg.get("size", Vector3(3.0, 1.4, 4.8))
		var aim_point: Vector3 = _target_hit_center_world(target)
		var delta: Vector3 = aim_point - origin
		var distance_to_target: float = delta.length()
		if distance_to_target <= 0.05 or distance_to_target > max_range + target_size.z * 0.28:
			continue
		var unit_to_target: Vector3 = delta / distance_to_target
		var angular_bonus: float = rad_to_deg(asin(clampf((target_size.x * 0.42) / maxf(distance_to_target, 0.2), 0.0, 0.82)))
		var effective_cone: float = minf(cone_deg + angular_bonus + 7.0, 78.0)
		if aim.dot(unit_to_target) < cos(deg_to_rad(effective_cone)):
			continue

		# Even at point blank, Firebird now needs a real collision-visible path. The
		# extra body-centre ray handles muzzle-inside-target cases without permitting
		# fire through a wall separating two touching tanks.
		var ray_origins: Array[Vector3] = [origin]
		if distance_to_target < maxf(3.2, target_size.z * 0.72):
			var shooter_up: Vector3 = global_basis.y.normalized()
			ray_origins.append(global_position + shooter_up * 1.05)
		var visible: bool = false
		for ray_origin in ray_origins:
			for ray_target in _target_hit_samples_world(target):
				var ray_delta: Vector3 = ray_target - ray_origin
				if ray_delta.length_squared() < 0.01:
					visible = true
					break
				var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target + ray_delta.normalized() * 0.20)
				query.exclude = [get_rid()]
				query.hit_from_inside = true
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					var hit_tank: TankActor = _tank_from_collider(hit.get("collider", null))
					if hit_tank == target:
						visible = true
						break
			if visible:
				break
		if visible:
			result.append(target.player_id)
			if result.size() >= 6:
				break
	return result

func _body_heading_yaw() -> float:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)

func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func _update_visual_pose(delta: float) -> void:
	if _running_gear_root == null or _body_rock_root == null:
		return
	# Terrain orientation now comes from the actual RigidBody3D. No support-plane
	# rotation is painted onto the mesh, so collision, tracks and hull cannot disagree.
	_running_gear_root.rotation = Vector3.ZERO
	_body_rock_root.rotation.x = lerp_angle(_body_rock_root.rotation.x, _rock_pitch, clampf(delta * 10.0, 0.0, 1.0))
	_body_rock_root.rotation.z = lerp_angle(_body_rock_root.rotation.z, _rock_roll, clampf(delta * 10.0, 0.0, 1.0))

func _update_visual_track_speeds(delta: float) -> void:
	# Drive commands describe requested track speed. Visual tracks must follow the
	# actual rigid-body motion, otherwise they instantly spin at full speed while
	# the several-ton chassis is still accelerating and the tank looks like it is
	# skating on ice. Differential speed also comes from real yaw velocity.
	var cfg: Dictionary = _cfg()
	var velocity_source: Vector3 = linear_velocity if (local_control or ai_control) else _target_linear_velocity
	var angular_source: Vector3 = angular_velocity if (local_control or ai_control) else _target_angular_velocity
	var forward: Vector3 = -global_basis.z.normalized()
	var up: Vector3 = global_basis.y.normalized()
	var forward_speed: float = velocity_source.dot(forward)
	var yaw_rate: float = angular_source.dot(up)
	var hull_size: Vector3 = cfg["size"]
	var half_track_spacing: float = hull_size.x * 0.355
	var left_linear: float = forward_speed - yaw_rate * half_track_spacing
	var right_linear: float = forward_speed + yaw_rate * half_track_spacing
	var left_target: float = clampf(left_linear / MAX_SPEED, -1.25, 1.25)
	var right_target: float = clampf(right_linear / MAX_SPEED, -1.25, 1.25)
	# Solver/network micro-velocities around rest should not make the UVs crawl back
	# and forth. Above the dead zone the response stays continuous.
	if absf(left_target) < 0.018:
		left_target = 0.0
	if absf(right_target) < 0.018:
		right_target = 0.0
	var response: float = clampf(delta * 8.0, 0.0, 1.0)
	_left_track_visual_speed = lerpf(_left_track_visual_speed, left_target, response)
	_right_track_visual_speed = lerpf(_right_track_visual_speed, right_target, response)

func _update_wheel_suspension(delta: float) -> void:
	var rest: float = float(_cfg()["suspension_rest"])
	var travel: float = float(_cfg()["suspension_travel"])
	var radius: float = float(_cfg()["wheel_radius"])
	var bias_y: float = float(_cfg().get("wheel_bias_y", 0.0))
	_update_wheel_side(_left_wheels, _left_track_visual_speed, rest, travel, radius, bias_y, delta)
	_update_wheel_side(_right_wheels, _right_track_visual_speed, rest, travel, radius, bias_y, delta)

func _update_wheel_side(wheels: Array[Node3D], track_speed: float, _rest: float, travel: float, radius: float, bias_y: float, delta: float) -> void:
	var up: Vector3 = global_basis.y.normalized()
	var down: Vector3 = -up
	var gear_drop: float = float(_cfg().get("running_gear_drop", 0.0))
	var ground_clearance: float = float(_cfg().get("track_ground_clearance", 0.012))
	var extension_ratio: float = clampf(float(_cfg().get("visual_wheel_extension", 0.62)), 0.30, 0.82)
	# Because the neutral wheel is lowered by gear_drop, allowing the same amount
	# back upward does not move it any closer to the hull than v17.8 did.
	var compression_limit: float = travel + gear_drop * 0.42
	# Keep a little droop for the suspension, but do not let a road wheel hang so
	# far below the lower belt that its rim/tire becomes visible outside the track.
	var extension_limit: float = travel * minf(extension_ratio, 0.43)
	# Wasp has a very shallow side skirt and comparatively large rendered road wheels.
	# Generic droop that looks fine on Viking/Mamont exposes the Wasp rollers below the
	# caterpillar silhouette. Keep Wasp's visual extension much tighter; physics is not
	# changed here, only the rendered running gear.
	if hull_id == "wasp":
		extension_limit = minf(extension_limit, travel * 0.16)
	var space := get_world_3d().direct_space_state
	# Around zero speed the smoothed visual velocity can change sign by a tiny amount
	# from physics/network noise. Do not flip the preview ray back and forth there.
	var direction_sign: float = signf(track_speed) if absf(track_speed) > 0.055 else 0.0
	var travel_forward: Vector3 = -global_basis.z.normalized() * direction_sign
	var preview_distance: float = float(_cfg().get("suspension_lookahead", 0.58)) * 1.05
	var step_height: float = float(_cfg().get("step_height", 0.85))
	for wheel in wheels:
		if wheel == null:
			continue
		var key: int = wheel.get_instance_id()
		var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
		var base_rot: Vector3 = _wheel_local_rot.get(key, wheel.rotation)
		var neutral_y: float = base_local.y + bias_y
		var target_y: float = neutral_y
		var parent_node := wheel.get_parent()
		if parent_node is Node3D and _is_primary_road_wheel(wheel):
			var parent_3d := parent_node as Node3D
			var neutral_local := Vector3(base_local.x, neutral_y, base_local.z)
			var neutral_world: Vector3 = parent_3d.to_global(neutral_local)
			var visual_radius: float = maxf(radius, float(_wheel_visual_radius.get(key, radius)))
			var upper_track_guard: float = maxf(visual_radius * 0.17, 0.035)
			# The track itself is the visible contact surface. Seat road wheels a few
			# centimetres inside that belt instead of merely touching the terrain plane.
			# This prevents the lower arc from leaking through the belt during compression.
			var track_embed: float = clampf(visual_radius * 0.10, 0.025, 0.052)
			if hull_id == "wasp":
				# Seat Wasp road wheels deeper inside the belt. The imported Wasp wheel art
				# is visually larger than its physics radius, so the generic clearance leaves
				# a visible lower arc outside the track on flat terrain.
				track_embed = maxf(track_embed, clampf(visual_radius * 0.30, 0.075, 0.115))
			# Scan enough space above/below the lowered neutral centre to cover the full
			# visual travel. The target centre is derived directly from the surface hit:
			# hit + visual radius + a tiny clearance. This makes wheel/terrain penetration
			# impossible as long as the arena render and collision surfaces agree.
			var ray_above: float = visual_radius + compression_limit + 0.22
			var ray_below: float = visual_radius + extension_limit + 0.22
			var query := PhysicsRayQueryParameters3D.create(neutral_world + up * ray_above, neutral_world + down * ray_below)
			query.exclude = [get_rid()]
			# Arena layer 2 is the untouched source mesh used only by visual suspension.
			# Mask 3 keeps Test Polygon/props compatible because their terrain remains layer 1.
			query.collision_mask = TERRAIN_VISUAL_MASK
			var hit := space.intersect_ray(query)
			var suspension_offset: float = -extension_limit
			if not hit.is_empty():
				var hit_normal: Vector3 = hit["normal"]
				hit_normal = hit_normal.normalized()
				if hit_normal.dot(up) > 0.30:
					var hit_pos: Vector3 = hit["position"]
					var desired_center: Vector3 = hit_pos + up * (visual_radius + ground_clearance + track_embed)
					var desired_offset: float = (desired_center - neutral_world).dot(up)
					suspension_offset = clampf(desired_offset, -extension_limit, compression_limit)

			# The leading road wheels keep the old look-ahead, but use the same visual
			# radius rule. A curb can compress a wheel early, never push it through the top.
			var leading_amount: float = -base_local.z * direction_sign
			if absf(direction_sign) > 0.01 and leading_amount > -0.02:
				var preview_center: Vector3 = neutral_world + travel_forward * preview_distance
				var preview_query := PhysicsRayQueryParameters3D.create(preview_center + up * (visual_radius + step_height + 0.30), preview_center + down * ray_below)
				preview_query.exclude = [get_rid()]
				preview_query.collision_mask = TERRAIN_VISUAL_MASK
				var preview_hit := space.intersect_ray(preview_query)
				if not preview_hit.is_empty():
					var preview_normal: Vector3 = preview_hit["normal"]
					preview_normal = preview_normal.normalized()
					if preview_normal.dot(up) > 0.50:
						var preview_pos: Vector3 = preview_hit["position"]
						var preview_desired_center: Vector3 = preview_pos + up * (visual_radius + ground_clearance + track_embed)
						var preview_offset: float = (preview_desired_center - preview_center).dot(up)
						preview_offset = clampf(preview_offset, -extension_limit, compression_limit)
						suspension_offset = maxf(suspension_offset, preview_offset * 0.92)
			target_y += suspension_offset
			# Wheels should never visibly poke above the belt/fender line. The running gear
			# still has the v17.9 droop reserve, but upward motion is capped a little below
			# the old maximum so the road wheel stays visually inside the track envelope.
			target_y = minf(target_y, neutral_y + compression_limit * 0.82 - upper_track_guard)
			if hull_id == "wasp":
				# Hard visual envelope: Wasp primary rollers may compress upward freely but
				# must never hang below their imported neutral line. The track itself was
				# lowered for suspension reserve, so this keeps the circles hidden inside it.
				target_y = maxf(target_y, neutral_y + 0.030)
		# Extension remains soft, but upward compression must keep pace with the belt.
		# The belt has a hard terrain floor and can jump upward immediately on a curb;
		# letting the wheel lag behind it is what caused the wheel to show through the
		# track in v18.14. Allow at most ~2.5 cm of visual lag while compressing.
		var wheel_response: float = 18.0 if target_y > wheel.position.y else 8.0
		var next_wheel_y: float = lerpf(wheel.position.y, target_y, clampf(delta * wheel_response, 0.0, 1.0))
		if target_y > wheel.position.y:
			next_wheel_y = maxf(next_wheel_y, target_y - 0.025)
		wheel.position.y = next_wheel_y
		# The track deformation source must come from the suspension target, not the
		# final rendered wheel position. v18.16 may lift a rendered wheel after the belt
		# is deformed to keep it inside the track; feeding that correction back into the
		# belt would make the whole running gear ratchet upward frame after frame.
		if _is_primary_road_wheel(wheel):
			_wheel_track_source_offset[key] = target_y - neutral_y
		var spin_value: float = float(_wheel_spin.get(key, 0.0))
		# Imported wheel X-axis is opposite to the mathematical positive roll used by
		# the old formula. Negate drive so forward tank motion spins wheels forward.
		spin_value = fposmod(spin_value - (track_speed * MAX_SPEED / maxf(radius, 0.01)) * delta, TAU)
		_wheel_spin[key] = spin_value
		wheel.rotation = Vector3(base_rot.x + spin_value, base_rot.y, base_rot.z)

func _track_surface_samples(wheels: Array[Node3D]) -> Array[float]:
	var samples: Array[float] = []
	for _sample_index in range(TRACK_DEFORM_SAMPLES):
		samples.append(0.0)
	var primaries: Array[Node3D] = []
	for wheel in wheels:
		if wheel != null and _is_primary_road_wheel(wheel):
			primaries.append(wheel)
	if primaries.is_empty():
		return samples

	var min_z: float = 999999.0
	var max_z: float = -999999.0
	var avg_x: float = 0.0
	for wheel in primaries:
		var key: int = wheel.get_instance_id()
		var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
		min_z = minf(min_z, base_local.z)
		max_z = maxf(max_z, base_local.z)
		avg_x += base_local.x
	avg_x /= float(primaries.size())

	var cfg: Dictionary = _cfg()
	var travel: float = float(cfg.get("suspension_travel", 0.18))
	var step_height: float = float(cfg.get("step_height", 0.85))
	var gear_drop: float = float(cfg.get("running_gear_drop", 0.0))
	var clearance: float = float(cfg.get("track_ground_clearance", 0.012))
	var space := get_world_3d().direct_space_state
	var up: Vector3 = global_basis.y.normalized()
	# The imported lower belt is around local Y=0. VisualRoot contributes +0.03 m;
	# v17.9 then lowers the whole running gear by running_gear_drop. Surface offsets
	# are therefore measured from that new neutral belt plane.
	var neutral_track_y: float = (_visual_root.position.y if _visual_root != null else 0.03) - gear_drop
	var sample_denominator: float = maxf(float(TRACK_DEFORM_SAMPLES - 1), 1.0)
	for sample_index in range(TRACK_DEFORM_SAMPLES):
		var z: float = lerpf(min_z, max_z, float(sample_index) / sample_denominator)
		var start_local := Vector3(avg_x, neutral_track_y + step_height + 0.70, z)
		var end_local := Vector3(avg_x, neutral_track_y - travel * 3.0 - 0.42, z)
		var start_world: Vector3 = global_transform * start_local
		var end_world: Vector3 = global_transform * end_local
		var query := PhysicsRayQueryParameters3D.create(start_world, end_world)
		query.exclude = [get_rid()]
		query.collision_mask = TERRAIN_VISUAL_MASK
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if normal.normalized().dot(up) < 0.34:
			continue
		var local_hit: Vector3 = global_transform.affine_inverse() * Vector3(hit["position"])
		var offset: float = local_hit.y - neutral_track_y
		# This value is a hard floor for the lower belt, not merely an animation hint.
		# Do not scale it down: the old 0.92 factor could intentionally leave the belt
		# a few millimetres below the collision surface. Add a small clearance instead.
		samples[sample_index] = clampf(offset + clearance, -travel * 0.62, step_height * 0.58 + gear_drop)
	return samples

func _track_deform_samples(wheels: Array[Node3D], _track_speed: float, terrain_samples: Array[float]) -> Array[float]:
	var entries: Array[Dictionary] = []
	var bias_y: float = float(_cfg().get("wheel_bias_y", 0.0))
	for wheel in wheels:
		if wheel == null or not _is_primary_road_wheel(wheel):
			continue
		var key: int = wheel.get_instance_id()
		var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
		# wheel_bias_y remains a static art-alignment correction. Running-gear drop is
		# already baked into base_local, so only actual suspension motion bends the belt.
		# Use the pre-envelope suspension target cached in _update_wheel_side(). The
		# rendered wheel can then be lifted into the belt without recursively lifting
		# the belt itself on the next frame.
		var source_offset: float = float(_wheel_track_source_offset.get(key, wheel.position.y - (base_local.y + bias_y)))
		entries.append({"z":base_local.z, "offset":source_offset})
	if entries.is_empty():
		return terrain_samples.duplicate()

	for i in range(entries.size()):
		for j in range(i + 1, entries.size()):
			if float(entries[j]["z"]) < float(entries[i]["z"]):
				var tmp: Dictionary = entries[i]
				entries[i] = entries[j]
				entries[j] = tmp

	var samples: Array[float] = []
	if entries.size() == 1:
		var only_value: float = float(entries[0]["offset"]) * 1.16
		for _unused_index in range(TRACK_DEFORM_SAMPLES):
			samples.append(only_value)
	else:
		var min_z: float = float(entries[0]["z"])
		var max_z: float = float(entries[entries.size() - 1]["z"])
		var sample_denominator: float = maxf(float(TRACK_DEFORM_SAMPLES - 1), 1.0)
		for sample_index in range(TRACK_DEFORM_SAMPLES):
			var wanted_z: float = lerpf(min_z, max_z, float(sample_index) / sample_denominator)
			var value: float = float(entries[0]["offset"])
			for entry_index in range(entries.size() - 1):
				var a: Dictionary = entries[entry_index]
				var b: Dictionary = entries[entry_index + 1]
				var za: float = float(a["z"])
				var zb: float = float(b["z"])
				if wanted_z <= zb or entry_index == entries.size() - 2:
					var blend: float = clampf((wanted_z - za) / maxf(zb - za, 0.0001), 0.0, 1.0)
					value = lerpf(float(a["offset"]), float(b["offset"]), blend)
					break
			samples.append(value * 1.16)

	# A continuous belt distributes wheel movement to neighbours. v18.0 uses more
	# sample points than v17.x and also diffuses each point over the next two nodes,
	# so the lower run no longer kinks sharply between adjacent road wheels.
	for _pass_index in range(3):
		var spread: Array[float] = []
		for spread_index in range(TRACK_DEFORM_SAMPLES):
			var value: float = samples[spread_index] * 0.44
			var weight: float = 0.44
			if spread_index > 0:
				value += samples[spread_index - 1] * 0.22
				weight += 0.22
			if spread_index < TRACK_DEFORM_SAMPLES - 1:
				value += samples[spread_index + 1] * 0.22
				weight += 0.22
			if spread_index > 1:
				value += samples[spread_index - 2] * 0.06
				weight += 0.06
			if spread_index < TRACK_DEFORM_SAMPLES - 2:
				value += samples[spread_index + 2] * 0.06
				weight += 0.06
			spread.append(value / weight)
		samples = spread

	var travel: float = float(_cfg().get("suspension_travel", 0.18))
	var visual_step: float = float(_cfg().get("step_height", 0.85))
	var gear_drop: float = float(_cfg().get("running_gear_drop", 0.0))
	# Lowering the neutral belt by gear_drop creates exactly that much additional
	# upward room before it reaches the old v17.8 hull envelope.
	var up_limit: float = travel * 1.05 + visual_step * 0.10 + gear_drop
	var down_limit: float = travel * 0.62
	for sample_index in range(samples.size()):
		samples[sample_index] = clampf(samples[sample_index], -down_limit, up_limit)
		# Terrain is a one-sided constraint: wheels may hold the belt above a hollow,
		# but no wheel animation is allowed to pull it below a sampled ground surface.
		if terrain_samples.size() >= TRACK_DEFORM_SAMPLES:
			samples[sample_index] = maxf(samples[sample_index], terrain_samples[sample_index])
	return samples

func _smooth_track_deform(current: Array[float], target: Array[float], terrain_floor: Array[float], delta: float) -> Array[float]:
	var result: Array[float] = []
	if target.size() < TRACK_DEFORM_SAMPLES:
		return result
	var response: float = clampf(delta * 6.8, 0.0, 1.0)
	var max_step: float = maxf(delta * 1.02, 0.001)
	for sample_index in range(TRACK_DEFORM_SAMPLES):
		var from_value: float = float(current[sample_index]) if current.size() >= TRACK_DEFORM_SAMPLES else 0.0
		var target_value: float = float(target[sample_index])
		var blended: float = lerpf(from_value, target_value, response)
		var value: float = move_toward(from_value, blended, max_step)
		# Temporal smoothing is never allowed to lag *through* the ground when the tank
		# suddenly reaches a curb. Upward correction to the contact plane is immediate;
		# all unconstrained motion stays smoothed.
		if terrain_floor.size() >= TRACK_DEFORM_SAMPLES:
			value = maxf(value, terrain_floor[sample_index])
		result.append(value)
	return result

func _apply_track_deform(materials: Array[ShaderMaterial], samples: Array[float], uv_scroll: float) -> void:
	if samples.size() < TRACK_DEFORM_SAMPLES:
		return
	for mat in materials:
		if mat == null:
			continue
		mat.set_shader_parameter("uv_scroll", uv_scroll)
		for sample_index in range(TRACK_DEFORM_SAMPLES):
			mat.set_shader_parameter("deform_%d" % sample_index, samples[sample_index])

func _enforce_wheel_inside_track(wheels: Array[Node3D], samples: Array[float]) -> void:
	if samples.size() < TRACK_DEFORM_SAMPLES or wheels.is_empty():
		return
	# Samples are parameterised by the primary road-wheel span. Keep that same span,
	# but constrain *every* wheel (including the large idler/sprocket wheels). v18.16
	# only corrected whL/whR_1_*; the large end wheels seen in the screenshots could
	# therefore still leak below the belt even while all road wheels were correct.
	var min_z: float = 999999.0
	var max_z: float = -999999.0
	var primary_count: int = 0
	for wheel in wheels:
		if wheel == null or not _is_primary_road_wheel(wheel):
			continue
		var key: int = wheel.get_instance_id()
		var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
		min_z = minf(min_z, base_local.z)
		max_z = maxf(max_z, base_local.z)
		primary_count += 1
	if primary_count <= 0:
		return

	var cfg: Dictionary = _cfg()
	var gear_drop: float = float(cfg.get("running_gear_drop", 0.0))
	var neutral_track_y: float = (_visual_root.position.y if _visual_root != null else 0.03) - gear_drop
	var span: float = maxf(max_z - min_z, 0.0001)
	var up_world: Vector3 = global_basis.y.normalized()
	for wheel in wheels:
		if wheel == null:
			continue
		var key: int = wheel.get_instance_id()
		var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
		var t: float = clampf((base_local.z - min_z) / span, 0.0, 1.0)
		var sample_x: float = t * float(TRACK_DEFORM_SAMPLES - 1)
		var i0: int = clampi(int(floor(sample_x)), 0, TRACK_DEFORM_SAMPLES - 1)
		var i1: int = mini(i0 + 1, TRACK_DEFORM_SAMPLES - 1)
		var blend: float = sample_x - float(i0)
		var belt_offset: float = lerpf(float(samples[i0]), float(samples[i1]), blend)
		var visual_radius: float = maxf(float(cfg.get("wheel_radius", 0.30)), float(_wheel_visual_radius.get(key, 0.30)))
		var is_road: bool = _is_primary_road_wheel(wheel)
		# Give the wheel a real overlap reserve inside the belt, not a tangent contact.
		# End wheels get a slightly smaller correction because the belt wraps upward there,
		# while road wheels need the strongest guard against obstacle-induced droop.
		var inset_ratio: float = 0.34 if is_road else 0.27
		var belt_inset: float = clampf(visual_radius * inset_ratio, 0.080, 0.155)
		var required_center_y: float = neutral_track_y + belt_offset + visual_radius + belt_inset
		var wheel_local_to_tank: Vector3 = global_transform.affine_inverse() * wheel.global_position
		if wheel_local_to_tank.y < required_center_y:
			var lift: float = required_center_y - wheel_local_to_tank.y
			wheel.global_position += up_world * lift

func _update_track_animation(delta: float) -> void:
	var scroll_rate: float = float(_cfg()["track_scroll_rate"])
	_track_drive_intensity = maxf(absf(_left_track_visual_speed), absf(_right_track_visual_speed))
	_left_track_uv_offset += _left_track_visual_speed * scroll_rate * delta
	_right_track_uv_offset += _right_track_visual_speed * scroll_rate * delta
	# Keep the values bounded so a long-running server session cannot lose UV float
	# precision after hours of track scrolling.
	_left_track_uv_offset = fposmod(_left_track_uv_offset, 1.0)
	_right_track_uv_offset = fposmod(_right_track_uv_offset, 1.0)
	var left_terrain_floor: Array[float] = _track_surface_samples(_left_wheels)
	var right_terrain_floor: Array[float] = _track_surface_samples(_right_wheels)
	var left_target_deform: Array[float] = _track_deform_samples(_left_wheels, _left_track_speed, left_terrain_floor)
	var right_target_deform: Array[float] = _track_deform_samples(_right_wheels, _right_track_speed, right_terrain_floor)
	_left_track_deform = _smooth_track_deform(_left_track_deform, left_target_deform, left_terrain_floor, delta)
	_right_track_deform = _smooth_track_deform(_right_track_deform, right_target_deform, right_terrain_floor, delta)
	_apply_track_deform(_left_track_mats, _left_track_deform, _left_track_uv_offset)
	_apply_track_deform(_right_track_mats, _right_track_deform, _right_track_uv_offset)
	# Final render-space guard: once the lower belt shape is known, seat road wheels
	# behind it. This closes the last leak visible on steep/softened obstacle edges.
	_enforce_wheel_inside_track(_left_wheels, _left_track_deform)
	_enforce_wheel_inside_track(_right_wheels, _right_track_deform)

func _start_wreck_fire(duration: float) -> void:
	_wreck_fire_remaining = maxf(duration, 0.0)
	_wreck_fire_emit_elapsed = 0.12
	_wreck_fire_light_elapsed = 0.22

func _update_wreck_fire_fx(delta: float) -> void:
	if _wreck_fire_remaining <= 0.0:
		return
	_wreck_fire_remaining = maxf(0.0, _wreck_fire_remaining - delta)
	_wreck_fire_emit_elapsed += delta
	_wreck_fire_light_elapsed += delta
	var fade := clampf(_wreck_fire_remaining / 2.45, 0.0, 1.0)
	var interval := lerpf(0.15, 0.075, fade)
	var fire_transform: Transform3D = global_transform
	if _wreck_body_debris != null and is_instance_valid(_wreck_body_debris):
		fire_transform = _wreck_body_debris.global_transform
	var size_value: Vector3 = _cfg()["size"]
	while _wreck_fire_emit_elapsed >= interval:
		_wreck_fire_emit_elapsed -= interval
		for flame_index in range(2):
			var local_offset := Vector3(
				randf_range(-size_value.x * 0.30, size_value.x * 0.30),
				randf_range(size_value.y * 0.38, size_value.y * 0.82),
				randf_range(-size_value.z * 0.30, size_value.z * 0.30)
			)
			var world_pos := fire_transform * local_offset
			_spawn_sheet_fx(
				"res://assets/effects/fire_rgba.png", world_pos, 32, 47,
				randf_range(0.38, 0.58), randf_range(0.70, 1.00) * (0.72 + fade * 0.28),
				randf_range(1.35, 2.10) * (0.70 + fade * 0.30),
				Vector3.UP * randf_range(0.48, 0.92), Vector3.UP * 0.075,
				0.90 * fade + 0.08, 0.62, randf_range(-0.38, 0.38)
			)
		if randf() < 0.46:
			var smoke_local := Vector3(
				randf_range(-size_value.x * 0.24, size_value.x * 0.24), size_value.y * 0.80,
				randf_range(-size_value.z * 0.24, size_value.z * 0.24)
			)
			_spawn_sheet_fx(
				"res://assets/effects/smoky_rgba.png", fire_transform * smoke_local, 0, 15,
				randf_range(0.90, 1.30), 0.72, 1.85, Vector3.UP * randf_range(0.55, 0.95),
				Vector3.UP * 0.02, 0.36 * fade + 0.08, 0.18, randf_range(-0.12, 0.12),
				Color(0.34, 0.29, 0.25, 1.0)
			)
	if _wreck_fire_light_elapsed >= 0.28:
		_wreck_fire_light_elapsed = 0.0
		var light_pos := fire_transform * Vector3(0.0, size_value.y * 0.70, 0.0)
		_spawn_flash_light(light_pos, Color(1.0, 0.20, 0.025), 2.1 * fade + 0.7, 4.8, 0.34, false)

func _update_burn_fx(delta: float) -> void:
	if combat_burn <= 0.02 or not combat_alive:
		_burn_emit_elapsed = 0.0
		_burn_light_elapsed = 0.0
		return
	_burn_emit_elapsed += delta
	_burn_light_elapsed += delta
	var interval: float = lerpf(0.090, 0.034, combat_burn)
	while _burn_emit_elapsed >= interval:
		_burn_emit_elapsed -= interval
		var size_value: Vector3 = _cfg()["size"]
		# Several independent seats make afterburn read as a vehicle on fire, not a
		# single billboard hovering over the turret.
		for flame_index in range(4):
			var local_offset := Vector3(
				randf_range(-size_value.x * 0.40, size_value.x * 0.40),
				randf_range(size_value.y * 0.42, size_value.y * 1.08),
				randf_range(-size_value.z * 0.39, size_value.z * 0.39)
			)
			var world_pos: Vector3 = global_transform * local_offset
			_spawn_sheet_fx(
				"res://assets/effects/fire_rgba.png",
				world_pos,
				32,
				47,
				randf_range(0.40, 0.66),
				0.78 + combat_burn * 0.58,
				1.72 + combat_burn * 1.35,
				Vector3.UP * randf_range(0.62, 1.22),
				Vector3.UP * 0.10,
				0.98,
				0.62,
				randf_range(-0.50, 0.50)
			)
			if randf() < 0.48:
				_spawn_sheet_fx(
					"res://assets/effects/firebird_rgba_clean.png",
					world_pos + Vector3.UP * 0.10,
					16,
					31,
					randf_range(0.34, 0.54),
					0.56,
					1.48,
					Vector3.UP * randf_range(0.50, 0.92),
					Vector3.UP * 0.055,
					0.90,
					0.62,
					randf_range(-0.30, 0.30)
				)
		if randf() < 0.62:
			var smoke_offset := Vector3(randf_range(-size_value.x * 0.29, size_value.x * 0.29), size_value.y * 0.94, randf_range(-size_value.z * 0.29, size_value.z * 0.29))
			var smoke_pos: Vector3 = global_transform * smoke_offset
			_spawn_sheet_fx("res://assets/effects/smoky_rgba.png", smoke_pos, 0, 15, randf_range(1.05, 1.50), 0.82, 2.25, Vector3.UP * randf_range(0.78, 1.28), Vector3.UP * 0.025, 0.54, 0.16, randf_range(-0.14, 0.14), Color(0.28, 0.25, 0.23, 1.0))
	if _burn_light_elapsed >= 0.20:
		_burn_light_elapsed = 0.0
		var burn_size: Vector3 = _cfg()["size"]
		_spawn_flash_light(global_position + Vector3.UP * (burn_size.y * 0.82), Color(1.0, 0.22, 0.025), 3.4 + combat_burn * 4.2, 6.2, 0.30)

func _update_audio_and_fx() -> void:
	var fx_delta := get_physics_process_delta_time()
	_update_wreck_fire_fx(fx_delta)
	_update_burn_fx(fx_delta)
	_update_combat_hud()
	var moving := _track_drive_intensity > 0.12 or absf(current_speed) > 0.25
	if _move_audio != null and _move_audio.stream != null:
		if moving and not _move_audio.playing:
			_move_audio.play()
		if not moving and _move_audio.playing:
			_move_audio.stop()
		var motion_mix := clampf(maxf(_track_drive_intensity, absf(current_speed) / MAX_SPEED), 0.0, 1.0)
		_move_audio.volume_db = lerpf(-22.0, -7.0, motion_mix)
	if moving != _last_moving and _oneshot_audio != null:
		var path := "res://assets/sounds/startmoving.mp3" if moving else "res://assets/sounds/endmoving.mp3"
		_oneshot_audio.stream = load(path)
		if _oneshot_audio.stream != null:
			_oneshot_audio.play()
	_last_moving = moving
	var turret_pressed := local_control and (Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_X))
	if _turret_audio != null and _turret_audio.stream != null:
		if turret_pressed and not _turret_audio.playing:
			_turret_audio.play()
		if not turret_pressed and _turret_audio.playing:
			_turret_audio.stop()
	var is_firebird := String(_cfg()["weapon"]) == "firebird"
	if is_firebird and firing:
		_emit_firebird_stream(get_physics_process_delta_time())
		var flame_phase: float = float(Time.get_ticks_msec()) * 0.026
		var flame_forward: Vector3 = -_turret_root.global_basis.z.normalized()
		var flame_origin: Vector3 = _muzzle.global_position
		if _flame_light != null:
			_flame_light.global_position = flame_origin + flame_forward * 1.05 + Vector3.UP * 0.12
			_flame_light.light_energy = 12.5 + sin(flame_phase) * 1.8
		if _flame_fill_light != null:
			_flame_fill_light.global_position = flame_origin + flame_forward * 9.5 + Vector3.UP * 0.34
			_flame_fill_light.light_energy = 8.8 + sin(flame_phase * 0.83 + 1.2) * 1.25
	else:
		_firebird_emit_elapsed = 0.0
		if _flame_light != null:
			_flame_light.light_energy = 0.0
		if _flame_fill_light != null:
			_flame_fill_light.light_energy = 0.0
	if is_firebird and _shot_audio != null and _shot_audio.stream != null:
		if firing and not _shot_audio.playing:
			_shot_audio.play()
		if not firing and _shot_audio.playing:
			_shot_audio.stop()
