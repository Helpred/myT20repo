shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_tex : source_color;
uniform sampler2D surface_tex;
uniform sampler2D paint_tex : source_color, repeat_enable;
uniform sampler2D roughness_tex;
uniform sampler2D metallic_tex;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D wear_tex;
uniform float paint_scale = 1.0;
uniform float paint_strength = 0.86;
uniform float roughness_floor = 0.72;
uniform float metallic_ceiling = 0.14;
uniform float normal_depth = 0.26;
uniform float wreck_amount = 0.0; // v18.18.23
uniform vec3 wreck_tint = vec3(0.56, 0.46, 0.38);
// v18.18.26: corrosion is a dedicated wreck overlay. It no longer replaces
// paint_tex, so the original paint/panel detail remains readable.
uniform sampler2D wreck_tex : source_color, repeat_enable;
uniform float wreck_scale = 1.12;
uniform float wreck_texture_strength = 0.78;

void fragment() {
    vec3 base = texture(base_tex, UV).rgb;
    vec3 surface = texture(surface_tex, UV).rgb;
    float base_luma = max(dot(base, vec3(0.2126, 0.7152, 0.0722)), 0.035);

    // surface.r is the recovered paintable-area mask. Do not repaint the most
    // metallic mechanical regions at full strength: this keeps exposed metal,
    // bolts and fittings visually separate from the painted armor.
    float paint_mask = smoothstep(0.18, 0.72, surface.r);
    float source_metal = texture(metallic_tex, UV).r;
    float exposed_metal = smoothstep(0.43, 0.54, source_metal);
    paint_mask *= 1.0 - exposed_metal * 0.72;

    vec3 paint = texture(paint_tex, UV * paint_scale).rgb;
    float paint_luma = clamp(dot(paint, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);

    // Treat the user texture as a PAINT pattern, not a replacement diffuse map.
    // Hue/chroma comes from the paint, while local panel shading and fine detail
    // come from the original tank diffuse. Paint luminance still modulates the
    // large pattern, so dark/light camouflage shapes are preserved.
    float paint_peak = max(max(paint.r, paint.g), max(paint.b, 0.08));
    vec3 paint_hue = paint / paint_peak;
    float pattern_gain = mix(0.55, 1.30, smoothstep(0.04, 0.86, paint_luma));
    float target_luma = clamp(base_luma * pattern_gain, 0.0, 0.90);

    // Keep restrained RGB micro-detail from the original diffuse in addition to
    // its luminance. This is what keeps seams, recesses and weathering readable
    // even under bright yellow/white paints.
    vec3 base_detail = clamp(base / base_luma, vec3(0.78), vec3(1.22));
    vec3 colored = clamp(
        paint_hue * target_luma * mix(vec3(1.0), base_detail, 0.22),
        vec3(0.0), vec3(1.0)
    );

    vec3 out_color = mix(base, colored, paint_mask * paint_strength);
    // Preserve the original paint/detail and blend the supplied rust texture as a
    // separate weathering layer. The old implementation replaced paint_tex and
    // destroyed the tank's local shading; this one only modulates the final armor.
    float wreck = clamp(wreck_amount, 0.0, 1.0);
    vec3 corrosion = texture(wreck_tex, UV * wreck_scale).rgb;
    float corrosion_luma = clamp(dot(corrosion, vec3(0.2126, 0.7152, 0.0722)), 0.04, 0.92);
    vec3 charred = out_color * wreck_tint;
    vec3 rusted = mix(charred, corrosion, 0.72);
    // Reintroduce a little authored panel luminance so the rust does not become
    // a flat self-lit photograph pasted onto the model.
    rusted *= mix(0.68, 1.08, corrosion_luma) * mix(0.82, 1.12, base_luma);
    out_color = mix(out_color, rusted, wreck * wreck_texture_strength);

    // Generated wear masks for Mamont/Thunder contain cross-hatched construction
    // guide lines. Feeding them into ALBEDO creates the artificial wire-grid look,
    // so keep the authored diffuse/normal detail and do not overlay that mask.

    ALBEDO = pow(clamp(out_color, vec3(0.0), vec3(1.0)), vec3(0.96));
    ROUGHNESS = max(texture(roughness_tex, UV).r, roughness_floor);
    METALLIC = min(source_metal, metallic_ceiling) * 0.28;
    NORMAL_MAP = texture(normal_tex, UV).rgb;
    NORMAL_MAP_DEPTH = normal_depth;

    // Very subtle camera-facing silhouette lift. It is intentionally weak enough
    // to keep night lighting intact, but prevents dark paint from disappearing
    // completely into dark Arena geometry.
    SPECULAR = 0.0;
    // Legacy Tanki surfaces should read as painted armor, not glossy lacquer.
    // Remove the artificial silhouette lift as well; this was the main source of
    // the pale white coating still visible even after light Specular was zeroed.
    EMISSION = vec3(0.0);
}
