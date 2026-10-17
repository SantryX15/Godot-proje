// BlurBackdrop.gdshader — modal pencerelerin arkasındaki ekranı bulanıklaştırıp karartır.
// Ekran dokusunun mipmap'inden okur (ucuz blur) + birkaç ofsetli örnekle yumuşatır.
// `amount` 0→1 ile açılış/kapanış animasyonu yapılır.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float blur_lod = 3.0;
uniform vec4 tint : source_color = vec4(0.02, 0.025, 0.04, 0.4);

void fragment() {
	float lod = blur_lod * amount;
	vec2 px = SCREEN_PIXEL_SIZE * 6.0 * amount;
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.4;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), lod).rgb * 0.15;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), lod).rgb * 0.15;
	c = mix(c, tint.rgb, tint.a * amount);
	COLOR = vec4(c, 1.0);
}
