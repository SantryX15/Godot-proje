// MenuBackdrop.gdshader
// Ana menü arka planı: karanlık zemin + taktik ızgara + fareyi takip eden el feneri konisi + vinyet.
shader_type canvas_item;

uniform vec2 rect_size = vec2(1152.0, 648.0);
uniform vec2 light_pos = vec2(576.0, 324.0);
uniform vec4 bg_color : source_color = vec4(0.03, 0.035, 0.05, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform float light_radius = 460.0;
uniform float grid_size = 48.0;

void fragment() {
	vec2 px = UV * rect_size;

	// El feneri: yumuşak kenarlı radyal ışık
	float d = distance(px, light_pos);
	float light = 1.0 - smoothstep(0.0, light_radius, d);
	light *= light;

	// Izgara çizgileri (ışığın içinde daha belirgin)
	vec2 g = abs(fract(px / grid_size - 0.5) - 0.5) * grid_size;
	float line = 1.0 - smoothstep(0.0, 1.1, min(g.x, g.y));
	// Her 4 hücrede bir kalın çizgi
	vec2 g4 = abs(fract(px / (grid_size * 4.0) - 0.5) - 0.5) * grid_size * 4.0;
	float major = 1.0 - smoothstep(0.0, 1.4, min(g4.x, g4.y));

	vec3 col = bg_color.rgb;
	col += light_color.rgb * light * 0.16;
	col += vec3(line) * (0.012 + light * 0.06);
	col += vec3(major) * (0.012 + light * 0.05);

	// Vinyet
	vec2 c = UV - 0.5;
	col *= 1.0 - dot(c, c) * 1.1;

	COLOR = vec4(col, 1.0);
}
