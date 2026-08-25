extends Sprite3D
class_name TankSheetEffect

var _life: float = 0.5
var _age: float = 0.0
var _first_frame: int = 0
var _last_frame: int = 0
var _start_size: float = 1.0
var _end_size: float = 1.0
var _velocity: Vector3 = Vector3.ZERO
var _acceleration: Vector3 = Vector3.ZERO
var _start_alpha: float = 1.0
var _fade_start: float = 0.55
var _spin_speed: float = 0.0
var _frame_pixels: float = 128.0
var _color: Color = Color.WHITE

func setup(
    texture_path: String,
    first_frame: int,
    last_frame: int,
    life_seconds: float,
    start_size: float,
    end_size: float,
    velocity: Vector3 = Vector3.ZERO,
    acceleration: Vector3 = Vector3.ZERO,
    alpha: float = 1.0,
    fade_start: float = 0.55,
    spin_speed: float = 0.0,
    color: Color = Color.WHITE
) -> void:
    var loaded := load(texture_path)
    if loaded is Texture2D:
        texture = loaded as Texture2D
    hframes = 8
    vframes = 8
    billboard = BaseMaterial3D.BILLBOARD_ENABLED
    shaded = false
    transparent = true
    double_sided = true
    # The original effect atlases contain broad low-alpha halos. Alpha-hash turns
    # surviving pixels fully opaque, which exposes the whole frame as a red/grey
    # rectangle. Use the authored smooth alpha again and keep billboard shadows off.
    alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    render_priority = 3
    _first_frame = clampi(first_frame, 0, 63)
    _last_frame = clampi(last_frame, _first_frame, 63)
    frame = _first_frame
    _life = maxf(life_seconds, 0.02)
    _start_size = maxf(start_size, 0.01)
    _end_size = maxf(end_size, 0.01)
    _velocity = velocity
    _acceleration = acceleration
    _start_alpha = clampf(alpha, 0.0, 1.0)
    _fade_start = clampf(fade_start, 0.0, 0.98)
    _spin_speed = spin_speed
    _color = color
    pixel_size = _start_size / _frame_pixels
    modulate = Color(_color.r, _color.g, _color.b, _start_alpha)

func _process(delta: float) -> void:
    _age += delta
    if _age >= _life:
        queue_free()
        return

    var t := clampf(_age / _life, 0.0, 1.0)
    var frame_count := _last_frame - _first_frame + 1
    if frame_count > 1:
        frame = clampi(_first_frame + int(floor(t * float(frame_count))), _first_frame, _last_frame)

    _velocity += _acceleration * delta
    global_position += _velocity * delta
    rotation.z += _spin_speed * delta
    pixel_size = lerpf(_start_size, _end_size, t) / _frame_pixels

    var fade := 1.0
    if t > _fade_start:
        fade = 1.0 - ((t - _fade_start) / maxf(1.0 - _fade_start, 0.001))
    modulate = Color(_color.r, _color.g, _color.b, _start_alpha * clampf(fade, 0.0, 1.0))
