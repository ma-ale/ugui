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
	vec2 v = vec2(float(viewsize.x), float(viewsize.y));
	
//	vec2 p = vec2(position.x*2.0f/v.x - 1.0f, position.y*2.0f/v.y - 1.0f);
	vec2 p = vec2(position.x*2.0/v.x - 1.0, 1.0 - position.y*2.0/v.y);
	vec4 pos = vec4(p.x, p.y, 0.0f, 1.0f);

	gl_Position = pos;
	// since the texture is a GL_TEXTURE_RECTANGLE the coordintes do not need to
	// be normalized
	uv = vec2(txcoord.x, txcoord.y);
}
