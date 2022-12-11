#include <stdio.h>
#include <SDL2/SDL.h>

#include "../ugui.h"

#define STB_RECT_PACK_IMPLEMENTATION
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTTF_IMPLEMENTATION
#include "stbttf.h"


SDL_Window *w;
SDL_Renderer *r;
ug_ctx_t *ctx;
STBTTF_Font *font;

void cleanup(void);

int main(void)
{
	SDL_DisplayMode dm;

	SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
	SDL_EnableScreenSaver();
	SDL_EventState(SDL_DROPFILE, SDL_ENABLE);	
	SDL_EventState(SDL_DROPTEXT, SDL_ENABLE);

	SDL_GetDesktopDisplayMode(0, &dm);

#ifdef SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR /* Available since 2.0.8 */
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
#endif

#if SDL_VERSION_ATLEAST(2, 0, 5)
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
#endif

	w = SDL_CreateWindow("test", 
	                     SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
	                     dm.w*0.8, dm.h*0.8, 
			     SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI |
	                     SDL_WINDOW_OPENGL );

	//SDL_Surface *s;
	//s = SDL_GetWindowSurface(w);
	r = SDL_CreateRenderer(w, -1, SDL_RENDERER_ACCELERATED);
	SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);

	ug_vec2_t size, dsize;
	SDL_GetWindowSize(w, &size.w, &size.h);
	SDL_GL_GetDrawableSize(w, &dsize.w, &dsize.h);
	float scale = 1.0;
	scale = ((float)(size.w+size.h)/2)/((float)(dsize.w+dsize.h)/2);
	
	float dpi;
	int idx;
	idx = SDL_GetWindowDisplayIndex(w);
	SDL_GetDisplayDPI(idx, &dpi, NULL, NULL);


	ctx = ug_ctx_new();
	ug_ctx_set_displayinfo(ctx, scale, dpi);
	ug_ctx_set_drawableregion(ctx, dsize);

	// open font
	font = STBTTF_OpenFont(r, "monospace.ttf", ctx->style_px->text.size.size.i);

//	atexit(cleanup);

	SDL_Event event;

	char button_map[] = {
		[SDL_BUTTON_LEFT   & 0xff] = UG_BTN_LEFT, 
		[SDL_BUTTON_MIDDLE & 0xff] = UG_BTN_MIDDLE, 
		[SDL_BUTTON_RIGHT  & 0xff] = UG_BTN_RIGHT, 
		[SDL_BUTTON_X1     & 0xff] = UG_BTN_4, 
		[SDL_BUTTON_X2     & 0xff] = UG_BTN_5, 
	};
	
	do {
	SDL_WaitEvent(&event);

		switch (event.type) {
		case SDL_WINDOWEVENT:
	        	switch (event.window.event) {
			case SDL_WINDOWEVENT_SHOWN:
				(SDL_Log("Window %d shown", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_HIDDEN:
				(SDL_Log("Window %d hidden", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_EXPOSED:
				(SDL_Log("Window %d exposed", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_MOVED:
				(SDL_Log("Window %d moved to %d,%d",
				event.window.windowID, event.window.data1,
				event.window.data2));
				break;
			case SDL_WINDOWEVENT_RESIZED:
				(SDL_Log("Window %d resized to %dx%d",
				event.window.windowID, event.window.data1,
				event.window.data2));
				break;
			case SDL_WINDOWEVENT_SIZE_CHANGED:
				(SDL_Log("Window %d size changed to %dx%d",
				event.window.windowID, event.window.data1,
				event.window.data2));

				size.w = event.window.data1;
				size.h = event.window.data2;
				// surface is invalidated every time the window
				// is resized
				//s = SDL_GetWindowSurface(w);
				ug_ctx_set_drawableregion(ctx, size);

				break;
			case SDL_WINDOWEVENT_MINIMIZED:
				(SDL_Log("Window %d minimized", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_MAXIMIZED:
				(SDL_Log("Window %d maximized", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_RESTORED:
				(SDL_Log("Window %d restored", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_ENTER:
				(SDL_Log("Mouse entered window %d",
					event.window.windowID));
				break;
			case SDL_WINDOWEVENT_LEAVE:
				(SDL_Log("Mouse left window %d", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_FOCUS_GAINED:
				(SDL_Log("Window %d gained keyboard focus",
				event.window.windowID));
				break;
			case SDL_WINDOWEVENT_FOCUS_LOST:
				(SDL_Log("Window %d lost keyboard focus",
				event.window.windowID));
				break;
			case SDL_WINDOWEVENT_CLOSE:
				(SDL_Log("Window %d closed", event.window.windowID));
				break;
#if SDL_VERSION_ATLEAST(2, 0, 5)
			case SDL_WINDOWEVENT_TAKE_FOCUS:
				(SDL_Log("Window %d is offered a focus", event.window.windowID));
				break;
			case SDL_WINDOWEVENT_HIT_TEST:
				(SDL_Log("Window %d has a special hit test", event.window.windowID));
				break;
#endif
			default:
				(SDL_Log("Window %d got unknown event %d",
				event.window.windowID, event.window.event));
				break;
			}
			break;
		case SDL_QUIT:
			(printf("Quitting\n"));
			break;
		case SDL_MOUSEMOTION:

			ug_input_mousemove(ctx, event.motion.x, event.motion.y);

			break;
		case SDL_MOUSEBUTTONDOWN:
			ug_input_mousemove(ctx, event.button.x, event.button.y);
			ug_input_mousedown(ctx, button_map[event.button.button & 0xff]);

			break;
		case SDL_MOUSEBUTTONUP:

			ug_input_mousemove(ctx, event.button.x, event.button.y);
			ug_input_mouseup(ctx, button_map[event.button.button & 0xff]);

			break;
		default:
			(printf("Unknown event: %d\n", event.type));
			break;
		}


		ug_frame_begin(ctx);

		if (ctx->frame < 5000) {
			ug_container_menu_bar(ctx, "Menu fichissimo", (ug_size_t)SIZE_PX(24));
		} else if (ctx->frame == 5000) {
			ug_container_remove(ctx, "Menu fichissimo");
		}

		ug_container_floating(ctx, "stupid name", 
		                      (ug_div_t){.x=SIZE_PX(0), .y=SIZE_PX(0), .w=SIZE_PX(100), .h=SIZE_MM(75.0)});

		//ug_container_floating(ctx, "floating windoooooooow", 
		//                      (ug_div_t){.x=SIZE_PX(100), .y=SIZE_PX(0), .w=SIZE_PX(100), .h=SIZE_MM(75.0)});

		ug_container_sidebar(ctx, "Right Sidebar", (ug_size_t)SIZE_PX(300), UG_SIDE_RIGHT);
		ug_container_sidebar(ctx, "Left Sidebar", (ug_size_t)SIZE_PX(200), UG_SIDE_LEFT);
		ug_container_sidebar(ctx, "Bottom Sidebar", (ug_size_t)SIZE_MM(10), UG_SIDE_BOTTOM);
		ug_container_sidebar(ctx, "Top Sidebar", (ug_size_t)SIZE_MM(40), UG_SIDE_TOP);

		//ug_container_floating(ctx, "stupid er", 
		//                      (ug_div_t){.x=SIZE_PX(150), .y=SIZE_PX(-100), .w=SIZE_PX(100), .h=SIZE_MM(75.0)});
		ug_container_popup(ctx, "Annoying popup", (ug_div_t){.x=SIZE_MM(150), .y=SIZE_MM(150), .w=SIZE_PX(100), .h=SIZE_MM(75.0)});

		ug_container_body(ctx, "Main Body");
		if (ug_container_body(ctx, "Other Body"))
			printf("No space!\n");

		ug_frame_end(ctx);

		// fill background
		SDL_SetRenderDrawColor(r, 0, 0, 0, 0xff);
		SDL_RenderClear(r);
		for (int i = 0; i < ctx->cmd_stack.idx; i++) {
			ug_cmd_t cmd = ctx->cmd_stack.items[i];
			switch (cmd.type) {
			case UG_CMD_RECT:
				{
				ug_color_t col = cmd.rect.color;
				SDL_Rect sr = {
					.x = cmd.rect.x,
					.y = cmd.rect.y,
					.w = cmd.rect.w,
					.h = cmd.rect.h,
				};
				SDL_SetRenderDrawColor(r, col.r, col.g, col.b, col.a);
				SDL_RenderFillRect(r, &sr);
				}
				break;
			case UG_CMD_TEXT:
			SDL_SetRenderDrawColor(r, cmd.text.color.r, cmd.text.color.g, cmd.text.color.b, cmd.text.color.a);
				STBTTF_RenderText(r, font, cmd.text.x, cmd.text.y, cmd.text.str);
				break;
			default: break;
			}
		}
		SDL_RenderPresent(r);

	} while (event.type != SDL_QUIT);

	cleanup();

	return 0;
}

void cleanup(void)
{
	ug_ctx_free(ctx);
	STBTTF_CloseFont(font);
	SDL_DestroyRenderer(r);
	SDL_DestroyWindow(w);
	SDL_Quit();
}
