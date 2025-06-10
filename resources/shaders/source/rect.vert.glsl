#version 450

layout(set = 1, binding = 0) uniform Viewport {
	ivec2 view;
};

layout(location = 0) in ivec2 position;
layout(location = 1) in ivec2 uv;
layout(location = 2) in ivec4 color;

layout(location = 0) out vec4 col;
layout(location = 1) out vec2 local_position;
layout(location = 2) out vec2 global_position;
layout(location = 3) out float radius;

void main()
{
	// vertex position
	vec2 pos;
	pos.x = float(position.x)*2.0 / view.x - 1.0;
	pos.y = -(float(position.y)*2.0 / view.y - 1.0);

	gl_Position = vec4(pos, 0.0, 1.0);

	local_position = vec2(sign(uv));
	global_position = gl_Position.xy;
	radius = abs(float(uv.x));
	
	col = vec4(color) / 255.0;
}
