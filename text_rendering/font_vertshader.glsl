#version 330 core

// viewsize.x = viewport width in pixels; viewsize.y = viewport height in pixels
uniform ivec2 viewsize;
uniform ivec2 texturesize;

// both position and and uv are in pixels, they where converted to floats when 
// passed to the shader
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 txcoord;

out vec2 uv;

void main()
{
	vec4 pos = vec4(position.x, position.y, 0.0f, 1.0f);
	vec2 hsize = vec2(float(viewsize.x)/2.0f, float(viewsize.y)/2.0f);

	pos.xy = (pos.xy - hsize) / hsize;

	gl_Position = pos;
	uv = txcoord / float(texturesize);
}
