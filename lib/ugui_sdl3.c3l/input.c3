module ugui::sdl::ren;

import std::io;
import std::ascii;
import ugui;
import sdl3;

<*
@param [&inout] ctx
*>
fn bool? Ctx.handle_events(&ctx)
{
	bool quit = false;
	ugui::ModKeys mod_set, mod_reset;
	ugui::MouseButtons btn;
	sdl::Event e;

	while (sdl::poll_event(&e)) {
		switch (e.type) {
		case EVENT_QUIT:
			quit = true;
		case EVENT_KEY_UP:
			ctx.input_key_release();
			nextcase;
		case EVENT_KEY_DOWN:
			ctx.input_key_press();
			if (e.key.repeat) ctx.input_key_repeat();

			bool down = e.type == EVENT_KEY_DOWN;
			switch (e.key.key) {
			case K_RCTRL:     mod_set.rctrl  = down; mod_reset.rctrl = !down;
			case K_LCTRL:     mod_set.lctrl  = down; mod_reset.lctrl = !down;
			case K_RSHIFT:    mod_set.rshift = down; mod_reset.rshift = !down;
			case K_LSHIFT:    mod_set.lshift = down; mod_reset.lshift = !down;
			case K_BACKSPACE: mod_set.bkspc  = down; mod_reset.bkspc = !down;
			case K_DELETE:    mod_set.del    = down; mod_reset.del = !down;
			case K_HOME:      mod_set.home   = down; mod_reset.home = !down;
			case K_END:       mod_set.end    = down; mod_reset.end = !down;
			case K_UP:        mod_set.up     = down; mod_reset.up = !down;
			case K_DOWN:      mod_set.down   = down; mod_reset.down = !down;
			case K_LEFT:      mod_set.left   = down; mod_reset.left = !down;
			case K_RIGHT:     mod_set.right  = down; mod_reset.right = !down;
			}
			ctx.input_mod_keys(mod_set, true);
			ctx.input_mod_keys(mod_reset, false);

			// pressing ctrl+key or alt+key does not generate a character as such no
			// TEXT_INPUT event is generated. When those keys are pressed we have to
			// do manual text input, bummer
			ModKeys mod = ctx.get_mod();
			if (e.type == EVENT_KEY_DOWN && (mod.lctrl || mod.rctrl)) {
				if (ascii::is_alnum_m((uint)e.key.key)) {
					ctx.input_char((char)e.key.key);
				}
			}

			if (e.type == EVENT_KEY_DOWN && e.key.key == K_RETURN) ctx.input_char('\n');

		case EVENT_TEXT_INPUT:
			ctx.input_text_utf8(e.text.text.str_view());
		case EVENT_WINDOW_RESIZED:
			ctx.input_window_size((short)e.window.data1, (short)e.window.data2)!;
		case EVENT_WINDOW_FOCUS_GAINED:
			ctx.input_changefocus(true);
		case EVENT_WINDOW_FOCUS_LOST:
			ctx.input_changefocus(false);
		case EVENT_MOUSE_MOTION:
			ctx.input_mouse_abs((short)e.motion.x, (short)e.motion.y);
		case EVENT_MOUSE_WHEEL:
			ctx.input_mouse_wheel((short)e.wheel.integer_x, (short)e.wheel.integer_y);
		case EVENT_MOUSE_BUTTON_DOWN: nextcase;
		case EVENT_MOUSE_BUTTON_UP:
			sdl::MouseButtonFlags mb = sdl::get_mouse_state(null, null);
			btn = {
				.btn_left = !!(mb & BUTTON_LMASK),
				.btn_right = !!(mb & BUTTON_RMASK),
				.btn_middle = !!(mb & BUTTON_MMASK),
				.btn_4 = !!(mb & BUTTON_X1MASK),
				.btn_5 = !!(mb & BUTTON_X2MASK),
			};
			ctx.input_mouse_button(btn);
		case EVENT_POLL_SENTINEL: break;
		default:
			io::eprintfn("unhandled event: %s", e.type);
		}
	}

	return quit;
}

fn void pre(sdl::Window* win) => sdl::start_text_input(win);

// TODO: this has to be a function of Ctx if we want to set the fps internally
fn void wait_events(uint timeout_ms = 0)
{
	sdl::wait_event_timeout(null, timeout_ms);
}