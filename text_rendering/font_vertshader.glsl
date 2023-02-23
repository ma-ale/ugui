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
	// matrix to change from image coordinates to opengl coordinates
	mat2 transform = mat2(vec2(0.0f, -1.0f), vec2(1.0f, 0.0f));
	vec2 v = vec2(float(viewsize.x), float(viewsize.y));
	vec2 h = v/2.0f;
	vec2 p = ((position-h)/ h);

	vec4 pos = vec4(p.x, p.y, 0.0f, 1.0f);

	gl_Position = pos;
	uv = vec2(txcoord.x / float(texturesize.x), (float(texturesize.y) - txcoord.y) / float(texturesize.y));
}
