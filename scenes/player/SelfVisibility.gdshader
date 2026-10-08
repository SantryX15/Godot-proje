shader_type spatial;
render_mode unshaded, blend_add, cull_back;

// Kendi karakterini karanlıkta görünür kılan kenar parıltısı (self rim light).
// Gerçek bir ışık kaynağı değildir — zemine/duvara ışık veya gölge taşırmaz,
// sadece bu mesh'in kendi yüzeyine ek bir unshaded katman çizer.

uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.85;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb;
	ALPHA = fresnel * rim_strength;
}
