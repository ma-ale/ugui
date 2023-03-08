#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>
#include <SDL2/SDL_video.h>
#include <ctype.h>
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
			__FILE__, __LINE__, __func__, x, a, glerr[a&0xff]);    \
}
#define GL(f) f; GLERR(#f)
#define REN_RET(a,b) {ren_errno = b; return a;}


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

#define ELEM(x) [x&0xff] = #x,
const char *glerr[] = {
	ELEM(GL_INVALID_ENUM)
	ELEM(GL_INVALID_VALUE)
	ELEM(GL_INVALID_OPERATION)
	ELEM(GL_OUT_OF_MEMORY)
};
#undef ELEM


// different stacks
#include "generic_stack.h"
STACK_DECL(vtstack, struct v_text)
STACK_DECL(vcstack, struct v_col)


struct ren_font {
	struct font_atlas *font;
	GLuint texture;
};

struct {
	SDL_GLContext *gl;
	struct ren_font *fonts;
	int fonts_no;
	GLuint font_prog;
	GLuint box_prog;
	GLuint font_buffer;
	GLuint box_buffer;
	GLint  viewsize_loc;
	GLint  box_viewsize_loc;
	GLint texturesize_loc;
	struct vtstack font_stack;
	struct vcstack box_stack;
	int width, height;
	int s_x, s_y, s_w, s_h;
	int tabsize;
} ren = {0};


static int ren_errno;


// print shader compilation errors
static int shader_compile_error(GLuint shader, const char *path)
{
	GLint status;
	GL(glGetShaderiv(shader, GL_COMPILE_STATUS, &status))
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	GL(glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length))

	GLchar *log_str = emalloc((log_length + 1)*sizeof(GLchar));
	GL(glGetShaderInfoLog(shader, log_length, NULL, log_str))

	const char *shader_type_str = NULL;
	GLint shader_type;
	GL(glGetShaderiv(shader, GL_SHADER_TYPE, &shader_type))
	switch(shader_type) {
	case GL_VERTEX_SHADER:   shader_type_str = "vertex";   break;
	case GL_GEOMETRY_SHADER: shader_type_str = "geometry"; break;
	case GL_FRAGMENT_SHADER: shader_type_str = "fragment"; break;
	}

	fprintf(stderr, "Compile failure in %s shader %s:\n%s\n", shader_type_str, path, log_str);
	efree(log_str);
	return -1;
}


// print shader link errors
static int shader_link_error(GLuint prog)
{
	GLint status;
	GL(glGetProgramiv(prog, GL_LINK_STATUS, &status))
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	GL(glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &log_length))

	GLchar *log_str = emalloc((log_length + 1)*sizeof(GLchar));
	GL(glGetProgramInfoLog(prog, log_length, NULL, log_str))
	fprintf(stderr, "Linker failure: %s\n", log_str);
	efree(log_str);

	return -1;
}


static GLuint shader_compile(const char *path, const char *shader, GLuint type)
{
	GLuint s;
	// initialize the vertex shader and get the corresponding id
	s = GL(glCreateShader(type))
	if (!s) REN_RET(0, REN_VERTEX)
	// get the shader into opengl
	GL(glShaderSource(s, 1, &shader, NULL))
	GL(glCompileShader(s))
	if (shader_compile_error(s, path))
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
	gl_vertshader = shader_compile(vs_path, str, GL_VERTEX_SHADER);
	efree(str);
	if (!gl_vertshader)
		return 0;

	dump_file(fs_path, &str, NULL);
	if (!str) REN_RET(0, REN_ERRNO)
	gl_fragshader = shader_compile(fs_path, str, GL_FRAGMENT_SHADER);
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


static void set_texture_parameters(GLuint type, GLuint wrap_s, GLuint wrap_t, GLuint upscale, GLuint downscale)
{
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap_s))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap_t))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, upscale))
	GL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, downscale))
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

	set_texture_parameters(GL_TEXTURE_2D, GL_REPEAT, GL_REPEAT, upscale, downscale);

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
	set_texture_parameters(GL_TEXTURE_2D, GL_REPEAT, GL_REPEAT, upscale, downscale);

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
	set_texture_parameters(GL_TEXTURE_2D, GL_REPEAT, GL_REPEAT, upscale, downscale);

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
	set_texture_parameters(GL_TEXTURE_RECTANGLE, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE, upscale, downscale);

	return t;
}


// FIXME: update only the newly generated character instead of the whole texture
static int update_font_texture(int idx)
{
	GL(glUseProgram(ren.font_prog))
	GL(glTexSubImage2D(
		GL_TEXTURE_RECTANGLE,
		0, 0, 0,
		ren.fonts[idx].font->width,
		ren.fonts[idx].font->height,
		GL_RED,
		GL_UNSIGNED_BYTE,
		ren.fonts[idx].font->atlas))
	font_dump(ren.fonts[idx].font, "./atlas.png");
	GL(glUseProgram(0));
	return 0;
}


// loads a font and returns it's index in the fonts array
static int ren_load_font(int size, const char *path)
{
	int idx = ren.fonts_no;
	struct font_atlas *f;
	ren.fonts = erealloc(ren.fonts, sizeof(struct ren_font)*(idx+1));
	ren.fonts[idx].font = font_init();
	f = ren.fonts[idx].font;
	if (!f)
		REN_RET(-1, REN_FONT)

	if (!path)
		path = DEFAULT_FONT;

	if (font_load(f, path, size))
		REN_RET(-1, REN_FONT)
	font_dump(f, "./atlas.png");

	// load font texture (atlas)
	ren.fonts[idx].texture = ren_texturer_rect(
		(const char *)f->atlas,
		f->width,
		f->height,
		GL_LINEAR, GL_LINEAR);
	if (!ren.fonts[idx].texture)
		return -1;

	ren.fonts_no = idx+1;
	return idx;
}


// returns the index to the ren.fonts array to the font with the correct size
// return -1 on errror
static int ren_get_font(int size)
{
	for (int i = 0; i < ren.fonts_no; i++) {
		if (ren.fonts[i].font->size == size)
			return i;
	}
	// TODO: add a way to change font family
	return ren_load_font(size, NULL);
}


int ren_init(SDL_Window *w)
{
	// Initialize OpenGL
	if (!w)
		REN_RET(-1, REN_INVAL)
	// using version 3 does not allow to use glVertexAttribPointer() without
	// vertex buffer objects, so use compatibility mode
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	ren.gl = SDL_GL_CreateContext(w);
	if (!ren.gl) {
		printf("SDL: %s\n", SDL_GetError());
		REN_RET(-1, REN_CONTEXT)
	}

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

	// Create stacks
	ren.font_stack = vtstack_init();
	ren.box_stack  = vcstack_init();
	// generate the font buffer object
	GL(glGenBuffers(1, &ren.font_buffer))
	if (!ren.font_buffer) REN_RET(-1, REN_BUFFER)
	GL(glGenBuffers(1, &ren.box_buffer))
	if (!ren.box_buffer) REN_RET(-1, REN_BUFFER)

	// Compile font shaders
	ren.font_prog = ren_compile_program(FONT_VERSHADER, FONT_FRAGSHADER);
	if (!ren.font_prog) return -1;
	// create the uniforms, if the returned value is -1 then the uniform may have
	// been optimized away, in any case do not return, just give a warning
	ren.viewsize_loc = GL(glGetUniformLocation(ren.font_prog, "viewsize"))
	if (ren.viewsize_loc == -1)
		printf("uniform %s was optimized away\n", "viewsize");
	ren.texturesize_loc = GL(glGetUniformLocation(ren.font_prog, "texturesize"))
	if (ren.texturesize_loc == -1)
		printf("uniform %s was optimized away\n", "texturesize");

	// Compile box shaders
	ren.box_prog = ren_compile_program(BOX_VERSHADER, BOX_FRAGSHADER);
	if (!ren.box_prog) return -1;
	ren.box_viewsize_loc = GL(glGetUniformLocation(ren.box_prog, "viewsize"))
	if (ren.box_viewsize_loc == -1)
		printf("uniform %s was optimized away\n", "viewsize");

	// Finishing touches
	ren.tabsize = REN_TABSIZE;
	int width, height;
	SDL_GetWindowSize(w, &width, &height);
	ren_update_viewport(width, height);
	GL(glClearColor(0.3f, 0.3f, 0.3f, 0.f))
	GL(glClear(GL_COLOR_BUFFER_BIT))

	return 0;
}


int ren_clear(void)
{
	GL(glScissor(0, 0, ren.width, ren.height))
	GL(glClear(GL_COLOR_BUFFER_BIT));
	return 0;
}


// idx refers to the fonts array index, this means that when drawing the font stack
// only one font size at the time can be used
static int ren_draw_font_stack(int idx)
{
	struct font_atlas *font = ren.fonts[idx].font;
	GLuint font_texture = ren.fonts[idx].texture;

	GL(glUseProgram(ren.font_prog))
	GL(glBindTexture(GL_TEXTURE_RECTANGLE, font_texture))

	GL(glViewport(0, 0, ren.width, ren.height))
	// this has caused me some trouble, convert from image coordiates to viewport
	GL(glScissor(ren.s_x, ren.height-ren.s_y-ren.s_h, ren.s_w, ren.s_h))
	GL(glUniform2i(ren.viewsize_loc, ren.width, ren.height))
	GL(glUniform2i(ren.texturesize_loc, font->width, font->height))

	GL(glBindBuffer(GL_ARRAY_BUFFER, ren.font_buffer))
	if (vtstack_changed(&ren.font_stack)) {
		if (vtstack_size_changed(&ren.font_stack)) {
			GL(glBufferData(
				GL_ARRAY_BUFFER,
				ren.font_stack.idx*sizeof(struct v_text),
				ren.font_stack.items,
				GL_DYNAMIC_DRAW))
		} else {
			GL(glBufferSubData(
				GL_ARRAY_BUFFER,
				0,
				ren.font_stack.idx*sizeof(struct v_text),
				ren.font_stack.items))
		}
	}
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
	GL(glEnableVertexAttribArray(REN_VERTEX_IDX))
	GL(glEnableVertexAttribArray(REN_UV_IDX))

	GL(glDrawArrays(GL_TRIANGLES, 0, ren.font_stack.idx))

	GL(glDisableVertexAttribArray(REN_VERTEX_IDX))
	GL(glDisableVertexAttribArray(REN_UV_IDX))
	GL(glBindBuffer(GL_ARRAY_BUFFER, 0))
	GL(glBindTexture(GL_TEXTURE_RECTANGLE, 0))
	GL(glUseProgram(0))

	vtstack_clear(&ren.font_stack);
	return 0;
}


static int ren_draw_box_stack(void)
{
	GL(glUseProgram(ren.box_prog))

	GL(glViewport(0, 0, ren.width, ren.height))
	GL(glScissor(0, 0, ren.width, ren.height))
	GL(glUniform2i(ren.box_viewsize_loc, ren.width, ren.height))

	GL(glBindBuffer(GL_ARRAY_BUFFER, ren.box_buffer))
	if(vcstack_changed(&ren.box_stack)) {
		if (vcstack_size_changed(&ren.box_stack)) {
			GL(glBufferData(
				GL_ARRAY_BUFFER,
				ren.box_stack.idx*sizeof(struct v_col),
				ren.box_stack.items,
				GL_DYNAMIC_DRAW))
		} else {
			GL(glBufferSubData(
				GL_ARRAY_BUFFER,
				0,
				ren.box_stack.idx*sizeof(struct v_col),
				ren.box_stack.items))
		}
	}
	// when passing ints to glVertexAttribPointer they are automatically
	// converted to floats
	GL(glVertexAttribPointer(
		REN_VERTEX_IDX,
		2,
		GL_INT,
		GL_FALSE,
		sizeof(struct v_col),
		0))
	// the color gets normalized
	GL(glVertexAttribPointer(
		REN_COLOR_IDX,
		4,
		GL_INT,
		GL_TRUE,
		sizeof(struct v_col),
		(void*)sizeof(vec2_i)))
	GL(glEnableVertexAttribArray(REN_VERTEX_IDX))
	GL(glEnableVertexAttribArray(REN_COLOR_IDX))

	GL(glDrawArrays(GL_TRIANGLES, 0, ren.box_stack.idx))

	GL(glDisableVertexAttribArray(REN_VERTEX_IDX))
	GL(glDisableVertexAttribArray(REN_COLOR_IDX))
	GL(glBindBuffer(GL_ARRAY_BUFFER, 0))
	GL(glUseProgram(0))

	vcstack_clear(&ren.box_stack);
	return 0;
}


int ren_update_viewport(int w, int h)
{
	ren.width = w;
	ren.height = h;
	return 0;
}


int ren_set_scissor(int x, int y, int w, int h)
{
	ren.s_x = x;
	ren.s_y = y;
	ren.s_w = w;
	ren.s_h = h;
	return 0;
}


static int ren_push_glyph(const struct font_glyph *g, int gx, int gy)
{
	/* x4,y4        x3,y3
	 * o-------------+
	 * |(x,y)       /|
	 * |          /  |
	 * |   2    /    |
	 * |      /      |
	 * |    /        |
	 * |  /     1    |
	 * |/            |
	 * +-------------+
	 * x1,y1        x2,y2 */
	struct v_text v;
	struct font_glyph c;
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

	return 0;
}


static const struct font_glyph * get_glyph(unsigned int code, int idx)
{
	const struct font_glyph *g;
	int updated;
	g = font_get_glyph_texture(ren.fonts[idx].font, code, &updated);
	if (!g)
		REN_RET(NULL, REN_FONT);
	if (updated) {
		if (update_font_texture(idx))
			REN_RET(NULL, REN_TEXTURE);
	}
	return g;
}


// TODO: reduce repeating patterns in ren_get_text_box() and ren_render_text()
int ren_get_text_box(const char *str, int *rw, int *rh, int size)
{
	int w = 0, h = 0, x = 0, y = 0;
	const struct font_glyph *g;
	size_t off, ret;
	uint32_t cp;
	int idx = ren_get_font(size);
	if (idx < 0)
		return -1;

	h = y = ren.fonts[idx].font->glyph_max_h;
	for (off = 0; (ret = grapheme_decode_utf8(str+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		if (iscntrl(cp)) goto skip_get;
		if (!(g = get_glyph(cp, idx)))
			return -1;

		x += g->x + g->a;
		// FIXME: generalize this thing
		skip_get:
		switch (cp) {
		case '\t': {
			const struct font_glyph *sp = get_glyph(' ', idx);
			if (!sp) return -1;
			x += (sp->x + sp->a)*ren.tabsize;
		}
		break;
		case '\r':
			x = 0;
			break;
		case '\n':
			// TODO: encode and/or store line height
			y += ren.fonts[idx].font->glyph_max_h;
			x = 0;
			break;
		default: break;
		}

		if (x > w) w = x;
		if (y > h) h = y;
	}

	if (rw) *rw = w;
	if (rh) *rh = h;

	return 0;
}


int ren_render_text(const char *str, int x, int y, int w, int h, int size)
{
	const struct font_glyph *g;
	size_t ret, off;
	uint32_t cp;
	int gx = x, gy = y;
	int idx = ren_get_font(size);
	if (idx < 0)
		return -1;
	for (off = 0; (ret = grapheme_decode_utf8(str+off, SIZE_MAX, &cp)) > 0 && cp != 0; off += ret) {
		// skip special characters that render a box (not present in font)
		if (iscntrl(cp)) goto skip_render;
		if (!(g = get_glyph(cp, idx)))
			return -1;

		// only push the glyph if it is inside the bounding box
		if (gx <= x+w && gy <= y+h)
			ren_push_glyph(g, gx, gy);
		// TODO: possible kerning needs to be applied here
		// TODO: handle other unicode control characters such as the
		//       right-to-left isolate (\u2067)
		gx += g->x + g->a;
		skip_render:
		switch (cp) {
		case '\t': {
			const struct font_glyph *sp = get_glyph(' ', idx);
			if (!sp) return -1;
			gx += (sp->x + sp->a)*ren.tabsize;
		}
		break;
		case '\r':
			gx = x;
			break;
		case '\n':
			gy += ren.fonts[idx].font->glyph_max_h;
			gx = x;
			break;
		default: break;
		}
	}

	ren_set_scissor(x, y, w, h);
	ren_draw_font_stack(idx);

	return 0;
}


// re-normalize color from 0-255 to 0-0x7fffffff, technically i'm dividing by 256 here
#define RENORM(x) (((unsigned long long)(x)*0x7fffffff)>>8)
#define R(x) (x&0xff)
#define G(x) ((x>>8)&0xff)
#define B(x) ((x>>16)&0xff)
#define A(x) ((x>>24)&0xff)
static int ren_push_box(int x, int y, int w, int h, unsigned int color)
{
	/* x4,y4        x3,y3
	 * o-------------+
	 * |(x,y)       /|
	 * |          /  |
	 * |   2    /    |
	 * |      /      |
	 * |    /        |
	 * |  /     1    |
	 * |/            |
	 * +-------------+
	 * x1,y1        x2,y2 */
	struct v_col v;
	vec4_i c = {
		.r = RENORM(R(color)),
		.g = RENORM(G(color)),
		.b = RENORM(B(color)),
		.a = RENORM(A(color)),
	};
	// x1, y1
	v = (struct v_col){ .pos = { .x = x, .y = y+h }, .col = c };
	vcstack_push(&ren.box_stack, &v);
	// x2, y2
	v = (struct v_col){ .pos = { .x = x+w, .y = y+h }, .col = c };
	vcstack_push(&ren.box_stack, &v);
	// x3, y3
	v = (struct v_col){ .pos = { .x = x+w, .y = y }, .col = c };
	vcstack_push(&ren.box_stack, &v);
	// x1, y1
	v = (struct v_col){ .pos = { .x = x, .y = y+h }, .col = c };
	vcstack_push(&ren.box_stack, &v);
	// x3, y3
	v = (struct v_col){ .pos = { .x = x+w, .y = y }, .col = c };
	vcstack_push(&ren.box_stack, &v);
	// x4, y4
	v = (struct v_col){ .pos = { .x = x, .y = y }, .col = c };
	vcstack_push(&ren.box_stack, &v);

	return 0;
}


int ren_render_box(int x, int y, int w, int h, unsigned int color)
{
	ren_push_box(x, y, w, h, color);
	ren_draw_box_stack();
	return 0;
}


int ren_free(void)
{
	GL(glUseProgram(0))
	GL(glBindBuffer(GL_ARRAY_BUFFER, 0))
	GL(glDeleteProgram(ren.box_prog));
	GL(glDeleteProgram(ren.font_prog));
	GL(glDeleteBuffers(1, &ren.font_buffer))
	for (int i = 0; i < ren.fonts_no; i++) {
		GL(glDeleteTextures(1, &ren.fonts[i].texture))
		font_free(ren.fonts[i].font);
	}
	SDL_GL_DeleteContext(ren.gl);
	vtstack_free(&ren.font_stack);
	vcstack_free(&ren.box_stack);
	return 0;
}
