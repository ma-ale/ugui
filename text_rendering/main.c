#include <SDL2/SDL.h>
#include <SDL2/SDL_events.h>
#include <SDL2/SDL_video.h>
#include <stdlib.h>
#include <stdio.h>

#include "ren.h"
#include "util.h"


int main(void)
{
	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");

	SDL_Window *win = SDL_CreateWindow(
		"test render",
		SDL_WINDOWPOS_UNDEFINED,
		SDL_WINDOWPOS_UNDEFINED,
		500,
		500,
		SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
	if (ren_init(win)) {
		printf("renderer init error: %s\n", ren_strerror());
		return 1;
	}

	const char *str = "Ciao Mamma!\nprova: òçà°ù§|¬³¼$£ì\t";

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
				ren_render_text(str, 0, 0, 200, 100, 12);
				SDL_GL_SwapWindow(win);
				break;
			case SDL_WINDOWEVENT_EXPOSED:
				ren_render_text(str, 0, 0, 200, 100, 12);
				SDL_GL_SwapWindow(win);
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
