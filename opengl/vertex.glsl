#version 330

// use the input ("in") vertices from index zero
layout(location = 0) in vec4 position;

void main()
{
	// simply copy teh output position
	gl_Position = position;
}