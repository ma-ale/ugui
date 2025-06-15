#version 450

layout(set = 1, binding = 0) uniform Viewport {
    ivec2 view;
};

layout(location = 0) in ivec2 position;
layout(location = 1) in ivec4 attr; // quad x,y,w,h
layout(location = 2) in ivec2 in_uv;
layout(location = 3) in ivec4 color;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_color;

void main()
{
	// vertex position
	ivec2 px_pos = attr.xy + position.xy * attr.zw;
	vec2 clip_pos;
	clip_pos.x = float(px_pos.x)*2.0 / view.x - 1.0;
	clip_pos.y = -(float(px_pos.y)*2.0 / view.y - 1.0);

	gl_Position = vec4(clip_pos, 0.0, 1.0);

    vec2 px_uv = in_uv.xy + position.xy * attr.zw;
    out_uv = vec2(px_uv);
    out_color = vec4(color) / 255.0;
}
