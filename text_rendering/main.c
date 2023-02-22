#include <SDL2/SDL.h>
#include <SDL2/SDL_events.h>
#include <stdlib.h>
#include <stdio.h>

#include "ren.h"
#include "util.h"


int main(void)
{
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

	ren_render_text("ciao mamma", 0, 0, 100, 100, 12);
	SDL_GL_SwapWindow(win);

	SDL_Event e;
	while(1) {
		SDL_WaitEvent(&e);
		if (e.type == SDL_QUIT)
			break;
	}

	ren_free();
	SDL_DestroyWindow(win);
	SDL_Quit();
	return 0;
}
