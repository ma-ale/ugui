#include <stddef.h>
#define _POSIX_C_SOURCE 200809l

#include <sys/mman.h>
#include <arpa/inet.h>

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <err.h>

#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>


#define GLSL_VERT_SHADER "vertex.glsl"
#define GLSL_FRAG_SHADER "fragment.glsl"
#define PACKED __attribute__((packed))


const int vertindex = 0;
const int colindex  = 1;
const int textindex = 2;

struct {
	SDL_Window *w;
	SDL_GLContext *gl;
	GLuint gl_vertbuffer;
	GLuint gl_program;
	GLuint font_texture;
} ren = {0};

typedef struct PACKED {
	union { GLfloat x, u; };
	union { GLfloat y, v; };
} vec2;

typedef struct PACKED {
	union { GLfloat x, r; };
	union { GLfloat y, g; };
	union { GLfloat z, b; };
	union { GLfloat w, a; };
} vec4;

// a vertex has a position and a color
struct PACKED vertex { 
	vec2 pos;	
	vec2 texture;
	vec4 color;
};


int w_height(SDL_Window *);
int w_width(SDL_Window *);


//#define VNUM(s) (sizeof(s)/sizeof(s[0]))
//struct vertex vertbuffer[] = {
//	{ .pos={.x= 0.75f, .y= 0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//	{ .pos={.x=-0.75f, .y=-0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//	{ .pos={.x= 0.75f, .y=-0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//	{ .pos={.x= 0.75f, .y= 0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//	{ .pos={.x=-0.75f, .y=-0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//	{ .pos={.x=-0.75f, .y= 0.75f}, .col={ .r=1.0f, .g=0.0f, .b=0.0f, .a=1.0f} },
//};


// this just descrives a farbfeld image
// https://tools.suckless.org/farbfeld/
struct PACKED _ff {
	uint8_t magic[8];
	uint32_t w, h;
	uint64_t bytes[];
};
const int gw = 7, gh = 9;
unsigned int fw, fh;


struct {
	struct vertex *v;
	int size, idx;
} vstack = {0};


void grow_stack(int step)
{
	vstack.v = realloc(vstack.v, (vstack.size+step)*sizeof(*(vstack.v)));
	if(!vstack.v)
		err(-1, "Could not allocate stack #S: %s", strerror(errno));
	memset(&(vstack.v[vstack.size]), 0, step*sizeof(*(vstack.v)));
	vstack.size += step; 
}


int vstack_push_quad_c(int x, int y, int w, int h, vec4 color)
{
	if (vstack.idx <= vstack.size)
		grow_stack(6);
	
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

	int hw = w_width(ren.w)/2;
	int hh = w_width(ren.w)/2;

	float x1, x2, x3, x4;
	float y1, y2, y3, y4;

	x4 = x1 = (float)(x - hw)   / hw;
	x2 = x3 = (float)(x+w - hw) / hw;
	y4 = y3 = (float)(hh - y)   / hh;
	y1 = y2 = (float)(hh - y-h) / hh;

	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x1, .pos.y=y1, .color=color };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x2, .pos.y=y2, .color=color };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x3, .pos.y=y3, .color=color };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x1, .pos.y=y1, .color=color };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x3, .pos.y=y3, .color=color };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x4, .pos.y=y4, .color=color };

	return 0;
}


int vstack_push_quad_t(int x, int y, int w, int h, int u, int v)
{
	if (vstack.idx <= vstack.size)
		grow_stack(6);
	
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

	int hw = w_width(ren.w)/2;
	int hh = w_width(ren.w)/2;

	float x1, x2, x3, x4;
	float y1, y2, y3, y4;

	x1 = x4 = (float)(x - hw)   / hw;
	x2 = x3 = (float)(x+w - hw) / hw;
	y1 = y2 = (float)(hh - y-h) / hh;
	y3 = y4 = (float)(hh - y)   / hh;

	float u1, u2, u3, u4;
	float v1, v2, v3, v4;

	u1 = u4 = (float)(u)    / fw;
	u2 = u3 = (float)(u+gw) / fw;
	v1 = v2 = (float)(v+gh) / fh;
	v3 = v4 = (float)(v)    / fh;

	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x1, .pos.y=y1, .texture.x=u1, .texture.y=v1 };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x2, .pos.y=y2, .texture.x=u2, .texture.y=v2 };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x3, .pos.y=y3, .texture.x=u3, .texture.y=v3 };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x1, .pos.y=y1, .texture.x=u1, .texture.y=v1 };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x3, .pos.y=y3, .texture.x=u3, .texture.y=v3 };
	vstack.v[vstack.idx++] = (struct vertex){ .pos.x=x4, .pos.y=y4, .texture.x=u4, .texture.y=v4 };

	return 0;
}


void vstack_clear(void)
{
	vstack.idx = 0;
}


// copy the vertex buffer from system to video memory
void ren_initvertbuffer()
{
	// generate a buffer id
	glGenBuffers(1, &ren.gl_vertbuffer);
	// tell opengl that we want to work on that buffer
	glBindBuffer(GL_ARRAY_BUFFER, ren.gl_vertbuffer);
	// copy the vertex data into the gpu memory, GL_STATIC_DRAW tells opengl
	// that the data will be used for drawing (DRAW) and it will only be modified
	// every frame (DYNAMIC)
	glBufferData(GL_ARRAY_BUFFER, vstack.idx*sizeof(struct vertex), vstack.v, GL_DYNAMIC_DRAW);
	// set the format of each vertex, in this case each vertex is made of 4
	// coordinates, x y z w, where w is the clip coordinate, stride is
	// sizeof(vec4) since every postition vertex there is a vector representing
	// color data
	// set the position data of the vertex buffer, and bind it as input to the
	// vertex shader with an index of 0
	glEnableVertexAttribArray(vertindex);
	glVertexAttribPointer(vertindex, 2, GL_FLOAT, GL_FALSE, sizeof(struct vertex), 0);
	// set the color data of the vertex buffer to index 1
	// vertex attribute is the OpenGL name given to a set of vertices which are
	// given as input to a vertext shader, in a shader an array of vertices is
	// always referred to by index and not by pointer or other manners, indices
	// go from 0 to 15
	glEnableVertexAttribArray(colindex);
	glVertexAttribPointer(colindex, 4, GL_FLOAT, GL_FALSE, sizeof(struct vertex), (void*)(2*sizeof(vec2)));
	// texture uv data
	glEnableVertexAttribArray(textindex);
	glVertexAttribPointer(textindex, 2, GL_FLOAT, GL_FALSE, sizeof(struct vertex), (void*)sizeof(vec2));
	// reset the object bind so not to create errors
	glBindBuffer(GL_ARRAY_BUFFER, 0);
}


void map_file(const char **str, int *size, const char *fname)
{
	FILE *fp = fopen(fname, "r");
	*size = lseek(fileno(fp), 0, SEEK_END);
	*str = mmap(0, *size, PROT_READ, MAP_PRIVATE, fileno(fp), 0);
	fclose(fp);
}


// print shader compilation errors
int debug_shader(GLuint shader)
{
	GLint status;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);

	GLchar *log_str = malloc((log_length + 1)*sizeof(GLchar));
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
	free(log_str);
	return -1;
}


// print program compilation errors
int debug_program(GLuint prog)
{
	GLint status;
	glGetProgramiv (prog, GL_LINK_STATUS, &status);
	if (status != GL_FALSE)
		return 0;

	GLint log_length;
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &log_length);

	GLchar *log_str = malloc((log_length + 1)*sizeof(GLchar));
	glGetProgramInfoLog(prog, log_length, NULL, log_str);
	fprintf(stderr, "Linker failure: %s\n", log_str);
	free(log_str);

	return -1;
}


void ren_initshaders()
{
	GLuint gl_vertshader, gl_fragshader;

	// initialize the vertex shader and get the corresponding id
	gl_vertshader = glCreateShader(GL_VERTEX_SHADER);
	if (!gl_vertshader)
		err(-1, "Could not create the vertex shader");

	// map the shader file into memory
	const char *vshader_str = NULL;
	int vshader_size;
	map_file(&vshader_str, &vshader_size, GLSL_VERT_SHADER);

	// get the shader into opengl
	glShaderSource(gl_vertshader, 1, &vshader_str, NULL);
	// compile the shader
	glCompileShader(gl_vertshader);
	if (debug_shader(gl_vertshader))
		exit(EXIT_FAILURE);

	// do the same for the fragment shader
	// FIXME: make this a function
	gl_fragshader = glCreateShader(GL_FRAGMENT_SHADER);
	if (!gl_fragshader)
		err(-1, "Could not create the vertex shader");

	// map the shader file into memory
	const char *fshader_str = NULL;
	int fshader_size;
	map_file(&fshader_str, &fshader_size, GLSL_FRAG_SHADER);

	// get the shader into opengl
	glShaderSource(gl_fragshader, 1, &fshader_str, NULL);
	// compile the shader
	glCompileShader(gl_fragshader);
	if (debug_shader(gl_fragshader))
		exit(EXIT_FAILURE);

	// create the main program object, it is an amalgamation of all shaders
	ren.gl_program = glCreateProgram();
	// attach the shaders to the program (set which shaders are present)
	glAttachShader(ren.gl_program, gl_vertshader);
	glAttachShader(ren.gl_program, gl_fragshader);
	// then link the program (basically the linking stage of the program)
	glLinkProgram(ren.gl_program);
	if (debug_program(ren.gl_program))
		exit(EXIT_FAILURE);

	// after linking the shaders can be detached and the source freed from
	// memory since the program is ready to use
	glDetachShader(ren.gl_program, gl_vertshader);
	glDetachShader(ren.gl_program, gl_fragshader);
	munmap((void *)vshader_str, vshader_size);
	munmap((void *)fshader_str, fshader_size);

	// now tell opengl to use the program
	glUseProgram(ren.gl_program);
}


void ren_drawvertbuffer()
{
	glBindBuffer(GL_ARRAY_BUFFER, ren.gl_vertbuffer);
	glDrawArrays(GL_TRIANGLES, 0, vstack.idx);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
}


int w_height(SDL_Window *win)
{
	int h;
	SDL_GetWindowSize(win, NULL, &h);
	return h;
}


int w_width(SDL_Window *win)
{
	int w;
	SDL_GetWindowSize(win, &w, NULL);
	return w;
}


void import_font(const char *path)
{
	const char *map;
	int size;
	const struct _ff *img;

	map_file(&map, &size, path);
	img = (const struct _ff *)map;
	fw = ntohl(img->w);
	fh = ntohl(img->h);
 
	glGenTextures(1, &ren.font_texture);
	glBindTexture(GL_TEXTURE_2D, ren.font_texture);
	// farbfeld image
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, fw, fh, 0, GL_RGBA, GL_UNSIGNED_SHORT, img->bytes);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);	
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

	munmap((void *)map, size);
}


void push_text(int x, int y, const char *s)
{
	for (; *s; s++) {
		int u, v;
		int idx = *s - ' ';
		u = idx % (fw / gw);
		v = (idx / (fw / gw)) % (fh / gh);
		vstack_push_quad_t(x, y, gw*2, gh*2, u*gw, v*gh);
		x += gw*2;
		if (*s == '\n')
			y += gh;
	}
}


int main (void)
{
	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");

	ren.w = SDL_CreateWindow("test",
	SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
	500, 500, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE );

	// create the OpenGL context
	ren.gl = SDL_GL_CreateContext(ren.w);
	if (ren.gl == NULL)
		err(-1, "Failed to create OpenGL context: %s", SDL_GetError());

	// select some features
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glEnable(GL_SCISSOR_TEST);
	glEnable(GL_TEXTURE_2D);

	// initialize glew, this library gives us the declarations for most GL
	// functions, in the future it would be cool to do it manually
	GLenum glew_err = glewInit();
	if (glew_err != GLEW_OK)
		err(-1, "Failed to initialize GLEW: %s", glewGetErrorString(glew_err));

	ren_initshaders();
	import_font("./charmap.ff");

	vec4 magenta = {.r=1.0, .g=0.0, .b=1.0, .a=1.0};
	vstack_push_quad_c(0, 0, 100, 100, magenta);
	vstack_push_quad_c(200, 0, 10, 10, magenta);
	vstack_push_quad_c(10, 150, 100, 100, magenta);

	push_text(250, 250, "ò Ciao Victoria <3");
	ren_initvertbuffer();

	// event loop and drawing
	SDL_Event ev = {0};
	int running = 1;
	do {
		SDL_WaitEvent(&ev);
		switch (ev.type) {
		case SDL_QUIT: running = 0; break;
		default: break;
		}

		glViewport(0, 0, w_width(ren.w), w_height(ren.w));
		glClearColor(0.f, 0.f, 0.f, 0.f);
		glClear(GL_COLOR_BUFFER_BIT);

		ren_drawvertbuffer();

		SDL_GL_SwapWindow(ren.w);

	} while(running);

	glUseProgram(0);
	glDisableVertexAttribArray(vertindex);
	glDisableVertexAttribArray(colindex);
	SDL_GL_DeleteContext(ren.gl);
	SDL_DestroyWindow(ren.w);
	SDL_Quit();

	return 0;
}
