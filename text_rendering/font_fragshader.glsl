#version 330 core

// viewsize.x = viewport width in pixels; viewsize.y = viewport height in pixels
uniform ivec2 viewsize;
uniform ivec2 texturesize;

// texture uv coordinate in texture space
in vec2 uv;
uniform sampler2DRect ts;

const vec3 textcolor = vec3(1.0, 1.0, 1.0);


void main()
{
	//gl_FragColor = vec4(1.0f,0.0f,0.0f,1.0f);
	gl_FragColor = vec4(textcolor, texture(ts, uv));
}
