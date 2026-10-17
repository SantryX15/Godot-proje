// MenuFloor.gdshader — menü/lobi 3D arka planının taktik ızgara zemini.
// Işıklı (lit) malzeme: çizgiler sadece el feneri vurunca belirginleşir; çok hafif emission karanlıkta silüet bırakır.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.045, 0.05, 0.065, 1.0);
uniform vec4 line_color : source_color = vec4(0.5, 0.53, 0.6, 1.0);
uniform float cell = 2.0;          // ince çizgi aralığı (m)
uniform float major_every = 4.0;   // her N hücrede kalın çizgi
uniform float glow = 0.006;        // karanlıkta görünür kalan ızgara

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size, float width) {
	vec2 g = abs(fract(p / size - 0.5) - 0.5) * size;
	float w = max(fwidth(p.x) * width, 0.015 * width);
	return 1.0 - smoothstep(0.0, w, min(g.x, g.y));
}

void fragment() {
	vec2 p = wpos.xz;
	float l = max(grid(p, cell, 1.2) * 0.55, grid(p, cell * major_every, 1.8));
	ALBEDO = mix(base_color.rgb, line_color.rgb, l);
	EMISSION = line_color.rgb * l * glow;
	ROUGHNESS = 0.92;
}
