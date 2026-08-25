extends RigidBody3D
class_name TankActor

const SheetEffectScript = preload("res://scripts/sheet_effect.gd")

var player_id: int = -1
var slot: int = -1
var local_control: bool = false
var network: TankiNetworkClient

var turret_yaw: float = 0.0
var current_speed: float = 0.0
var firing: bool = false
var _fire_down: bool = false
var _fire_cooldown: float = 0.0
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
var _spring: SpringArm3D
var _camera_rig: Node3D
var _flame_root: Node3D
var _flame_light: OmniLight3D
var _firebird_emit_elapsed: float = 0.0
var _idle_audio: AudioStreamPlayer3D
var _move_audio: AudioStreamPlayer3D
var _turret_audio: AudioStreamPlayer3D
var _oneshot_audio: AudioStreamPlayer3D
var _shot_audio: AudioStreamPlayer3D

var _left_track_speed: float = 0.0
var _right_track_speed: float = 0.0
var _track_drive_intensity: float = 0.0
var _left_track_mats: Array[StandardMaterial3D] = []
var _right_track_mats: Array[StandardMaterial3D] = []
var _left_wheels: Array[Node3D] = []
var _right_wheels: Array[Node3D] = []
var _wheel_local_pos: Dictionary = {}
var _wheel_local_rot: Dictionary = {}
var _wheel_spin: Dictionary = {}
var _turn_velocity: float = 0.0
var _last_speed_for_rock: float = 0.0
var _rock_pitch: float = 0.0
var _rock_velocity: float = 0.0
var _step_grace: float = 0.0
var _ground_contacts: int = 0
var _drive_input: int = 0
var _turn_input: int = 0
var _suspension_points: Array[Dictionary] = []

const MAX_SPEED := 8.0 # Original demo conMaxSpeed=800 cm/s.
const DRIVE_ACCEL := 1.65 # normalized track speed / sec
const COAST_DECEL := 0.52
const SERVICE_BRAKE := 2.35
const TURN_INPUT_SCALE := 0.34
const WORLD_GRAVITY := 9.8
const CAMERA_MIN_X := -38.0
const CAMERA_MAX_X := -6.0

func configure(id_: int, slot_: int, is_local: bool, net: TankiNetworkClient) -> void:
    player_id = id_
    slot = slot_
    local_control = is_local
    network = net
    name = "Tank_%d" % player_id
    _build_body()
    _build_visuals()
    _rebuild_suspension_points()
    _build_audio()
    freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
    freeze = not local_control
    sleeping = false
    if local_control:
        _build_camera()

func _cfg() -> Dictionary:
    match slot:
        0:
            return {
                "label":"Wasp M2 + Smoky M2",
                "hull":"res://assets/hulls/wasp_m2.dae",
                "turret":"res://assets/turrets/smoky_m2.obj",
                "weapon":"smoky",
                "tint":Color("#d7d9cc"),
                "size":Vector3(3.0,1.35,4.8),
                "turret_mount":Vector3(0.0,2.2317,1.3210),
                "muzzle":Vector3(0.0015,0.4657,-3.7172),
                "hull_albedo":"res://assets/tank_textures/wasp_m2/albedo.png",
                "track_albedo":"res://assets/tank_textures/wasp_m2/tracks_diffuse.png",
                "turret_albedo":"res://assets/tank_textures/smoky_m2/albedo.png",
                "suspension_rest":0.34,
                "suspension_travel":0.12,
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
                "physics_mass":4.0,
                "suspension_k":55.0,
                "suspension_damping":9.0,
                "drive_gain":0.040,
                "lateral_gain":0.22
            }
        1:
            return {
                "label":"Viking M1 + Firebird M1",
                "hull":"res://assets/hulls/viking_m1.dae",
                "turret":"res://assets/turrets/firebird_m1.obj",
                "weapon":"firebird",
                "tint":Color("#dccca8"),
                "size":Vector3(4.1,1.55,6.1),
                "turret_mount":Vector3(0.0070,1.6924,0.4725),
                "muzzle":Vector3(0.0015,0.5230,-4.1959),
                "hull_albedo":"res://assets/tank_textures/viking_m1/albedo.png",
                "track_albedo":"res://assets/tank_textures/viking_m1/tracks_diffuse.png",
                "turret_albedo":"res://assets/tank_textures/firebird_m1/albedo.png",
                "suspension_rest":0.42,
                "suspension_travel":0.095,
                "wheel_radius":0.33,
                "track_scroll_rate":0.88,
                "turn_in_place":1.72,
                "turn_running":0.86,
                "ground_probe_height":2.2,
                "ground_probe_depth":4.8,
                "step_height":0.94,
                "step_probe":0.70,
                "rock_strength":0.00105,
                "wheel_bias_y":0.075,
                "physics_mass":5.8,
                "suspension_k":68.0,
                "suspension_damping":10.5,
                "drive_gain":0.038,
                "lateral_gain":0.24
            }
        _:
            return {
                "label":"Mamont M3 + Thunder M3",
                "hull":"res://assets/hulls/mamont_m3.dae",
                "turret":"res://assets/turrets/thunder_m3.obj",
                "weapon":"thunder",
                "tint":Color("#f0ede0"),
                "size":Vector3(4.7,1.75,7.2),
                "turret_mount":Vector3(0.0,2.2787,-1.0971),
                "muzzle":Vector3(0.0015,0.6696,-4.1718),
                "hull_albedo":"res://assets/tank_textures/mamont_m3/albedo.png",
                "track_albedo":"res://assets/tank_textures/mamont_m3/tracks_diffuse.png",
                "turret_albedo":"res://assets/tank_textures/thunder_m3/albedo.png",
                "suspension_rest":0.54,
                "suspension_travel":0.15,
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
                "physics_mass":8.4,
                "suspension_k":82.0,
                "suspension_damping":12.5,
                "drive_gain":0.035,
                "lateral_gain":0.27
            }

func _build_body() -> void:
    var cfg: Dictionary = _cfg()
    var s: Vector3 = cfg["size"]
    mass = float(cfg["physics_mass"])
    gravity_scale = 1.0
    linear_damp = 0.18
    angular_damp = 1.35
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 24
    can_sleep = true
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    center_of_mass = Vector3(0.0, s.y * 0.34, 0.0)

    var physical_material := PhysicsMaterial.new()
    physical_material.friction = 0.92
    physical_material.bounce = 0.0
    physics_material_override = physical_material

    var collision := CollisionShape3D.new()
    collision.name = "PhysicsCollision"
    var shape := BoxShape3D.new()
    # The collision volume is deliberately tucked inside the track silhouette.
    # Suspension rays support the tank; this box handles hard contacts, walls and rollovers.
    shape.size = Vector3(s.x * 0.72, s.y * 0.82, s.z * 0.68)
    collision.position.y = s.y * 0.47
    collision.shape = shape
    add_child(collision)

func _build_visuals() -> void:
    var cfg: Dictionary = _cfg()
    var tint: Color = cfg["tint"]
    var hull_albedo: String = String(cfg["hull_albedo"])
    var track_albedo: String = String(cfg["track_albedo"])
    var turret_albedo: String = String(cfg["turret_albedo"])
    var hull_dir: String = hull_albedo.get_base_dir()
    var track_dir: String = track_albedo.get_base_dir()
    var turret_dir: String = turret_albedo.get_base_dir()
    var hull_roughness: String = hull_dir + "/roughness.png"
    var hull_metallic: String = hull_dir + "/metallic.png"
    var hull_normal: String = hull_dir + "/detail_normal.png"
    var track_roughness: String = track_dir + "/tracks_roughness.png"
    var track_metallic: String = track_dir + "/tracks_metallic.png"
    var track_normal: String = track_dir + "/tracks_detail_normal.png"
    var turret_roughness: String = turret_dir + "/roughness.png"
    var turret_metallic: String = turret_dir + "/metallic.png"
    var turret_normal: String = turret_dir + "/detail_normal.png"

    _visual_root = Node3D.new()
    _visual_root.name = "VisualRoot"
    _visual_root.position.y = 0.03
    add_child(_visual_root)

    # The running gear follows the terrain but never receives acceleration/braking
    # rocking. The hull/turret get a small extra spring pitch on top of it.
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
        _prepare_hull_import(imported, hull_albedo, hull_roughness, hull_metallic, hull_normal, track_albedo, track_roughness, track_metallic, track_normal)
        var mount_node: Node = _find_named_recursive(imported, "mount")
        if mount_node is Node3D:
            turret_position = _body_rock_root.to_local((mount_node as Node3D).global_position)
        _move_hull_mesh_to_sprung_body(imported)
    else:
        _build_hull_fallback(cfg, tint, hull_albedo, hull_roughness, hull_metallic, hull_normal)

    _turret_root = Node3D.new()
    _turret_root.name = "Turret"
    _turret_root.position = turret_position
    _body_rock_root.add_child(_turret_root)

    var turret_resource: Resource = load(String(cfg["turret"]))
    if turret_resource is Mesh:
        var turret_mesh := MeshInstance3D.new()
        turret_mesh.name = "OriginalTurretMesh"
        turret_mesh.mesh = turret_resource as Mesh
        turret_mesh.material_override = _material(Color.WHITE, turret_albedo, 0.48, 0.26, turret_roughness, turret_metallic, turret_normal, 0.42)
        _turret_root.add_child(turret_mesh)
    elif turret_resource is PackedScene:
        var turret_scene: Node = (turret_resource as PackedScene).instantiate()
        _turret_root.add_child(turret_scene)
        _apply_tint(turret_scene, Color.WHITE, turret_albedo, turret_roughness, turret_metallic, turret_normal, 0.42)
    else:
        _build_turret_fallback(tint, turret_albedo, turret_roughness, turret_metallic, turret_normal)

    _muzzle = Marker3D.new()
    _muzzle.name = "Muzzle"
    _muzzle.position = cfg["muzzle"]
    _turret_root.add_child(_muzzle)
    _build_flame()
    _build_muzzle_soot()
    # Store an unrocked root-space pivot for the camera. It will follow turret yaw,
    # but not suspension/body pitch-roll.
    _camera_anchor_base = to_local(_turret_root.global_position)

func _build_hull_fallback(cfg: Dictionary, tint: Color, albedo_path: String, roughness_path: String, metallic_path: String, normal_path: String) -> void:
    var fallback := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = cfg["size"]
    fallback.mesh = mesh
    var fallback_size: Vector3 = cfg["size"]
    fallback.position.y = fallback_size.y * 0.5
    fallback.material_override = _material(tint, albedo_path, 0.80, 0.08, roughness_path, metallic_path, normal_path, 0.26)
    _body_rock_root.add_child(fallback)

func _build_turret_fallback(tint: Color, albedo_path: String, roughness_path: String, metallic_path: String, normal_path: String) -> void:
    var turret := MeshInstance3D.new()
    var turret_mesh := BoxMesh.new()
    turret_mesh.size = Vector3(1.8,0.65,2.2)
    turret.mesh = turret_mesh
    turret.position.y = 0.25
    turret.material_override = _material(tint, albedo_path, 0.76, 0.10, roughness_path, metallic_path, normal_path, 0.30)
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

func _prepare_hull_import(
    node: Node,
    hull_texture: String,
    hull_roughness: String,
    hull_metallic: String,
    hull_normal: String,
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
        if is_render_part:
            if is_track:
                var tmat := _material(Color.WHITE, track_texture, 0.96, 0.02, track_roughness, track_metallic, track_normal, 0.26)
                tmat.uv1_scale = Vector3(1.0, 2.2, 1.0)
                mesh_node.material_override = tmat
                if part_name == "ltrack":
                    _left_track_mats.append(tmat)
                else:
                    _right_track_mats.append(tmat)
            else:
                mesh_node.material_override = _material(Color.WHITE, hull_texture, 0.78, 0.10, hull_roughness, hull_metallic, hull_normal, 0.26)
        if is_wheel:
            var wheel := mesh_node as Node3D
            var key := wheel.get_instance_id()
            _wheel_local_pos[key] = wheel.position
            _wheel_local_rot[key] = wheel.rotation
            _wheel_spin[key] = 0.0
            if part_name.begins_with("whl_"):
                _left_wheels.append(wheel)
            else:
                _right_wheels.append(wheel)
    for child in node.get_children():
        _prepare_hull_import(child, hull_texture, hull_roughness, hull_metallic, hull_normal, track_texture, track_roughness, track_metallic, track_normal)

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

func _apply_tint(node: Node, color: Color, albedo_path: String, roughness_path: String, metallic_path: String, normal_path: String, normal_scale_value: float = 0.30) -> void:
    if node is MeshInstance3D:
        (node as MeshInstance3D).material_override = _material(color, albedo_path, 0.76, 0.10, roughness_path, metallic_path, normal_path, normal_scale_value)
    for child in node.get_children():
        _apply_tint(child, color, albedo_path, roughness_path, metallic_path, normal_path, normal_scale_value)

func _find_named_recursive(node: Node, wanted: String) -> Node:
    if String(node.name).to_lower() == wanted.to_lower():
        return node
    for child in node.get_children():
        var found: Node = _find_named_recursive(child, wanted)
        if found != null:
            return found
    return null

func _rebuild_suspension_points() -> void:
    _suspension_points.clear()
    var cfg: Dictionary = _cfg()
    var travel: float = float(cfg["suspension_travel"])
    var radius: float = float(cfg["wheel_radius"])
    var k: float = float(cfg["suspension_k"])
    var wheel_count := max(1, _left_wheels.size() + _right_wheels.size())
    var static_sag := (mass * WORLD_GRAVITY) / (float(wheel_count) * maxf(k, 1.0))

    _append_suspension_from_wheels(_left_wheels, -1.0, travel, radius, static_sag)
    _append_suspension_from_wheels(_right_wheels, 1.0, travel, radius, static_sag)

    if _suspension_points.is_empty():
        var s: Vector3 = cfg["size"]
        for side in [-1.0, 1.0]:
            for z_factor in [-0.34, -0.17, 0.0, 0.17, 0.34]:
                var wheel_center := Vector3(side * s.x * 0.31, radius + 0.08, float(z_factor) * s.z)
                _suspension_points.append({
                    "anchor": wheel_center + Vector3.UP * travel,
                    "side": side,
                    "max_len": radius + travel + static_sag,
                    "static_sag": static_sag
                })

func _append_suspension_from_wheels(wheels: Array[Node3D], side: float, travel: float, radius: float, static_sag: float) -> void:
    for wheel in wheels:
        if wheel == null:
            continue
        var wheel_local := to_local(wheel.global_position)
        _suspension_points.append({
            "anchor": wheel_local + Vector3.UP * travel,
            "side": side,
            "max_len": radius + travel + static_sag,
            "static_sag": static_sag
        })

func teleport_spawn(spawn_transform: Transform3D) -> void:
    global_transform = spawn_transform
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
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
    # Firebird's visible stream is emitted from the original sprite sheet at
    # runtime. Keep only a lightweight muzzle container/light here.
    _flame_root = Node3D.new()
    _flame_root.name = "FlamethrowerEmitter"
    _muzzle.add_child(_flame_root)
    _flame_light = OmniLight3D.new()
    _flame_light.name = "FlameLight"
    _flame_light.light_color = Color(1.0, 0.48, 0.14)
    _flame_light.light_energy = 0.0
    _flame_light.omni_range = 7.5
    _flame_light.shadow_enabled = false
    _flame_root.add_child(_flame_light)

func _build_audio() -> void:
    _idle_audio = _audio("res://assets/sounds/engineidle.mp3", true, -13.0)
    _move_audio = _audio("res://assets/sounds/move.mp3", true, -22.0)
    _turret_audio = _audio("res://assets/sounds/turret.mp3", true, -18.0)
    _oneshot_audio = _audio("", false, -8.0)
    var weapon_name: String = String(_cfg()["weapon"])
    var sound_folder: String = "flamethrower" if weapon_name == "firebird" else weapon_name
    var shot_path := "res://assets/sounds/%s/shot.mp3" % sound_folder
    _shot_audio = _audio(shot_path, weapon_name == "firebird", -5.0)
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

func apply_network_state(state: Dictionary) -> void:
    var p = state.get("p", null)
    if p is Array and p.size() >= 3:
        _target_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
        if not _has_target:
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
    if local_control:
        _read_local_controls(delta)
        _apply_suspension_and_track_forces(delta)
        _apply_climb_assist(delta)
        current_speed = linear_velocity.dot(-global_basis.z.normalized())
        _state_elapsed += delta
        if _state_elapsed >= 0.05:
            _state_elapsed = 0.0
            _send_state()
    else:
        _remote_interpolation(delta)

    _update_visual_pose(delta)
    _update_wheel_suspension(delta)
    _update_track_animation(delta)
    _turret_root.rotation.y = turret_yaw
    _update_stable_camera_pivot()
    _update_audio_and_fx()

func _read_local_controls(delta: float) -> void:
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

    var turn_command := float(_turn_input) * TURN_INPUT_SCALE
    var left_target := clampf(float(_drive_input) - turn_command, -1.0, 1.0)
    var right_target := clampf(float(_drive_input) + turn_command, -1.0, 1.0)
    _left_track_speed = _approach_track_speed(_left_track_speed, left_target, _drive_input, delta)
    _right_track_speed = _approach_track_speed(_right_track_speed, right_target, _drive_input, delta)
    if _turn_input == 0:
        _damp_track_differential(delta)

    var turret_input := 0
    if Input.is_key_pressed(KEY_Z):
        turret_input += 1
    if Input.is_key_pressed(KEY_X):
        turret_input -= 1
    turret_yaw += float(turret_input) * 2.0 * delta

    _handle_fire()
    if _spring != null:
        if Input.is_key_pressed(KEY_PAGEUP):
            _spring.rotation.x = clampf(_spring.rotation.x - delta * 0.6, deg_to_rad(CAMERA_MIN_X), deg_to_rad(CAMERA_MAX_X))
        if Input.is_key_pressed(KEY_PAGEDOWN):
            _spring.rotation.x = clampf(_spring.rotation.x + delta * 0.6, deg_to_rad(CAMERA_MIN_X), deg_to_rad(CAMERA_MAX_X))

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
    differential = move_toward(differential, 0.0, 1.55 * delta)
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
    var up := global_basis.y.normalized()
    var down := -up
    var forward_raw := -global_basis.z.normalized()
    var side_raw := global_basis.x.normalized()
    var space := get_world_3d().direct_space_state
    _ground_contacts = 0

    for point in _suspension_points:
        var anchor_local: Vector3 = point["anchor"]
        var anchor_world: Vector3 = global_transform * anchor_local
        var max_len: float = float(point["max_len"])
        var query := PhysicsRayQueryParameters3D.create(anchor_world, anchor_world + down * (max_len + 0.12))
        query.exclude = [get_rid()]
        var hit := space.intersect_ray(query)
        if hit.is_empty():
            continue

        var hit_pos: Vector3 = hit["position"]
        var hit_normal: Vector3 = hit["normal"]
        hit_normal = hit_normal.normalized()
        var distance := anchor_world.distance_to(hit_pos)
        var compression := maxf(0.0, max_len - distance)
        if compression <= 0.0:
            continue
        _ground_contacts += 1

        var offset := hit_pos - global_position
        var point_velocity := linear_velocity + angular_velocity.cross(offset)
        var suspension_speed := point_velocity.dot(up)
        var spring_force := compression * spring_k - suspension_speed * spring_damping
        spring_force = clampf(spring_force, 0.0, mass * WORLD_GRAVITY * 0.85)
        apply_force(up * spring_force, offset)

        var forward := forward_raw.slide(hit_normal)
        var side := side_raw.slide(hit_normal)
        if forward.length_squared() > 0.001:
            forward = forward.normalized()
        if side.length_squared() > 0.001:
            side = side.normalized()

        var track_speed: float = _left_track_speed if float(point["side"]) < 0.0 else _right_track_speed
        var target_speed := track_speed * MAX_SPEED
        var forward_speed := point_velocity.dot(forward)
        var drive_force := (target_speed - forward_speed) * mass * drive_gain
        apply_force(forward * drive_force, offset)

        var lateral_speed := point_velocity.dot(side)
        var grip_force := -lateral_speed * mass * lateral_gain
        apply_force(side * grip_force, offset)

func _apply_climb_assist(_delta: float) -> void:
    if _ground_contacts <= 0 or absf((_left_track_speed + _right_track_speed) * 0.5) < 0.12:
        return
    # Do not magically climb while on the side or upside down. In those states the
    # rigid body is deliberately left to gravity/collision and can fully roll over.
    var local_up := global_basis.y.normalized()
    if local_up.dot(Vector3.UP) < 0.45:
        return
    var cfg: Dictionary = _cfg()
    var s: Vector3 = cfg["size"]
    var step_height: float = float(cfg["step_height"])
    var direction_sign := signf((_left_track_speed + _right_track_speed) * 0.5)
    var forward := -global_basis.z.normalized() * direction_sign
    var side := global_basis.x.normalized()
    var space := get_world_3d().direct_space_state
    var front_center := global_position + forward * (s.z * 0.34) + local_up * (s.y * 0.20)

    for lateral in [-0.24, 0.0, 0.24]:
        var lower_from := front_center + side * (s.x * float(lateral))
        var lower_to := lower_from + forward * (float(cfg["step_probe"]) + 0.38)
        var low_query := PhysicsRayQueryParameters3D.create(lower_from, lower_to)
        low_query.exclude = [get_rid()]
        var low_hit := space.intersect_ray(low_query)
        if low_hit.is_empty():
            continue
        var low_normal: Vector3 = low_hit["normal"]
        low_normal = low_normal.normalized()
        if absf(low_normal.dot(Vector3.UP)) > 0.58:
            continue

        var upper_from := lower_from + local_up * step_height
        var upper_to := upper_from + forward * (float(cfg["step_probe"]) + 0.46)
        var high_query := PhysicsRayQueryParameters3D.create(upper_from, upper_to)
        high_query.exclude = [get_rid()]
        if not space.intersect_ray(high_query).is_empty():
            continue

        var contact: Vector3 = low_hit["position"]
        var offset := contact - global_position
        # Force, not teleport: the front suspension unloads and the hull physically
        # rotates onto the ledge. A tall obstacle still blocks the collision box.
        apply_force(local_up * mass * 12.0 + forward * mass * 4.2, offset)
        return

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
    var pressed := Input.is_key_pressed(KEY_SPACE)
    var weapon := String(_cfg()["weapon"])
    if weapon == "firebird":
        firing = pressed
    else:
        firing = false
        if pressed and _fire_cooldown <= 0.0:
            _fire_cooldown = 1.0
            _perform_discrete_shot()
    _fire_down = pressed

func _perform_discrete_shot() -> void:
    if _muzzle == null:
        return
    if _shot_audio.stream != null:
        _shot_audio.play()
    var origin := _muzzle.global_position
    var direction := -_turret_root.global_basis.z.normalized()
    var end := origin + direction * 100.0
    var query := PhysicsRayQueryParameters3D.create(origin, end)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        end = hit["position"]
    _spawn_shot_fx(origin, end, String(_cfg()["weapon"]))
    if network != null:
        network.send_shot({"origin":_v3(origin), "end":_v3(end)})

func play_remote_shot(data: Dictionary) -> void:
    var a = data.get("origin", [])
    var b = data.get("end", [])
    if not (a is Array and b is Array and a.size() >= 3 and b.size() >= 3):
        return
    if _shot_audio != null and _shot_audio.stream != null:
        _shot_audio.play()
    _spawn_shot_fx(Vector3(float(a[0]),float(a[1]),float(a[2])), Vector3(float(b[0]),float(b[1]),float(b[2])), String(data.get("weapon", _cfg()["weapon"])))

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
        _spawn_flash_light(origin, Color(1.0, 0.70, 0.32), 3.4, 5.6, 0.12)
        _spawn_flash_light(end, Color(1.0, 0.42, 0.10), 2.2, 4.4, 0.14)
    else:
        # Thunder must feel like a heavy shell: huge muzzle bloom and a much bigger impact cloud.
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.14, 56, 58, 0.13, 2.80, 5.10, direction * 0.30, Vector3.ZERO, 1.0, 0.75, randf_range(-0.35, 0.35))
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.24, 40, 47, 0.20, 2.55, 4.55, direction * 2.5, Vector3.UP * 0.22, 1.0, 0.66, 0.42)
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", origin + direction * 0.34, 0, 15, 1.05, 1.05, 2.90, direction * 0.90 + Vector3.UP * 1.05, Vector3.UP * 0.15, 0.82, 0.18, -0.16)
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end, 16, 39, 0.70, 3.50, 7.20, Vector3.UP * 0.24, Vector3.UP * 0.16, 1.0, 0.74, 0.25)
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end + Vector3.UP * 0.18, 56, 58, 0.18, 2.85, 4.70, Vector3.ZERO, Vector3.ZERO, 0.94, 0.80, 0.0)
        _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", end + Vector3.UP * 0.28, 0, 15, 1.65, 2.10, 5.90, Vector3.UP * 1.15, Vector3.UP * 0.04, 0.84, 0.14, -0.12)
        _spawn_flash_light(origin, Color(1.0, 0.73, 0.36), 5.8, 8.0, 0.15)
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

func _spawn_flash_light(position: Vector3, color: Color, energy: float, range_m: float, life: float) -> void:
    var root := get_tree().current_scene
    if root == null:
        return
    var light := OmniLight3D.new()
    light.light_color = color
    light.light_energy = energy
    light.omni_range = range_m
    light.shadow_enabled = false
    root.add_child(light)
    light.global_position = position
    var tween := get_tree().create_tween()
    tween.tween_property(light, "light_energy", 0.0, life)
    tween.tween_callback(light.queue_free)

func _emit_firebird_stream(delta: float) -> void:
    if _muzzle == null:
        return
    _firebird_emit_elapsed += delta
    var interval := 0.030
    while _firebird_emit_elapsed >= interval:
        _firebird_emit_elapsed -= interval
        var forward := -_turret_root.global_basis.z.normalized()
        var side := _turret_root.global_basis.x.normalized()
        var up := Vector3.UP
        var base_origin := _muzzle.global_position + forward * 0.26 + up * 0.02

        # Main core jet: much larger, closer to the original Firebird plume.
        var core_jitter := side * randf_range(-0.10, 0.10) + up * randf_range(-0.03, 0.12)
        var core_origin := base_origin + core_jitter
        var core_velocity := forward * randf_range(6.0, 8.0) + up * randf_range(0.35, 0.95) + side * randf_range(-0.18, 0.18)
        _spawn_sheet_fx("res://assets/effects/fire_rgba.png", core_origin, 32, 47, randf_range(0.26, 0.34), randf_range(1.35, 1.70), randf_range(2.95, 3.85), core_velocity, Vector3.UP * 0.26, randf_range(0.92, 1.0), 0.64, randf_range(-0.45, 0.45))

        # Surrounding hotter flame billows.
        var halo_origin := base_origin + side * randf_range(-0.20, 0.20) + up * randf_range(0.00, 0.14)
        var halo_velocity := forward * randf_range(5.4, 7.2) + up * randf_range(0.45, 1.10) + side * randf_range(-0.32, 0.32)
        _spawn_sheet_fx("res://assets/effects/firebird_rgba.png", halo_origin, 16, 31, randf_range(0.30, 0.40), randf_range(1.15, 1.45), randf_range(2.55, 3.30), halo_velocity, Vector3.UP * 0.20, randf_range(0.88, 0.98), 0.58, randf_range(-0.55, 0.55))

        # Occasional fire-ball lick further down the stream.
        if randf() < 0.45:
            var tongue_origin := base_origin + forward * randf_range(0.20, 0.65) + side * randf_range(-0.16, 0.16) + up * randf_range(0.00, 0.10)
            var tongue_velocity := forward * randf_range(4.6, 6.4) + up * randf_range(0.20, 0.65)
            _spawn_sheet_fx("res://assets/effects/firebird_rgba.png", tongue_origin, 48, 63, randf_range(0.24, 0.34), randf_range(0.86, 1.10), randf_range(1.90, 2.55), tongue_velocity, Vector3.UP * 0.14, randf_range(0.84, 0.96), 0.58, randf_range(-0.60, 0.60))

        # Smoke rolls above the flame instead of looking like tiny black dots.
        if randf() < 0.32:
            var smoke_origin := base_origin + forward * randf_range(0.25, 0.85) + up * randf_range(0.28, 0.48)
            var smoke_velocity := forward * randf_range(1.4, 2.2) + up * randf_range(0.90, 1.35)
            _spawn_sheet_fx("res://assets/effects/smoky_rgba.png", smoke_origin, 0, 15, randf_range(0.95, 1.20), randf_range(0.90, 1.20), randf_range(2.25, 3.10), smoke_velocity, Vector3.UP * 0.04, randf_range(0.42, 0.58), 0.18, randf_range(-0.18, 0.18), Color(0.28, 0.24, 0.22, 1.0))


func _send_state() -> void:
    if network == null:
        return
    var q := global_basis.get_rotation_quaternion().normalized()
    network.send_state({
        "slot":slot,
        "p":_v3(global_position),
        "yaw":_body_heading_yaw(),
        "rot":[q.x, q.y, q.z, q.w],
        "lin_vel":_v3(linear_velocity),
        "ang_vel":_v3(angular_velocity),
        "turret":turret_yaw,
        "speed":current_speed,
        "left_track":_left_track_speed,
        "right_track":_right_track_speed,
        "firing":firing
    })

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
    _body_rock_root.rotation.z = lerp_angle(_body_rock_root.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))

func _update_wheel_suspension(delta: float) -> void:
    var rest: float = float(_cfg()["suspension_rest"])
    var travel: float = float(_cfg()["suspension_travel"])
    var radius: float = float(_cfg()["wheel_radius"])
    var bias_y: float = float(_cfg().get("wheel_bias_y", 0.0))
    _update_wheel_side(_left_wheels, _left_track_speed, rest, travel, radius, bias_y, delta)
    _update_wheel_side(_right_wheels, _right_track_speed, rest, travel, radius, bias_y, delta)

func _update_wheel_side(wheels: Array[Node3D], track_speed: float, _rest: float, travel: float, radius: float, bias_y: float, delta: float) -> void:
    var up := global_basis.y.normalized()
    var down := -up
    var k: float = float(_cfg()["suspension_k"])
    var total_wheels := max(1, _left_wheels.size() + _right_wheels.size())
    var static_sag := (mass * WORLD_GRAVITY) / (float(total_wheels) * maxf(k, 1.0))
    var max_len := radius + travel + static_sag
    var space := get_world_3d().direct_space_state
    for wheel in wheels:
        if wheel == null:
            continue
        var key: int = wheel.get_instance_id()
        var base_local: Vector3 = _wheel_local_pos.get(key, wheel.position)
        var base_rot: Vector3 = _wheel_local_rot.get(key, wheel.rotation)
        var parent_node := wheel.get_parent()
        if not (parent_node is Node3D):
            continue
        var parent_3d := parent_node as Node3D
        var base_world := parent_3d.to_global(base_local)
        var anchor_world := base_world + up * travel
        var query := PhysicsRayQueryParameters3D.create(anchor_world, anchor_world + down * (max_len + 0.10))
        query.exclude = [get_rid()]
        var hit := space.intersect_ray(query)
        var suspension_offset := -travel
        if not hit.is_empty():
            var hit_pos: Vector3 = hit["position"]
            var distance := anchor_world.distance_to(hit_pos)
            var compression := clampf(max_len - distance - static_sag, -travel, travel)
            suspension_offset = compression
        var target_y := base_local.y + bias_y + suspension_offset
        wheel.position.y = lerpf(wheel.position.y, target_y, clampf(delta * 12.0, 0.0, 1.0))
        var spin_value: float = float(_wheel_spin.get(key, 0.0))
        spin_value += (track_speed * MAX_SPEED / maxf(radius, 0.01)) * delta
        _wheel_spin[key] = spin_value
        wheel.rotation = Vector3(base_rot.x + spin_value, base_rot.y, base_rot.z)

func _update_track_animation(delta: float) -> void:
    var scroll_rate: float = float(_cfg()["track_scroll_rate"])
    _track_drive_intensity = maxf(absf(_left_track_speed), absf(_right_track_speed))
    for mat in _left_track_mats:
        if mat != null:
            var uv_left: Vector3 = mat.uv1_offset
            uv_left.y += _left_track_speed * scroll_rate * delta
            mat.uv1_offset = uv_left
    for mat in _right_track_mats:
        if mat != null:
            var uv_right: Vector3 = mat.uv1_offset
            uv_right.y += _right_track_speed * scroll_rate * delta
            mat.uv1_offset = uv_right

func _update_audio_and_fx() -> void:
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
        if _flame_light != null:
            _flame_light.light_energy = 2.10 + sin(Time.get_ticks_msec() * 0.026) * 0.42
    else:
        _firebird_emit_elapsed = 0.0
        if _flame_light != null:
            _flame_light.light_energy = 0.0
    if is_firebird and _shot_audio != null and _shot_audio.stream != null:
        if firing and not _shot_audio.playing:
            _shot_audio.play()
        if not firing and _shot_audio.playing:
            _shot_audio.stop()
