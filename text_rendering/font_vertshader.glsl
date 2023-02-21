#version 330 core

// viewsize.x = viewport width in pixels; viewsize.y = viewport height in pixels
uniform vec2 viewsize;

// both position and and uv are in pixels
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 uv;

out vec2 texture_coord;

void main()
{
	vec4 pos = vec4(position.x, position.y, 0.0f, 1.0f);
	vec2 v = viewsize / 2;
	pos.xy = (pos.xy - v) / v;

	gl_Position = pos;
	texture_coord = uv / viewsize;
}
