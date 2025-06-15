#version 450

layout(set = 3, binding = 0) uniform Viewport {
    ivec2 view;
};
layout(set = 2, binding = 0) uniform sampler2D tx;

const float PX_RANGE = 4.0f;

layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 color;

layout(location = 0) out vec4 fragColor;

float screen_px_range(vec2 uv) {
    vec2 unit_range = vec2(PX_RANGE)/vec2(textureSize(tx, 0));
    vec2 texel_size = vec2(1.0)/fwidth(uv);
    return max(0.5*dot(unit_range, texel_size), 1.0);
}

float median(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}

void main() {
    ivec2 ts = textureSize(tx, 0);
    vec2 fts = vec2(ts);
    vec2 real_uv = uv / fts;

	vec3 msd = texture(tx, real_uv).rgb;
	float sd = median(msd.r, msd.g, msd.b);
	float distance = screen_px_range(real_uv)*(sd - 0.5);
	float opacity = clamp(distance + 0.5, 0.0, 1.0);
	fragColor = color * opacity;
}