#ifndef _RENDERER_H
#define _RENDERER_H

#include <SDL2/SDL.h>


#define DEFAULT_FONT   "./monospace.ttf"
#define FONT_VERSHADER "./font_vertshader.glsl"
#define FONT_FRAGSHADER "./font_fragshader.glsl"
#define BOX_VERSHADER "./box_vertshader.glsl"
#define BOX_FRAGSHADER "./box_fragshader.glsl"
#define REN_VERTEX_IDX 0
#define REN_UV_IDX     1
#define REN_COLOR_IDX  2


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
	vec4_i col;
};


int ren_init(SDL_Window *sdl_window);
int ren_free(void);
const char * ren_strerror(void);
int ren_update_viewport(int w, int h);
int ren_set_scissor(int x, int y, int w, int h);
int ren_get_text_box(const char *str, int *rw, int *rh, int size);
int ren_render_text(const char *str, int x, int y, int w, int h, int size);
int ren_render_box(int x, int y, int w, int h, unsigned int color);
int ren_clear(void);


#endif
