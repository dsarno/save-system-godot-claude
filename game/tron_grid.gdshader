// Tron-style grid floor shader. Renders a dark base with glowing
// cyan lines on each unit boundary, plus emissive highlight on the
// block directly under the camera so the floor reads "electric".
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec4 bg_color : source_color = vec4(0.015, 0.020, 0.050, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.88, 1.0, 1.0);
uniform float cell_size : hint_range(0.1, 10.0) = 1.0;
uniform float line_thickness : hint_range(0.005, 0.25) = 0.035;
uniform float emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float fade_start : hint_range(0.0, 30.0) = 6.0;
uniform float fade_end : hint_range(0.0, 30.0) = 12.0;

void fragment() {
	// World-space XZ sampled through UV (mesh is a 20x20 BoxMesh with
	// default UVs that match world units along the top face).
	vec2 coord = UV * 20.0 / cell_size;
	vec2 cell = abs(fract(coord) - 0.5);
	float line = step(0.5 - line_thickness, max(cell.x, cell.y));

	// Distance-based fade so lines get gentler toward arena edges.
	float dist_from_center = length(UV - vec2(0.5)) * 20.0;
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist_from_center);

	vec3 col = mix(bg_color.rgb, line_color.rgb, line * fade);
	ALBEDO = col;
	EMISSION = line_color.rgb * line * fade * emission_strength;
}
