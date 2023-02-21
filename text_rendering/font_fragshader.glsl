#version 330

// viewsize.x = viewport width in pixels; viewsize.y = viewport height in pixels
uniform vec2 viewsize;
// texture uv coordinate in texture space
in vec2 texture_coord;
uniform sampler2D texture_sampler;

out vec4 color;

void main()
{
	color = mix(vec4(0.0f,0.0f,0.0f,1.0f), vec4(1.0f,1.0f,1.0f,1.0f), texture(texture_sampler, texture_coord)) + vec4(1.0f,0.0f,0.0f,1.0f);
}
