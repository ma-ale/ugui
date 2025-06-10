#version 450

layout(set = 1, binding = 0) uniform Viewport {
    ivec2 view;
};

layout(location = 0) in ivec2 position;
layout(location = 1) in ivec2 in_uv;
layout(location = 2) in ivec4 color;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_color;

void main()
{
    vec2 pos;
	pos.x = float(position.x)*2.0 / view.x - 1.0;
	pos.y = -(float(position.y)*2.0 / view.y - 1.0);
	gl_Position = vec4(pos, 0.0, 1.0);

    out_uv = vec2(float(in_uv.x), float(in_uv.y));
    out_color = vec4(color) / 255.0;
}
