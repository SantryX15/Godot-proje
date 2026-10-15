// LightShaft.gdshader — lamba altındaki yumuşak ışık huzmesi ("sızıntı").
// Toplamalı (additive), derinlik yazmaz; kenarlarda (bakış açısına göre) ve aşağı doğru sönümlenir,
// böylece düz bir koni yerine havada asılı hafif bir ışık sisi gibi görünür. WallLamps.gd `intensity` ile titretir.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.3, 1.0);
uniform float intensity = 0.12;

void fragment() {
	// CylinderMesh UV.y: 0 = üst (lamba), 1 = alt (zemin)
	float down = 1.0 - UV.y;
	float height_fade = down * down * down * smoothstep(0.0, 0.08, UV.y);
	// Kenara bakan yüzeyler (silüet) saydam → yumuşak kenar
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_fade = pow(facing, 2.0);
	ALBEDO = color.rgb * intensity * height_fade * edge_fade;
}
