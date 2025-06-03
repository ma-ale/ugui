#version 450

layout(set = 1, binding = 0) uniform Viewport {
	ivec2 view;
	ivec2 off;
};

layout(location = 0) in ivec2 position;
layout(location = 1) in ivec2 uv;
layout(location = 2) in ivec4 color;

layout(location = 0) out vec4 col;

void main()
{
	// per vertex shift
	vec2 shift;
	shift.x = float(off.x) / view.x;
	shift.y = -(float(off.y) / view.y);

	// vertex position
	vec2 pos;
	pos.x = float(position.x)*2.0 / view.x - 1.0;
	pos.y = -(float(position.y)*2.0 / view.y - 1.0);

	gl_Position = vec4(pos+shift, 0.0, 1.0);
	col = vec4(color) / 255.0;
}
