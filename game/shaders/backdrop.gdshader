shader_type canvas_item;
// The backdrop sits behind the playfield: pull its saturation and value down a step so the
// ground, the structures and the squad in front of it read as a separate, brighter layer.
uniform float sat = 0.7;
uniform float val = 0.9;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(g), c.rgb, sat) * val, c.a);
}
