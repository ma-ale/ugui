#version 450

layout(set = 1, binding = 0) uniform Viewport {
	ivec2 view;
};

layout(location = 0) in ivec2 position;
layout(location = 1) in ivec4 attr; // quad x,y,w,h
layout(location = 2) in ivec2 uv;   // x,y in the texture
layout(location = 3) in uvec4 color;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_quad_size;
layout(location = 2) out float out_radius;

void main()
{
	// vertex position
	ivec2 px_pos = attr.xy + position.xy * attr.zw;
	vec2 clip_pos;
	clip_pos.x = float(px_pos.x)*2.0 / view.x - 1.0;
	clip_pos.y = -(float(px_pos.y)*2.0 / view.y - 1.0);

	gl_Position = vec4(clip_pos, 0.0, 1.0);

	out_color = vec4(color) / 255.0;
	out_quad_size = vec4(attr);
	out_radius = float(abs(uv.x));
}
