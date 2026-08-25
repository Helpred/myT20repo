shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled;

uniform vec4 liquid_color : source_color = vec4(0.08, 0.55, 0.16, 0.46);
uniform vec4 glow_color : source_color = vec4(0.12, 1.0, 0.28, 1.0);
uniform float glow_strength : hint_range(0.0, 4.0) = 0.55;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.18;
uniform float wave_scale : hint_range(0.1, 20.0) = 5.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.55;

void fragment() {
    vec2 p = UV * wave_scale;
    float w1 = sin(p.x * 2.1 + TIME * wave_speed * 2.3);
    float w2 = cos(p.y * 2.7 - TIME * wave_speed * 1.7);
    float ripple = (w1 + w2) * 0.5;
    float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(0.0, 0.14, UV.y)
        * smoothstep(0.0, 0.14, 1.0 - UV.x) * smoothstep(0.0, 0.14, 1.0 - UV.y);
    ALBEDO = liquid_color.rgb * (0.82 + ripple * 0.08);
    ROUGHNESS = roughness_value;
    METALLIC = 0.0;
    EMISSION = glow_color.rgb * glow_strength * (0.78 + ripple * 0.12);
    ALPHA = liquid_color.a * edge;
    NORMAL = normalize(vec3(-w1 * 0.055, 1.0, -w2 * 0.055));
}
