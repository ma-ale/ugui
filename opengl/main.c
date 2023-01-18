#define _POSIX_C_SOURCE 200809l

#include <sys/mman.h>

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <err.h>

#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>


#define GLSL_VERT_SHADER "vertex.glsl"
#define GLSL_FRAG_SHADER "fragment.glsl"


struct {
	SDL_Window *w;
	SDL_GLContext *gl;
	GLuint gl_vertbuffer;
	GLuint gl_program;
} ren = {0};

#define VNUM(s, e) ((sizeof(s)/sizeof(s[0]))/e)
float vert[] = {
	 0.75f,  0.75f, 0.0f, 1.0f,
	-0.75f, -0.75f, 0.0f, 1.0f,
	 0.75f, -0.75f, 0.0f, 1.0f,
};


// copy the vertex buffer from system to video memory
void ren_initvertbuffer()
{
	// generate a buffer id
	glGenBuffers(1, &ren.gl_vertbuffer);
	// tell opengl that we want to work on that buffer
	glBindBuffer(GL_ARRAY_BUFFER, ren.gl_vertbuffer);
	// copy the vertex data into the gpu memory, GL_STATIC_DRAW tells opengl
	// that the data will be used for drawing (DRAW) and it will only be modified
	// once (STATIC)
	glBufferData(GL_ARRAY_BUFFER, sizeof(vert), &vert, GL_STATIC_DRAW);
	// set the data to generic vertex buffer, and bind it as input to the vertex
	// shader with an index of zero
	// vertex attribute is the OpenGL name given to a set of vertices which are
	// given as input to a vertext shader, in a shader an array of vertices is
	// always referred to by index and not by pointer or other manners, indices
	// go from 0 to 15
	int vertindex = 0;
	glEnableVertexAttribArray(vertindex);
	// set the format of each vertex, in this case each vertex is made of 4
	// coordinates, x y z w, where w is the clip coordinate
	glVertexAttribPointer(vertindex, 4, GL_FLOAT, GL_FALSE, 0, 0);
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
	glDrawArrays(GL_TRIANGLES, 0, VNUM(vert, 4));
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


int main (void)
{
	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");

	ren.w = SDL_CreateWindow("test",
	SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
	500, 500, SDL_WINDOW_OPENGL );

	// create the OpenGL context
	ren.gl = SDL_GL_CreateContext(ren.w);
	if (ren.gl == NULL)
		err(-1, "Failed to create OpenGL context: %s", SDL_GetError());

	// initialize glew, this library gives us the declarations for most GL
	// functions, in the future it would be cool to do it manually
	GLenum glew_err = glewInit();
	if (glew_err != GLEW_OK)
		err(-1, "Failed to initialize GLEW: %s", glewGetErrorString(glew_err));

	ren_initvertbuffer();
	ren_initshaders();

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
		glClearColor(1.f, 0.f, 1.f, 0.f);
		glClear(GL_COLOR_BUFFER_BIT);

		ren_drawvertbuffer();

		SDL_GL_SwapWindow(ren.w);

	} while(running);

	SDL_GL_DeleteContext(ren.gl);
	SDL_DestroyWindow(ren.w);
	SDL_Quit();

	return 0;
}
