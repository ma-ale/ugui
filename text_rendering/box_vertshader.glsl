#version 330 core

uniform ivec2 viewsize;

layout(location = 0) in vec2 position;
layout(location = 2) in vec4 color;

out vec4 col;


void main()
{
	vec2 v = vec2(float(viewsize.x), float(viewsize.y));
	vec2 p = vec2(position.x*2.0/v.x - 1.0, 1.0 - position.y*2.0/v.y);
	vec4 pos = vec4(p.x, p.y, 0.0f, 1.0f);

	gl_Position = pos;
	col = color;
}