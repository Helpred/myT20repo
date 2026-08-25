extends Node3D
class_name ArenaOriginal

const VISUAL_PATH := "res://assets/maps/arena/arena_visual.gltf"
const PHYSICS_PATH := "res://assets/maps/arena/arena_physics.obj"
const LIGHTS_PATH := "res://assets/maps/arena/lights.dae"
const PANORAMA_PATH := "res://assets/maps/arena/skybox/arena_panorama.jpg"

const CHEMICAL_PUDDLES := [
    {"pos": Vector3(-31.0, 0.08, 8.5), "size": Vector2(10.5, 6.0), "rot": deg_to_rad(18.0), "light": 1.25, "range": 10.0},
    {"pos": Vector3(-51.0, 0.08, 13.0), "size": Vector2(7.8, 5.6), "rot": deg_to_rad(-12.0), "light": 0.95, "range": 8.5},
    {"pos": Vector3(-22.0, 0.08, -16.5), "size": Vector2(7.0, 4.6), "rot": deg_to_rad(-30.0), "light": 0.82, "range": 7.2},
    {"pos": Vector3(-57.0, 0.08, -22.0), "size": Vector2(6.8, 4.2), "rot": deg_to_rad(35.0), "light": 0.74, "range": 6.8}
]

func _ready() -> void:
    name = "ArenaV3_Original"
    _build_environment()
    var visual_root := _load_visuals()
    _load_collision()
    _load_original_lights()
    _spawn_chemical_puddles()
    if visual_root != null:
        _retune_visuals(visual_root)

func _build_environment() -> void:
    var world_env := WorldEnvironment.new()
    world_env.name = "ArenaEnvironment"
    var env := Environment.new()
    var panorama := load(PANORAMA_PATH)
    if panorama is Texture2D:
        var sky_mat := PanoramaSkyMaterial.new()
        sky_mat.panorama = panorama as Texture2D
        var sky := Sky.new()
        sky.sky_material = sky_mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
    else:
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color("#231c18")

    # The scene should feel like a dark industrial bowl rather than an outdoor,
    # top-lit environment. Keep only a low ambient floor so the lamp rig carries
    # most of the usable light.
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#514538")
    env.ambient_light_energy = 0.18
    env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    env.fog_enabled = true
    env.fog_light_color = Color("#6b5f52")
    env.fog_light_energy = 0.22
    env.fog_density = 0.0012
    env.fog_sky_affect = 0.08
    env.tonemap_exposure = 1.0
    world_env.environment = env
    add_child(world_env)

func _load_visuals() -> Node3D:
    var resource := load(VISUAL_PATH)
    if resource is PackedScene:
        var scene := (resource as PackedScene).instantiate()
        if scene is Node3D:
            scene.name = "ArenaVisual"
            add_child(scene)
            return scene as Node3D
        add_child(scene)
        return null
    push_error("Arena v3 visual resource could not be imported: " + VISUAL_PATH)
    return null

func _load_collision() -> void:
    var resource := load(PHYSICS_PATH)
    if not (resource is Mesh):
        push_error("Arena v3 physics resource could not be imported: " + PHYSICS_PATH)
        return
    var body := StaticBody3D.new()
    body.name = "ArenaPhysics"
    var collision := CollisionShape3D.new()
    collision.name = "ArenaTrimesh"
    collision.shape = (resource as Mesh).create_trimesh_shape()
    body.add_child(collision)
    add_child(body)

func _load_original_lights() -> void:
    var resource := load(LIGHTS_PATH)
    if resource is PackedScene:
        var rig := (resource as PackedScene).instantiate()
        rig.name = "OriginalLightRig"
        add_child(rig)
        _retune_light_rig(rig)

func _retune_light_rig(node: Node) -> void:
    if node is DirectionalLight3D:
        # No fake sunlight. Arena should be lit by fixtures inside the map.
        var direct := node as DirectionalLight3D
        direct.visible = false
        direct.light_energy = 0.0
    elif node is SpotLight3D:
        var spot := node as SpotLight3D
        spot.visible = true
        spot.light_color = Color("#f1ead7")
        spot.light_energy = clampf(maxf(spot.light_energy * 0.95, 4.4), 4.4, 8.2)
        spot.spot_range = maxf(spot.spot_range, 34.0)
        spot.spot_angle = maxf(spot.spot_angle, 34.0)
        spot.shadow_enabled = false
    elif node is OmniLight3D:
        var omni := node as OmniLight3D
        var n := String(omni.name).to_lower()
        if n.contains("ambient"):
            omni.visible = false
            omni.light_energy = 0.0
        else:
            omni.visible = true
            omni.light_color = Color("#dfd7c4")
            omni.light_energy = clampf(omni.light_energy * 0.45, 0.25, 1.9)
            omni.omni_range = maxf(omni.omni_range, 8.0)
            omni.shadow_enabled = false
    for child in node.get_children():
        _retune_light_rig(child)

func _retune_visuals(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var node_name := String(mesh_node.name).to_lower()
        if node_name.contains("bims"):
            mesh_node.visible = false
        else:
            if mesh_node.mesh != null:
                for surface in range(mesh_node.mesh.get_surface_count()):
                    var active := mesh_node.get_active_material(surface)
                    var tuned := _tune_map_material(active, node_name)
                    if tuned != null:
                        mesh_node.set_surface_override_material(surface, tuned)
    for child in node.get_children():
        _retune_visuals(child)

func _tune_map_material(material: Material, node_name: String) -> Material:
    if not (material is StandardMaterial3D):
        return material
    var src := material as StandardMaterial3D
    var mat := src.duplicate() as StandardMaterial3D
    var key := (String(src.resource_name) + " " + node_name).to_lower()
    if key.contains("bims"):
        return mat

    # Pull the scene away from the overly glossy look: almost everything in Arena
    # is dusty, damp or oxidized. Keep light panels a bit punchier.
    if key.contains("light_") or key.contains("tv_uwv"):
        mat.roughness = maxf(mat.roughness, 0.52)
        mat.metallic = minf(mat.metallic, 0.04)
        mat.emission_enabled = true
        mat.emission = Color("#fff4d2")
        mat.emission_energy_multiplier = 0.65
    elif key.contains("metall") or key.contains("armatur"):
        mat.roughness = maxf(mat.roughness, 0.74)
        mat.metallic = minf(mat.metallic, 0.18)
    else:
        mat.roughness = maxf(mat.roughness, 0.82)
        mat.metallic = minf(mat.metallic, 0.08)
    return mat

func _spawn_chemical_puddles() -> void:
    var puddle_root := Node3D.new()
    puddle_root.name = "ChemicalPuddles"
    add_child(puddle_root)
    for puddle in CHEMICAL_PUDDLES:
        var pos: Vector3 = puddle["pos"]
        var size: Vector2 = puddle["size"]
        var rot: float = float(puddle["rot"])

        var plane := MeshInstance3D.new()
        plane.name = "ChemicalPuddle"
        var mesh := PlaneMesh.new()
        mesh.size = size
        mesh.subdivide_depth = 1
        mesh.subdivide_width = 1
        plane.mesh = mesh
        plane.position = pos
        plane.rotation.x = -PI * 0.5
        plane.rotation.z = rot
        var mat := StandardMaterial3D.new()
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.albedo_color = Color(0.22, 0.95, 0.34, 0.33)
        mat.roughness = 0.12
        mat.metallic = 0.0
        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        mat.emission_enabled = true
        mat.emission = Color(0.18, 0.95, 0.32)
        mat.emission_energy_multiplier = 0.30
        plane.material_override = mat
        puddle_root.add_child(plane)

        var underlay := MeshInstance3D.new()
        underlay.name = "ChemicalPuddleShade"
        var under_mesh := PlaneMesh.new()
        under_mesh.size = size * 1.12
        underlay.mesh = under_mesh
        underlay.position = pos + Vector3(0.0, -0.01, 0.0)
        underlay.rotation.x = -PI * 0.5
        underlay.rotation.z = rot * 0.9
        var under_mat := StandardMaterial3D.new()
        under_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        under_mat.albedo_color = Color(0.06, 0.16, 0.07, 0.30)
        under_mat.roughness = 1.0
        under_mat.metallic = 0.0
        under_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
        underlay.material_override = under_mat
        puddle_root.add_child(underlay)

        var light := OmniLight3D.new()
        light.name = "ChemicalGlow"
        light.position = pos + Vector3(0.0, 0.6, 0.0)
        light.light_color = Color(0.28, 0.95, 0.36)
        light.light_energy = float(puddle["light"])
        light.omni_range = float(puddle["range"])
        light.shadow_enabled = false
        puddle_root.add_child(light)
