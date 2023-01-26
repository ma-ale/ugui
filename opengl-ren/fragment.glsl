#version 330

flat in vec4 out_color;
in vec2 texture_coord;
uniform sampler2D texture_sampler;

out vec4 color;

void main()
{
	color = texture(texture_sampler, texture_coord) + out_color;
}