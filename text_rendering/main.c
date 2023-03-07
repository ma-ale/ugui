#include <SDL2/SDL.h>
#include <SDL2/SDL_events.h>
#include <SDL2/SDL_video.h>
#include <stdlib.h>
#include <stdio.h>

#include "ren.h"
#include "util.h"


//const char *str1 = "Ciao Mamma!\nprova: òçà°ù§|¬³¼$£ì\t";
const char *str1 = "ciao\tmamma";
const char *str2 = "gmt";
SDL_Window *win;


void draw(void)
{
	static unsigned int frame = 0;
	printf("frame: %d\n", frame++);
	ren_clear();
	ren_render_box(10, 10, 400, 50, 0xffff0000);
	if (ren_render_text(str1, 10, 10, 400, 50, 20))
		printf("text: %s\n", ren_strerror());
	int w, h;
	ren_get_text_box(str2, &w, &h, 40);
	printf("box for: %s -> (%d, %d)\n", str2, w, h);
	ren_render_box(200, 40, w, h, 0xffff0000);
	ren_render_text(str2, 200, 40, 300, 300, 40);
	SDL_GL_SwapWindow(win);
}


int main(void)
{
	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
	SDL_SetHint(SDL_HINT_VIDEO_HIGHDPI_DISABLED, "0");

	win = SDL_CreateWindow(
		"test render",
		SDL_WINDOWPOS_UNDEFINED,
		SDL_WINDOWPOS_UNDEFINED,
		500,
		500,
		SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
	if (ren_init(win)) {
		printf("renderer init error: %s\n", ren_strerror());
		return 1;
	}


	int w, h;
	const char *s = "ciao mamma";
	ren_get_text_box(s, &w, &h, 12);
	printf("box for: %s -> (%d, %d)\n", s, w, h);


	SDL_Event e;
	while(1) {
		SDL_WaitEvent(&e);
		if (e.type == SDL_QUIT)
			break;
		if (e.type == SDL_WINDOWEVENT) {
			switch (e.window.event) {
			case SDL_WINDOWEVENT_RESIZED:
			case SDL_WINDOWEVENT_SIZE_CHANGED:
				ren_update_viewport(e.window.data1, e.window.data2);
				draw();
				break;
			case SDL_WINDOWEVENT_EXPOSED:
				draw();
				break;
			default: break;
			}
		}
	}

	ren_free();
	SDL_DestroyWindow(win);
	SDL_Quit();
	return 0;
}
