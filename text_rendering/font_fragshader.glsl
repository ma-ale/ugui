#version 330 core

// viewsize.x = viewport width in pixels; viewsize.y = viewport height in pixels
uniform ivec2 viewsize;
uniform ivec2 texturesize;

// texture uv coordinate in texture space
in vec2 uv;
uniform sampler2D ts;

void main()
{
	//gl_FragColor = vec4(1.0f,0.0f,0.0f,1.0f);
	gl_FragColor = texture(ts, uv);
}
