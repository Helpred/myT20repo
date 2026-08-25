extends Node3D
class_name ArenaEditableRuntime

# Arena v18.14 uses two collision representations of the same authored map:
#   layer 1 = softened physical collision used by the rigid tank body/springs;
#   layer 2 = untouched original collision used only by visual suspension and LOS.
# This lets tracks/wheels read the real obstacle silhouette while the rigid body
# climbs a much lower relief and therefore stops hopping over every small curb.
const PHYSICAL_LAYER: int = 1
const VISUAL_PROBE_LAYER: int = 2
const SOFT_PHYSICS_PATH: String = "res://assets/maps/arena/arena_physics_soft.obj"

func _ready() -> void:
	var physics_mesh := get_node_or_null("Collision/PhysicsMesh") as MeshInstance3D
	if physics_mesh == null or physics_mesh.mesh == null:
		return
	physics_mesh.visible = false

	# Always create the untouched source collision first. It becomes the non-solid
	# visual probe only after the softened physical mesh has loaded successfully.
	var source_body: StaticBody3D = _ensure_trimesh_body(physics_mesh, "VisualTerrainProbe")
	var soft_ready: bool = _build_soft_physics_body()
	if source_body != null:
		source_body.collision_layer = VISUAL_PROBE_LAYER if soft_ready else PHYSICAL_LAYER
		source_body.collision_mask = 0

func _ensure_trimesh_body(mesh_instance: MeshInstance3D, body_name: String) -> StaticBody3D:
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			var existing := child as StaticBody3D
			existing.name = body_name
			return existing
	mesh_instance.create_trimesh_collision()
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			var created := child as StaticBody3D
			created.name = body_name
			return created
	return null

func _build_soft_physics_body() -> bool:
	var collision_root := get_node_or_null("Collision") as Node3D
	if collision_root == null:
		return false
	var soft_value: Variant = load(SOFT_PHYSICS_PATH)
	if not (soft_value is Mesh):
		push_warning("Arena soft collision missing; falling back to original collision.")
		return false
	var soft_mesh := MeshInstance3D.new()
	soft_mesh.name = "SoftPhysicsMesh"
	soft_mesh.visible = false
	soft_mesh.mesh = soft_value as Mesh
	collision_root.add_child(soft_mesh)
	var physical_body: StaticBody3D = _ensure_trimesh_body(soft_mesh, "SoftPhysicalBody")
	if physical_body == null:
		soft_mesh.queue_free()
		return false
	physical_body.collision_layer = PHYSICAL_LAYER
	physical_body.collision_mask = 0
	return true
