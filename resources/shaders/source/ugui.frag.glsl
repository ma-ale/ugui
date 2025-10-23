#version 450

/* Combined fragment shader to render UGUI commands */

// type values, these are the same as in renderer.c3
const uint TYPE_RECT   = 0;
const uint TYPE_FONT   = 1;
const uint TYPE_SPRITE = 2;
const uint TYPE_MSDF   = 3;

// viewport size
layout(set = 3, binding = 0) uniform Viewport {
    ivec2 view;
};

// textures
layout(set = 2, binding = 0) uniform sampler2D font_atlas;
layout(set = 2, binding = 1) uniform sampler2D sprite_atlas;

// inputs
layout(location = 0) in vec4  in_color;
layout(location = 1) in vec2  in_uv;
layout(location = 2) in vec4  in_quad_size;
layout(location = 3) in float in_radius;
layout(location = 4) flat in uint  in_type;

// outputs
layout(location = 0) out vec4 fragColor;


// SDF for a rounded rectangle given the centerpoint, half size and radius, all in pixels
float sdf_rr(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}


const float PX_RANGE = 4.0f;
float screen_px_range(vec2 uv, sampler2D tx) {
	vec2 unit_range = vec2(PX_RANGE)/vec2(textureSize(tx, 0));
	vec2 texel_size = vec2(1.0)/fwidth(uv);
	return max(0.5*dot(unit_range, texel_size), 1.0);
}


float median(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}


// main for TYPE_RECT, draw a rouded rectangle with a SDF
void rect_main()
{
	vec2 centerpoint = in_quad_size.xy + in_quad_size.zw * 0.5;
	vec2 half_size = in_quad_size.zw * 0.5;
	float distance = sdf_rr(vec2(gl_FragCoord) - centerpoint, half_size, in_radius);
	float alpha = 1.0 - smoothstep(0.0, 1.5, distance);
	fragColor = vec4(in_color.rgb, in_color.a * alpha);
}


// main for TYPE_SPRITE, draws a sprite sampled from an atlas
void sprite_main()
{
	ivec2 ts = textureSize(sprite_atlas, 0);
	vec2 fts = vec2(ts);
	vec2 real_uv = in_uv.xy / fts;
	fragColor = texture(sprite_atlas, real_uv);
}


// main for TYPE_FONT, draws a character sampled from an atlas that contains only the alpha channel
void font_main()
{
	ivec2 ts = textureSize(font_atlas, 0);
	vec2 fts = vec2(ts);
	vec2 real_uv = in_uv.xy / fts;

	vec4 opacity = texture(font_atlas, real_uv);
	fragColor = vec4(in_color.rgb, in_color.a*opacity.r);
}


// main for TYPE_MSDF, draws a sprite that is stored as a multi-channel SDF
void msdf_main() {
	ivec2 ts = textureSize(sprite_atlas, 0);
	vec2 fts = vec2(ts);
	vec2 real_uv = in_uv.xy / fts;

	vec3 msd = texture(sprite_atlas, real_uv).rgb;
	float sd = median(msd.r, msd.g, msd.b);
	float distance = screen_px_range(real_uv, sprite_atlas)*(sd - 0.5);
	float opacity = clamp(distance + 0.5, 0.0, 1.0);
	fragColor = in_color * opacity;
}


// shader main
void main()
{
	switch (in_type) {
	case TYPE_RECT:
		rect_main();
		break;
	case TYPE_FONT:
		font_main();
		break;
	case TYPE_SPRITE:
		sprite_main();
		break;
	case TYPE_MSDF:
		msdf_main();
		break;
	default:
		// ERROR, invalid type, return magenta
		fragColor = vec4(1.0, 0.0, 1.0, 1.0);
	}
}