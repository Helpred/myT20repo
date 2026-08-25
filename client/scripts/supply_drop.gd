extends Node3D
class_name SupplyDropActor

const DROP_HEIGHT: float = 28.0
const CRATE_HALF_HEIGHT: float = 0.72
const PICKUP_VISUAL_RADIUS: float = 3.8

# Original 2010/2011 client cube atlases. Each texture is a 4x4 atlas:
# four side faces on row 1, top at (1, 0), bottom at (1, 2).
const ArmorAtlas: Texture2D = preload("res://assets/bonuses/crate_armor.jpg")
const CrystalAtlas: Texture2D = preload("res://assets/bonuses/crate_crystal.jpg")
const GoldAtlas: Texture2D = preload("res://assets/bonuses/crate_gold.jpg")
const MedkitAtlas: Texture2D = preload("res://assets/bonuses/crate_medkit.jpg")
const NitroAtlas: Texture2D = preload("res://assets/bonuses/crate_nitro.jpg")
const DamageAtlas: Texture2D = preload("res://assets/bonuses/crate_damage.jpg")
const ParachuteTop: Texture2D = preload("res://assets/bonuses/parachute_classic_top.jpg")
const ParachuteBottom: Texture2D = preload("res://assets/bonuses/parachute_classic_bottom.jpg")

var supply_id: int = -1
var supply_kind: String = ""
var landing_position: Vector3 = Vector3.ZERO
var _fall_remaining: float = 0.0
var _ground_remaining: float = 0.0
var _persistent: bool = false
var _descent_total: float = 4.8
var _age: float = 0.0
var _crate: MeshInstance3D
var _crate_material: StandardMaterial3D
var _crate_base_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _parachute_root: Node3D
var _pickup_animating: bool = false
var _pickup_is_local: bool = false
var _pickup_elapsed: float = 0.0
const PICKUP_ANIM_DURATION: float = 0.72

func configure(data: Dictionary) -> void:
	supply_id = int(data.get("id", -1))
	supply_kind = String(data.get("kind", "nitro"))
	name = "Supply_%d_%s" % [supply_id, supply_kind]
	add_to_group("tanki_supply")
	_build_visuals()
	update_authoritative(data)

func update_authoritative(data: Dictionary) -> void:
	var p_value: Variant = data.get("p", [])
	if p_value is Array and (p_value as Array).size() >= 3:
		var p: Array = p_value as Array
		landing_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_descent_total = maxf(float(data.get("descent", _descent_total)), 0.1)
	_fall_remaining = maxf(float(data.get("fall_remaining", _fall_remaining)), 0.0)
	_persistent = bool(data.get("persistent", _persistent))
	if not _persistent:
		_ground_remaining = maxf(float(data.get("ground_remaining", _ground_remaining)), 0.0)
	_update_position()

func is_pickable() -> bool:
	# v19.1: a tank may catch a crate while it is still descending. The server
	# repeats the same 3D proximity check, so this is only the responsive client probe.
	return not _pickup_animating and (_fall_remaining > 0.0 or _persistent or _ground_remaining > 0.0)

func pickup_position() -> Vector3:
	# Return the CURRENT crate centre, not the future landing marker.
	return global_position + Vector3.UP * CRATE_HALF_HEIGHT

func ai_kind() -> String:
	return supply_kind

func ai_target_position() -> Vector3:
	# Bots navigate under the parachute/landing spot and can catch the crate on descent.
	return landing_position

func ai_is_available() -> bool:
	return is_pickable()

func _process(delta: float) -> void:
	_age += delta
	if _pickup_animating:
		_process_pickup_animation(delta)
		return
	if _fall_remaining > 0.0:
		_fall_remaining = maxf(0.0, _fall_remaining - delta)
	elif not _persistent:
		_ground_remaining = maxf(0.0, _ground_remaining - delta)
	_update_position()

	if _parachute_root != null:
		_parachute_root.visible = _fall_remaining > 0.02
		if _parachute_root.visible:
			# Very small cloth sway only; the crate itself stays upright.
			_parachute_root.rotation.z = sin(_age * 1.20 + float(supply_id) * 0.47) * 0.025
			_parachute_root.rotation.x = cos(_age * 0.92 + float(supply_id) * 0.31) * 0.016

	if _crate != null:
		# Old Tanki boxes rotated around vertical axis while descending.
		# Never rotate X/Z, so the box always lands square and upright.
		_crate.rotation.x = 0.0
		_crate.rotation.z = 0.0
		_crate.transparency = 0.0
		if _fall_remaining > 0.0:
			_crate.rotation.y += delta * 0.28
		elif not _persistent and _ground_remaining < 5.0:
			_crate.visible = fmod(_ground_remaining, 0.50) > 0.16
		else:
			_crate.visible = true

func play_pickup_effect(is_local: bool = false) -> void:
	if _pickup_animating:
		return
	_pickup_animating = true
	_pickup_is_local = is_local
	_pickup_elapsed = 0.0
	_fall_remaining = 0.0
	_ground_remaining = 0.0
	if _parachute_root != null:
		_parachute_root.visible = false
	if _crate != null:
		_crate.visible = true
		_crate.transparency = 0.0
	if _crate_material != null:
		_crate_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var base_color: Color = _crate_base_color
		base_color.a = 1.0
		_crate_material.albedo_color = base_color

func _process_pickup_animation(delta: float) -> void:
	if _crate == null:
		queue_free()
		return
	_pickup_elapsed += delta
	var t: float = clampf(_pickup_elapsed / PICKUP_ANIM_DURATION, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	_crate.visible = true
	_crate.rotation.x = 0.0
	_crate.rotation.z = 0.0
	_crate.rotation.y += delta * (8.0 if _pickup_is_local else 6.4)
	_crate.position.y = CRATE_HALF_HEIGHT + eased * 2.05
	_crate.transparency = min(0.96, eased * 0.92)
	if _crate_material != null:
		var color: Color = _crate_base_color
		color.a = 1.0 - eased
		_crate_material.albedo_color = color
	if t >= 1.0:
		queue_free()

func _update_position() -> void:
	var height_ratio: float = clampf(_fall_remaining / maxf(_descent_total, 0.1), 0.0, 1.0)
	var eased: float = height_ratio * height_ratio * (3.0 - 2.0 * height_ratio)
	global_position = landing_position + Vector3.UP * DROP_HEIGHT * eased

func _atlas_for_kind() -> Texture2D:
	match supply_kind:
		"armor":
			return ArmorAtlas
		"crystal":
			return CrystalAtlas
		"gold":
			return GoldAtlas
		"medkit":
			return MedkitAtlas
		"damage":
			return DamageAtlas
		_:
			return NitroAtlas

func _build_visuals() -> void:
	_crate = MeshInstance3D.new()
	_crate.mesh = _make_crate_mesh()
	_crate.position.y = CRATE_HALF_HEIGHT
	# Supply boxes are runtime geometry. Mark them as dynamic GI receivers so
	# LightmapGI can light them through baked light probes instead of treating
	# them like static lightmapped level geometry.
	_crate.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

	_crate_material = StandardMaterial3D.new()
	var crate_atlas: Texture2D = _atlas_for_kind()
	_crate_material.albedo_texture = crate_atlas
	_crate_material.roughness = 0.86
	_crate_material.metallic = 0.0
	_crate_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crate_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	_crate_base_color = Color(1.0, 1.0, 1.0, 1.0)
	if supply_kind == "gold":
		_crate_base_color = Color(0.96, 0.96, 0.96, 1.0)
	_crate_material.albedo_color = _crate_base_color
	_crate.material_override = _crate_material
	add_child(_crate)

	_parachute_root = Node3D.new()
	_parachute_root.position = Vector3(0.0, 4.75, 0.0)
	add_child(_parachute_root)

	var top_instance: MeshInstance3D = MeshInstance3D.new()
	top_instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	top_instance.mesh = _make_canopy_mesh(false)
	top_instance.material_override = _parachute_material(ParachuteTop)
	_parachute_root.add_child(top_instance)

	var bottom_instance: MeshInstance3D = MeshInstance3D.new()
	bottom_instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	bottom_instance.position.y = -0.035
	bottom_instance.mesh = _make_canopy_mesh(true)
	bottom_instance.material_override = _parachute_material(ParachuteBottom)
	_parachute_root.add_child(bottom_instance)

	_build_cords()

func _make_crate_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hx: float = 0.775
	var hy: float = 0.71
	var hz: float = 0.775

	# Four side tiles in the atlas, in the same order as the original cube strip.
	_add_crate_quad(st,
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
		Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
		Vector3(0.0, 0.0, 1.0), 0, 1)
	_add_crate_quad(st,
		Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz),
		Vector3(hx, hy, -hz), Vector3(hx, hy, hz),
		Vector3(1.0, 0.0, 0.0), 1, 1)
	_add_crate_quad(st,
		Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz),
		Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz),
		Vector3(0.0, 0.0, -1.0), 2, 1)
	_add_crate_quad(st,
		Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz),
		Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz),
		Vector3(-1.0, 0.0, 0.0), 3, 1)

	# Top and bottom are the vertical part of the original cross atlas.
	_add_crate_quad(st,
		Vector3(-hx, hy, hz), Vector3(hx, hy, hz),
		Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
		Vector3(0.0, 1.0, 0.0), 1, 0)
	_add_crate_quad(st,
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
		Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz),
		Vector3(0.0, -1.0, 0.0), 1, 2)

	var mesh_value: ArrayMesh = st.commit()
	return mesh_value

func _add_crate_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3,
	tile_x: int,
	tile_y: int
) -> void:
	var pad: float = 1.0 / 240.0
	var u0: float = float(tile_x) * 0.25 + pad
	var v0: float = float(tile_y) * 0.25 + pad
	var u1: float = float(tile_x + 1) * 0.25 - pad
	var v1: float = float(tile_y + 1) * 0.25 - pad

	# Vertex order is bottom-left, bottom-right, top-right, top-left
	# when looking at the face from outside.
	_add_crate_vertex(st, a, normal, Vector2(u0, v1))
	_add_crate_vertex(st, b, normal, Vector2(u1, v1))
	_add_crate_vertex(st, c, normal, Vector2(u1, v0))
	_add_crate_vertex(st, a, normal, Vector2(u0, v1))
	_add_crate_vertex(st, c, normal, Vector2(u1, v0))
	_add_crate_vertex(st, d, normal, Vector2(u0, v0))

func _add_crate_vertex(st: SurfaceTool, vertex: Vector3, normal: Vector3, uv: Vector2) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.add_vertex(vertex)

func _build_cords() -> void:
	var cords: MeshInstance3D = MeshInstance3D.new()
	var line_mesh: ImmediateMesh = ImmediateMesh.new()
	var cord_mat: StandardMaterial3D = StandardMaterial3D.new()
	cord_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cord_mat.albedo_color = Color(0.78, 0.73, 0.63)
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, cord_mat)

	var cord_count: int = 12
	for index: int in range(cord_count):
		var angle: float = TAU * float(index) / float(cord_count)
		var rim_radius: float = 2.68
		var rim: Vector3 = Vector3(cos(angle) * rim_radius, 0.02, sin(angle) * rim_radius)
		var corner_x: float = 0.56 if cos(angle) >= 0.0 else -0.56
		var corner_z: float = 0.56 if sin(angle) >= 0.0 else -0.56
		var crate_corner: Vector3 = Vector3(corner_x, -4.02, corner_z)
		line_mesh.surface_add_vertex(rim)
		line_mesh.surface_add_vertex(crate_corner)

	# Four extra lines from quarter points create the denser original silhouette.
	for index: int in range(4):
		var angle: float = TAU * (float(index) + 0.5) / 4.0
		var rim: Vector3 = Vector3(cos(angle) * 2.42, 0.12, sin(angle) * 2.42)
		var crate_corner: Vector3 = Vector3(
			0.48 if cos(angle) >= 0.0 else -0.48,
			-4.02,
			0.48 if sin(angle) >= 0.0 else -0.48
		)
		line_mesh.surface_add_vertex(rim)
		line_mesh.surface_add_vertex(crate_corner)

	line_mesh.surface_end()
	cords.mesh = line_mesh
	_parachute_root.add_child(cords)

func _parachute_material(texture: Texture2D) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

func _make_canopy_mesh(reverse: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: int = 7
	var sectors: int = 24
	var radius: float = 2.72
	var height: float = 1.02

	for ring: int in range(rings):
		var t0: float = float(ring) / float(rings)
		var t1: float = float(ring + 1) / float(rings)
		# Shallow rounded canopy: fuller in the middle, flatter near the rim.
		var theta0: float = t0 * PI * 0.5
		var theta1: float = t1 * PI * 0.5
		for sector: int in range(sectors):
			var a0: float = TAU * float(sector) / float(sectors)
			var a1: float = TAU * float(sector + 1) / float(sectors)
			var scallop0: float = 1.0
			var scallop1: float = 1.0
			if ring == rings - 1:
				scallop0 = 0.965 + 0.035 * absf(cos(float(sector) * PI))
				scallop1 = 0.965 + 0.035 * absf(cos(float(sector + 1) * PI))
			var p00: Vector3 = Vector3(
				cos(a0) * sin(theta0) * radius,
				cos(theta0) * height,
				sin(a0) * sin(theta0) * radius
			)
			var p01: Vector3 = Vector3(
				cos(a1) * sin(theta0) * radius,
				cos(theta0) * height,
				sin(a1) * sin(theta0) * radius
			)
			var p10: Vector3 = Vector3(
				cos(a0) * sin(theta1) * radius * scallop0,
				cos(theta1) * height,
				sin(a0) * sin(theta1) * radius * scallop0
			)
			var p11: Vector3 = Vector3(
				cos(a1) * sin(theta1) * radius * scallop1,
				cos(theta1) * height,
				sin(a1) * sin(theta1) * radius * scallop1
			)
			_add_canopy_triangle(st, p00, p10, p11, radius, reverse)
			_add_canopy_triangle(st, p00, p11, p01, radius, reverse)

	st.generate_normals()
	var mesh_value: ArrayMesh = st.commit()
	return mesh_value

func _add_canopy_triangle(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	radius: float,
	reverse: bool
) -> void:
	if reverse:
		_add_canopy_vertex(st, a, radius)
		_add_canopy_vertex(st, c, radius)
		_add_canopy_vertex(st, b, radius)
	else:
		_add_canopy_vertex(st, a, radius)
		_add_canopy_vertex(st, b, radius)
		_add_canopy_vertex(st, c, radius)

func _add_canopy_vertex(st: SurfaceTool, vertex: Vector3, radius: float) -> void:
	var uv: Vector2 = Vector2(
		0.5 + vertex.x / (radius * 2.0),
		0.5 + vertex.z / (radius * 2.0)
	)
	st.set_uv(uv)
	st.add_vertex(vertex)
