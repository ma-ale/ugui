#version 330

smooth in vec4 out_color;
out vec4 color;

void main()
{
	// set the color for each vertex to white
	color = out_color;
}