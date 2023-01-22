#version 330

// use the input ("in") vertices from index zero
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;

smooth out vec4 out_color;

void main()
{
	// simply copy teh output position
	gl_Position = position;
	out_color = color;
}