#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>
#include <SDL2/SDL_video.h>
#include <grapheme.h>
#include <stdio.h>

#include "util.h"
#include "font.h"
#include "ren.h"


#define GLERR(x)                                                               \
{                                                                              \
	int a = glGetError();                                                  \
	if (a != GL_NO_ERROR)                                                  \
		printf("(%s:%d %s:%s) glError: 0x%x %s\n",                     \
			__FILE__, __LINE__, __func__, x, a, glerr[a]);         \
}
#define GL(f) f; GLERR(#f)


enum REN_ERR {
	REN_SUCCESS = 0,
	REN_ERRNO,
	REN_INVAL,
	REN_VERTEX,
	REN_FRAGMENT,
	REN_PROGRAM,
	REN_COMPILE,
	REN_LINK,
	REN_TEXTURE,
	REN_CONTEXT,
	REN_GLEW,
	REN_FONT,
	REN_BUFFER,
	REN_UNIFORM,
};


// TODO: make a macro for enum-associated string arrays
const char * ren_err_msg[] = {
	[REN_SUCCESS]  = "Success",
	[REN_ERRNO]    = "Look at errno",
	[REN_INVAL]    = "Invalid or NULL arguments",
	[REN_VERTEX]   = "Failed to create opengl vertex shader",
	[REN_FRAGMENT] = "Failed to create opengl fragment shader",
	[REN_PROGRAM]  = "Failed to create opengl program",
	[REN_COMPILE]  = "Failed to compile shaders",
	[REN_LINK]     = "Failed to link shaders",
	[REN_TEXTURE]  = "Failed to create texture",
	[REN_CONTEXT]  = "Failed to create SDL OpenGL context",
	[REN_GLEW]     = "GLEW Error",
	[REN_FONT]     = "Font Error",
	[REN_BUFFER]   = "Failed to create opengl buffer",
	[REN_UNIFORM]  = "Failed to get uniform location",
};


#define ELEM(x...) [x] = #x,
const char *glerr[] = {
	ELEM(GL_INVALID_ENUM)
	ELEM(GL_INVALID_VALUE)
	ELEM(GL_INVALID_OPERATION)
	ELEM(GL_OUT_OF_MEMORY)
};
#undef ELEM


// different stacks
#include "stack.h"
STACK_DECL(vtstack, struct v_text)
STACK_DECL(vcstack, struct v_col)


struct {
	SDL_GLContext *gl;
	struct font_atlas *font;
	GLuint font_texture;
	GLuint font_prog;
	GLuint box_prog;
	GLuint font_buffer;
	GLint  viewsize_loc;
	GLint texturesize_loc;
	struct vtstack font_stack;
	struct vcstack box_stack;
	int width, height;
	int s_x, s_y, s_w, s_h;
} ren = {0};


static int ren_errno;


// print shader compilation errors
static int shader_compile_error(GLuint shader)
{
	GLint status;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);

	GLchar *log_str = emalloc((log_length + 1)*sizeof(GLchar));
	glGetShaderInfoLog(shader, log_length, NULL, log_str);

	const char *shader_type_str = NULL;
	GLint shader_type;
	glGetShaderiv(shader, GL_SHADER_TYPE, &shader_type);
	switch(shader_type) {
	case GL_VERTEX_SHADER:   shader_type_str = "vertex";   break;
	case GL_GEOMETRY_SHADER: shader_type_str = "geometry"; break;
	case GL_FRAGMENT_SHADER: shader_type_str = "fragment"; break;
	}

	fprintf(stderr, "Compile failure in %s shader:\n%s\n", shader_type_str, log_str);
	efree(log_str);
	return -1;
}


// print shader link errors
static int shader_link_error(GLuint prog)
{
	GLint status;
	glGetProgramiv (prog, GL_LINK_STATUS, &status);
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &log_length);

	GLchar *log_str = emalloc((log_length + 1)*sizeof(GLchar));
	glGetProgramInfoLog(prog, log_length, NULL, log_str);
	fprintf(stderr, "Linker failure: %s\n", log_str);
	efree(log_str);

	return -1;
}


#define REN_RET(a,b) {ren_errno = b; return a;}
static GLuint shader_compile(const char *shader, GLuint type)
{
	GLuint s;
	// initialize the vertex shader and get the corresponding id
	s = GL(glCreateShader(type))
	if (!s) REN_RET(0, REN_VERTEX)
	// get the shader into opengl
	GL(glShaderSource(s, 1, &shader, NULL))
	GL(glCompileShader(s))
	if (shader_compile_error(s))
		REN_RET(0, REN_COMPILE)
	return s;
}


const char * ren_strerror(void)
{
	return ren_err_msg[ren_errno % (sizeof(ren_err_msg)/sizeof(char *))];
}


// compile a vertex shader (vs_path) and a fragment shader (fs_path) into an opengl
// program and return it's index
static GLuint ren_compile_program(const char *vs_path, const char *fs_path)
{
	GLuint gl_vertshader, gl_fragshader, prog;

	if (!vs_path || !fs_path)
		REN_RET(0, REN_INVAL)

	char *str = NULL;

	dump_file(vs_path, &str, NULL);
	if (!str) REN_RET(0, REN_ERRNO)
	gl_vertshader = shader_compile(str, GL_VERTEX_SHADER);
	efree(str);
	if (!gl_vertshader)
		return 0;

	dump_file(fs_path, &str, NULL);
	if (!str) REN_RET(0, REN_ERRNO)
	gl_fragshader = shader_compile(str, GL_FRAGMENT_SHADER);
	efree(str);
	if (!gl_fragshader)
		return 0;


	// create the main program object, it is an amalgamation of all shaders
	prog = GL(glCreateProgram())
	if (!prog) REN_RET(0, REN_PROGRAM)

	// attach the shaders to the program (set which shaders are present)
	GL(glAttachShader(prog, gl_vertshader))
	GL(glAttachShader(prog, gl_fragshader))
	// then link the program (basically the linking stage of the program)
	GL(glLinkProgram(prog))
	if (shader_link_error(prog))
		REN_RET(0, REN_LINK)

	// after linking the shaders can be detached and the source freed from
	// memory since the program is ready to use
	GL(glDetachShader(prog, gl_vertshader))
	GL(glDetachShader(prog, gl_fragshader))

	return prog;
}


static GLuint ren_texturergb_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	GL(glGenTextures(1, &t))
	if (!t) REN_RET(0, REN_TEXTURE)

	GL(glBindTexture(GL_TEXTURE_2D, t))
	GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, w, h, 0, GL_RGB, GL_UNSIGNED_BYTE, buf))

	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale))

	return t;
}


static GLuint ren_texturergba_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	GL(glGenTextures(1, &t))
	if (!t) REN_RET(0, REN_TEXTURE)

	GL(glBindTexture(GL_TEXTURE_2D, t))
	GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf))

	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale))

	return t;
}


static GLuint ren_texturer_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	GL(glGenTextures(1, &t))
	if (!t) REN_RET(0, REN_TEXTURE)

	GL(glBindTexture(GL_TEXTURE_2D, t))
	GL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, w, h, 0, GL_RED, GL_UNSIGNED_BYTE, buf))

	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale))

	return t;
}


static GLuint ren_texturer_rect(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	GL(glGenTextures(1, &t))
	if (!t) REN_RET(0, REN_TEXTURE)

	GL(glBindTexture(GL_TEXTURE_RECTANGLE, t))
	GL(glTexImage2D(GL_TEXTURE_RECTANGLE, 0, GL_RED, w, h, 0, GL_RED, GL_UNSIGNED_BYTE, buf))

	// a limitation of recatngle textures is that the wrapping mode is limited 
	// to either clamp-to-edge or clamp-to-border
	GL(glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE))
	GL(glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE))
	GL(glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MIN_FILTER, downscale))
	GL(glTexParameteri(GL_TEXTURE_RECTANGLE, GL_TEXTURE_MAG_FILTER, upscale))

	return t;
}


// FIXME: update only the newly generated character instead of the whole texture
static int update_font_texture(void)
{
	glUseProgram(ren.font_prog);
	GL(glTexSubImage2D(
		GL_TEXTURE_RECTANGLE,
		0, 0, 0,
		ren.font->width,
		ren.font->height,
		GL_RED,
		GL_UNSIGNED_BYTE,
		ren.font->atlas))
	font_dump(ren.font, "./atlas.png");
	glUseProgram(0);
	return 0;
}


// TODO: push window size uniforms
int ren_init(SDL_Window *w)
{
	if (!w)
		REN_RET(-1, REN_INVAL)
	ren.gl = SDL_GL_CreateContext(w);
	if (!ren.gl)
		REN_RET(-1, REN_CONTEXT)
	
	// select some features
	GL(glEnable(GL_BLEND))
	GL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA))
	GL(glDisable(GL_CULL_FACE))
	GL(glDisable(GL_DEPTH_TEST))
	GL(glEnable(GL_SCISSOR_TEST))
	GL(glEnable(GL_TEXTURE_2D))
	GL(glEnable(GL_TEXTURE_RECTANGLE))

	GLenum glew_err = glewInit();
	if (glew_err != GLEW_OK)
		REN_RET(glew_err, REN_GLEW);

	ren.font = font_init();
	if (!ren.font) REN_RET(-1, REN_FONT) 
	if (font_load(ren.font, FONT_PATH, 20)) REN_RET(-1, REN_FONT)
	font_dump(ren.font, "./atlas.png");

	ren.font_texture = ren_texturer_rect(
		(const char *)ren.font->atlas,
		ren.font->width,
		ren.font->height,
		GL_LINEAR, GL_LINEAR);
	if (!ren.font_texture) return -1;

	ren.font_prog = ren_compile_program(FONT_VERSHADER, FONT_FRAGSHADER);
	if (!ren.font_prog) return -1;

	ren.font_stack = vtstack_init();
	ren.box_stack  = vcstack_init(); 

	// generate the font buffer object 
	GL(glGenBuffers(1, &ren.font_buffer))
	if (!ren.font_buffer) REN_RET(-1, REN_BUFFER)

	// create the uniforms, if the returned value is -1 then the uniform may have
	// been optimized away, in any case do not return, just give a warning
	ren.viewsize_loc = GL(glGetUniformLocation(ren.font_prog, "viewsize"))
	if (ren.viewsize_loc == -1)
		printf("uniform %s was optimized away\n", "viewsize");
	ren.texturesize_loc = GL(glGetUniformLocation(ren.font_prog, "texturesize"))
	if (ren.texturesize_loc == -1)
		printf("uniform %s was optimized away\n", "texturesize");

	int width, height;
	SDL_GetWindowSize(w, &width, &height);
	ren_update_viewport(width, height);
	GL(glClearColor(0.3f, 0.3f, 0.3f, 0.f))
	GL(glClear(GL_COLOR_BUFFER_BIT))

	return 0;
}


static int ren_draw_font_stack(void)
{
	GL(glUseProgram(ren.font_prog))
	GL(glBindBuffer(GL_ARRAY_BUFFER, ren.font_buffer))

	GL(glViewport(0, 0, ren.width, ren.height))
	GL(glScissor(0, 0, ren.width, ren.height))
	GL(glClear(GL_COLOR_BUFFER_BIT));
	// this has caused me some trouble, convert from image coordiates to viewport
	//GL(glScissor(ren.s_x, ren.height-ren.s_y-ren.s_h, ren.s_w, ren.s_h))
	GL(glUniform2i(ren.viewsize_loc, ren.width, ren.height))
	GL(glUniform2i(ren.texturesize_loc, ren.font->width, ren.font->height))

	GL(glEnableVertexAttribArray(REN_VERTEX_IDX))
	GL(glEnableVertexAttribArray(REN_UV_IDX))
	// when passing ints to glVertexAttribPointer they are automatically 
	// converted to floats
	GL(glVertexAttribPointer(
		REN_VERTEX_IDX,
		2,
		GL_INT,
		GL_FALSE,
		sizeof(struct v_text),
		0))
	GL(glVertexAttribPointer(
		REN_UV_IDX,
		2,
		GL_INT,
		GL_FALSE,
		sizeof(struct v_text),
		(void*)sizeof(vec2_i)))
	// TODO: implement size and damage tracking on stacks
	GL(glBufferData(
		GL_ARRAY_BUFFER,
		ren.font_stack.idx*sizeof(struct v_text),
		ren.font_stack.items,
		GL_DYNAMIC_DRAW))
	GL(glDrawArrays(GL_TRIANGLES, 0, ren.font_stack.idx))

	GL(glDisableVertexAttribArray(REN_VERTEX_IDX))
	GL(glDisableVertexAttribArray(REN_UV_IDX))
	GL(glBindBuffer(GL_ARRAY_BUFFER, 0))
	GL(glUseProgram(0))
	return 0;
}


int ren_update_viewport(int w, int h)
{
	ren.width = w;
	ren.height = h;
	return 0;
}


// TODO: add a scissor array in order to do less render calls
int ren_set_scissor(int x, int y, int w, int h)
{
	ren.s_x = x;
	ren.s_y = y;
	ren.s_w = w;
	ren.s_h = h;
	return 0;
}



// TODO: implement font size
int ren_render_text(const char *str, int x, int y, int w, int h, int size)
{
	// x4,y4        x3,y3
	// +-------------+
	// |(x,y)       /|
	// |          /  |
	// |   2    /    |
	// |      /      |
	// |    /        |
	// |  /     1    |
	// |/            |
	// +-------------+
	// x1,y1        x2,y2

	const struct font_glyph *g;
	struct font_glyph c;
	size_t ret, off;
	uint_least32_t cp;
	int updated, gx = x, gy = y;
	struct v_text v;
	printf("rendering text: %s\n", str);
	for (off = 0; (ret = grapheme_decode_utf8(str+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		g = font_get_glyph_texture(ren.font, cp, &updated);
		if (!g) REN_RET(-1, REN_FONT);
		if (updated) {
			if (update_font_texture())
				REN_RET(-1, REN_TEXTURE);
		}
		c = *g;
		//printf("g: u=%d v=%d w=%d h=%d a=%d x=%d y=%d\n", c.u, c.v, c.w, c.h, c.a, c.x, c.y);
		//printf("v: x=%d y=%d u=%d v=%d\n", v.pos.x, v.pos.y, v.uv.u, v.uv.v);
		// x1,y1
		v = (struct v_text){
			.pos = { .x = gx+c.x, .y = gy+c.y+c.h   },
			.uv  = { .u = c.u,    .v = c.v+c.h },
		};
		vtstack_push(&ren.font_stack, &v);
		// x2,y2
		v = (struct v_text){
			.pos = { .x = gx+c.x+c.w, .y = gy+c.y+c.h },
			.uv  = { .u = c.u+c.w,    .v = c.v+c.h },
		};
		vtstack_push(&ren.font_stack, &v);
		// x3,y3
		v = (struct v_text){
			.pos = { .x = gx+c.x+c.w, .y = gy+c.y },
			.uv  = { .u = c.u+c.w,    .v = c.v },
		};
		vtstack_push(&ren.font_stack, &v);
		// x1,y1
		v = (struct v_text){
			.pos = { .x = gx+c.x, .y = gy+c.y+c.h },
			.uv  = { .u = c.u,    .v = c.v+c.h },
		};
		vtstack_push(&ren.font_stack, &v);
		// x3,y3
		v = (struct v_text){
			.pos = { .x = gx+c.x+c.w, .y = gy+c.y },
			.uv  = { .u = c.u+c.w,    .v = c.v },
		};
		vtstack_push(&ren.font_stack, &v);
		// x4,y4
		v = (struct v_text){
			.pos = { .x = gx+c.x, .y = gy+c.y },
			.uv  = { .u = c.u,    .v = c.v },
		};
		vtstack_push(&ren.font_stack, &v);

		// TODO: possible kerning needs to be applied here
		// FIXME: advance is too large
		//gx += c.w + c.a;
		//gx += c.w + c.x + 1;
		gx += c.x + c.a;
		switch (cp) {
		case '\r':
			gx = x;
			break;
		case '\n':
			// TODO: encode and/or store line height
			gy = ren.font->glyph_max_h;
			gx = x;
			break;
		default: break;
		}
	}

	// FIXME: here we are doing one draw call for string of text which is 
	// inefficient but is simpler and allows for individual scissors
	ren_set_scissor(x, y, w, h);
	ren_draw_font_stack();
	vtstack_clear(&ren.font_stack);

	return 0;
}


int ren_free(void)
{
	GL(glUseProgram(0))
	GL(glBindBuffer(GL_ARRAY_BUFFER, 0))
	GL(glDeleteTextures(1, &ren.font_texture))
	GL(glDeleteBuffers(1, &ren.font_buffer))
	SDL_GL_DeleteContext(ren.gl);
	vtstack_free(&ren.font_stack);
	vcstack_free(&ren.box_stack);
	font_free(ren.font);
	return 0;
}
