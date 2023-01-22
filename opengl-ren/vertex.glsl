#version 330

// use the input ("in") vertices from index zero
layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;

flat out vec4 out_color;

void main()
{
	// simply copy teh output position
	gl_Position = vec4(position.x, position.y, 0.0f, 1.0f);
	out_color = color;
}