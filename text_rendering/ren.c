#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>
#include <SDL2/SDL_video.h>
#include <grapheme.h>
#include <stdio.h>

#include "util.h"
#include "font.h"
#include "ren.h"


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


#define ELEM(x) [x] = #x,
const char *glerr[] = {
	ELEM(GL_INVALID_ENUM)
	ELEM(GL_INVALID_VALUE)
	ELEM(GL_INVALID_OPERATION)
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
	s = glCreateShader(type);
	if (!s) REN_RET(0, REN_VERTEX)
	// get the shader into opengl
	glShaderSource(s, 1, &shader, NULL);
	glCompileShader(s);
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
	prog = glCreateProgram();
	if (!prog) REN_RET(0, REN_PROGRAM)

	// attach the shaders to the program (set which shaders are present)
	glAttachShader(prog, gl_vertshader);
	glAttachShader(prog, gl_fragshader);
	// then link the program (basically the linking stage of the program)
	glLinkProgram(prog);
	if (shader_link_error(prog))
		REN_RET(0, REN_LINK)

	// after linking the shaders can be detached and the source freed from
	// memory since the program is ready to use
	glDetachShader(prog, gl_vertshader);
	glDetachShader(prog, gl_fragshader);

	return prog;
}


static GLuint ren_texturergb_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	glGenTextures(1, &t);
	if (!t) REN_RET(0, REN_TEXTURE)

	glBindTexture(GL_TEXTURE_2D, t);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, w, h, 0, GL_RGB, GL_UNSIGNED_BYTE, buf);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale);

	return t;
}


static GLuint ren_texturergba_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	glGenTextures(1, &t);
	if (!t) REN_RET(0, REN_TEXTURE)

	glBindTexture(GL_TEXTURE_2D, t);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale);

	return t;
}


static GLuint ren_texturer_2d(const char *buf, int w, int h, int upscale, int downscale)
{
	GLuint t;

	if (!buf || w <= 0 || h <= 0)
		REN_RET(0, REN_INVAL)

	glGenTextures(1, &t);
	if (!t) REN_RET(0, REN_TEXTURE)

	glBindTexture(GL_TEXTURE_2D, t);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_R, w, h, 0, GL_R, GL_UNSIGNED_BYTE, buf);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale);

	return t;
}



// FIXME: update only the newly generated character instead of the whole texture
static int update_font_texture(void)
{
	glTexSubImage2D(
		ren.font_texture,
		0, 0, 0,
		ren.font->width,
		ren.font->height,
		GL_R,
		GL_UNSIGNED_BYTE,
		ren.font->atlas);
	font_dump(ren.font, "./atlas.png");
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
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glEnable(GL_SCISSOR_TEST);
	glEnable(GL_TEXTURE_2D);

	GLenum glew_err = glewInit();
	if (glew_err != GLEW_OK)
		REN_RET(glew_err, REN_GLEW);

	ren.font = font_init();
	if (!ren.font) REN_RET(-1, REN_FONT) 
	if (font_load(ren.font, FONT_PATH, 20)) REN_RET(-1, REN_FONT)
	font_dump(ren.font, "./atlas.png");

	ren.font_texture = ren_texturer_2d(
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
	glGenBuffers(1, &ren.font_buffer);
	if (!ren.font_buffer) REN_RET(-1, REN_BUFFER)

	// create the uniforms
	ren.viewsize_loc = glGetUniformLocation(ren.font_prog, "viewsize");
	if (ren.viewsize_loc == -1) REN_RET(-1, REN_UNIFORM)
	ren.texturesize_loc = glGetUniformLocation(ren.font_prog, "texturesize");
	if (ren.texturesize_loc == -1) REN_RET(-1, REN_UNIFORM)

	int width, height;
	SDL_GetWindowSize(w, &width, &height);
	ren_update_viewport(width, height);
	glClearColor(0.3f, 0.3f, 0.3f, 0.f);
	glClear(GL_COLOR_BUFFER_BIT);

	return 0;
}

#define GLERR()  {int a = glGetError(); if (a != GL_NO_ERROR) printf("glError: %d %s\n", a, glerr[a]);}
static int ren_draw_font_stack(void)
{
	glUseProgram(ren.font_prog);
	glBindBuffer(GL_ARRAY_BUFFER, ren.font_buffer);

	glViewport(0, 0, ren.width, ren.height);
	glScissor(ren.s_x, ren.s_y, ren.s_w, ren.s_h);
	glUniform2i(ren.viewsize_loc, ren.width, ren.height);
	glUniform2i(ren.texturesize_loc, ren.font->width, ren.font->height);
	GLERR();

	glEnableVertexAttribArray(REN_VERTEX_IDX);
	glEnableVertexAttribArray(REN_UV_IDX);
	// when passing ints to glVertexAttribPointer they are automatically 
	// converted to floats
	glVertexAttribPointer(
		REN_VERTEX_IDX,
		2,
		GL_INT,
		GL_FALSE,
		sizeof(struct v_text),
		0);
	GLERR();
	glVertexAttribPointer(
		REN_UV_IDX,
		2,
		GL_INT,
		GL_FALSE,
		sizeof(struct v_text),
		(void*)sizeof(vec2_i));
	GLERR();
	// TODO: implement size and damage tracking on stacks
	glBufferData(
		GL_ARRAY_BUFFER,
		ren.font_stack.idx*sizeof(struct v_text),
		ren.font_stack.items,
		GL_DYNAMIC_DRAW);
	glDrawArrays(GL_TRIANGLES, 0, ren.font_stack.idx);
	GLERR();

	glDisableVertexAttribArray(REN_VERTEX_IDX);
	glDisableVertexAttribArray(REN_UV_IDX);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glUseProgram(0);
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
	size_t ret, off;
	uint_least32_t cp;
	int updated, gx = x, gy = y;
	struct v_text v;
	for (off = 0; (ret = grapheme_decode_utf8(str+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		g = font_get_glyph_texture(ren.font, cp, &updated);
		if (!g) REN_RET(-1, REN_FONT);
		if (updated) {
			if (update_font_texture())
				REN_RET(-1, REN_TEXTURE);
		}

		printf("g: u=%d v=%d w=%d h=%d a=%d x=%d y=%d\n", g->u, g->v, g->w, g->h, g->a, g->x, g->y);

		// x1,y1
		v = (struct v_text){
			.pos = { .x = gx+g->x, .y = gy+g->y+g->h   },
			.uv  = { .u = g->u,    .v = g->v+g->h },
		};
		vtstack_push(&ren.font_stack, &v);
		// x2,y2
		v = (struct v_text){
			.pos = { .x = gx+g->x+g->w, .y = gy+g->y+g->h   },
			.uv  = { .u = g->u+g->w,    .v = g->v+g->h },
		};
		vtstack_push(&ren.font_stack, &v);
		// x3,y3
		v = (struct v_text){
			.pos = { .x = gx+g->x+g->w, .y = gy+g->y   },
			.uv  = { .u = g->u+g->w,    .v = g->v },
		};
		vtstack_push(&ren.font_stack, &v);
		vtstack_push(&ren.font_stack, &v);
		// x4,y4
		v = (struct v_text){
			.pos = { .x = gx+g->x, .y = gy+g->y   },
			.uv  = { .u = g->u,    .v = g->v },
		};
		vtstack_push(&ren.font_stack, &v);
		// x1,y1
		v = (struct v_text){
			.pos = { .x = gx+g->x, .y = gy+g->y+g->h   },
			.uv  = { .u = g->u,    .v = g->v+g->h },
		};
		vtstack_push(&ren.font_stack, &v);

		// TODO: possible kerning needs to be applied here
		// FIXME: advance is too large
		//gx += g->w + g->a;
		gx += g->w + g->x + 1;
		if (cp == '\n')
			gy += ren.font->glyph_max_h; 
			// TODO: encode and/or store line height
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
	glUseProgram(0);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glDeleteTextures(1, &ren.font_texture);
	glDeleteBuffers(1, &ren.font_buffer);
	SDL_GL_DeleteContext(ren.gl);
	vtstack_free(&ren.font_stack);
	vcstack_free(&ren.box_stack);
	font_free(ren.font);
	return 0;
}
