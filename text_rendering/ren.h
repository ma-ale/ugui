#ifndef _RENDERER_H
#define _RENDERER_H

#include <SDL2/SDL.h>


#define FONT_PATH "./monospace.ttf"
#define FONT_VERSHADER "./font_vertshader.glsl"
#define FONT_FRAGSHADER "./font_fragshader.glsl"
#define REN_VERTEX_IDX 0
#define REN_UV_IDX     1
#define REN_COLOR_IDX  2
#define REN_SCREENSIZE_LOC 0


typedef struct {
	union { int x, u; };
	union { int y, v; };
} vec2_i;

typedef struct {
	union { int x, r; };
	union { int y, g; };
	union { int z, b; };
	union { int w, a; };
} vec4_i;

// textured vertex
struct v_text {
	vec2_i pos;
	vec2_i uv;
};

// colored vertex
struct v_col {
	vec2_i pos;
	vec2_i col;
};


int ren_init(SDL_Window *sdl_window);
int ren_free(void);
const char * ren_strerror(void);
int ren_update_viewport(int w, int h);
int ren_render_text(const char *str, int x, int y, int w, int h, int size);


#endif
