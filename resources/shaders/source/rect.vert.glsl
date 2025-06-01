#version 450

layout(set = 1, binding = 0) uniform Viewport {
	ivec2 view;
	ivec2 off;
};

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;
layout(location = 2) in ivec4 color;

layout(location = 0) out vec4 col;

void main()
{
	//vec2 shift = vec2(0);
	vec2 shift;
	shift.x = float(off.x) / view.x;
	shift.y = -(float(off.y) / view.y);

	vec2 pos = position + shift;

	gl_Position = vec4(pos.x, pos.y, 0.0, 1.0);
	col = vec4(color) / 255.0;
}
