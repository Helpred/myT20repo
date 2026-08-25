extends Node3D
class_name ArenaV3Fallback

func _ready() -> void:
    _build_ground()
    _build_walls()
    _build_landmarks()

func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _box(name_: String, pos: Vector3, size: Vector3, color: Color, rot_y := 0.0, rot_x := 0.0) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = name_
    body.position = pos
    body.rotation = Vector3(rot_x, rot_y, 0.0)
    add_child(body)
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.material_override = _mat(color)
    body.add_child(mesh_instance)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    return body

func _build_ground() -> void:
    _box("ArenaFloor", Vector3(0,-0.6,0), Vector3(220,1.2,190), Color("#59604e"))

func _build_walls() -> void:
    var c := Color("#665d50")
    _box("NorthWall", Vector3(0,4,-95), Vector3(220,8,2), c)
    _box("SouthWall", Vector3(0,4,95), Vector3(220,8,2), c)
    _box("WestWall", Vector3(-110,4,0), Vector3(2,8,190), c)
    _box("EastWall", Vector3(110,4,0), Vector3(2,8,190), c)

func _build_landmarks() -> void:
    var concrete := Color("#77746a")
    var metal := Color("#555b5c")
    var rust := Color("#72594a")
    _box("CenterPlatform", Vector3(0,1.5,0), Vector3(28,3,22), concrete)
    _box("CenterRampN", Vector3(0,0.8,-17), Vector3(18,1.5,16), concrete, 0.0, deg_to_rad(-8))
    _box("CenterRampS", Vector3(0,0.8,17), Vector3(18,1.5,16), concrete, 0.0, deg_to_rad(8))
    _box("FactoryA", Vector3(-55,5,-30), Vector3(28,10,20), rust)
    _box("FactoryB", Vector3(52,4,34), Vector3(24,8,28), metal)
    _box("LongBlock", Vector3(55,2,-45), Vector3(36,4,8), concrete, deg_to_rad(16))
    _box("WestBlock", Vector3(-70,2,35), Vector3(24,4,12), concrete, deg_to_rad(-22))
    _box("NorthCoverA", Vector3(-25,1.5,-62), Vector3(13,3,8), metal)
    _box("NorthCoverB", Vector3(20,1.5,-63), Vector3(13,3,8), metal)
    _box("SouthCoverA", Vector3(-22,1.5,62), Vector3(14,3,8), rust)
    _box("SouthCoverB", Vector3(25,1.5,61), Vector3(14,3,8), rust)
    for p in [Vector3(-90,1,0), Vector3(87,1,-10), Vector3(-45,1,70), Vector3(70,1,70)]:
        _box("Crate", p, Vector3(6,2,6), rust)
