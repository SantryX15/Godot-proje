// MenuOverlay.gdshader — 3D menü arka planının üstüne vinyet + hafif karartma (UI okunabilirliği).
shader_type canvas_item;

uniform float vignette = 0.85;   // kenar karartması
uniform float dim = 0.18;        // tüm ekrana hafif karartma

void fragment() {
	vec2 c = (UV - 0.5) * vec2(1.0, 1.25);
	float v = smoothstep(0.22, 0.85, length(c));
	COLOR = vec4(0.01, 0.012, 0.02, clamp(dim + v * vignette, 0.0, 1.0));
}
