#include <SDL2/SDL.h>
#include <GL/glew.h>
#include <SDL2/SDL_opengl.h>


#define GLSL_VERT_SHADER "vertex.glsl"
#define GLSL_FRAG_SHADER "fragment.glsl"
#define PACKED __attribute__((packed))


struct {
	SDL_Window *w;
	SDL_GLContext *gl;
	GLuint gl_vertbuffer;
	GLuint gl_program;
	GLuint font_texture;
} ren = {0};


typedef struct PACKED {
	union { GLint x, u; };
	union { GLint y, v; };
} vec2_i;

typedef struct PACKED {
	union { GLint x, r; };
	union { GLint y, g; };
	union { GLint z, b; };
	union { GLint w, a; };
} vec4_i;

// textured vertex
struct PACKED v_text {
	vec2_i pos;
	vec2_i uv;
};

// colored vertex
struct PACKED v_col {
	vec2_i pos;
	vec2_i col;
};


// different stacks
#define _STACK_NAME vtstack
#define _STACK_TYPE struct v_text
#include "stack.h"
#undef _STACK_NAME
#undef _STACK_TYPE
#define _STACK_NAME vcstack
#define _STACK_TYPE struct v_col
#include "stack.h"
