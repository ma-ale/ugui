import std::io;
import vtree;
import cache;
import ugui;
import std::time;
import std::collections::ringbuffer;
import std::core::string;
import std::ascii;
import std::core::mem::allocator;
import sdlrenderer::ren;
import sdl3::sdl;

alias Times = ringbuffer::RingBuffer{time::NanoDuration[128]};

fn void Times.print_stats(&times)
{
	time::NanoDuration min, max, avg, x;
	min = times.get(0);
	for (usz i = 0; i < times.written; i++) {
		x = times.get(i);
		if (x < min) { min = x; }
		if (x > max) { max = x; }
		avg += x;
	}
	avg = (NanoDuration)((ulong)avg/128.0);

	io::printfn("min=%s, max=%s, avg=%s", min, max, avg);
}

struct TimeStats {
	time::NanoDuration min, max, avg;
}

fn TimeStats Times.get_stats(&times)
{
	time::NanoDuration min, max, avg, x;
	min = times.get(0);
	for (usz i = 0; i < times.written; i++) {
		x = times.get(i);
		if (x < min) { min = x; }
		if (x > max) { max = x; }
		avg += x;
	}
	avg = (NanoDuration)((ulong)avg/128.0);

	return {.min = min, .max = max, .avg = avg};
}


const char[*] MSDF_FS_PATH = "resources/shaders/compiled/msdf.frag.spv";
const char[*] SPRITE_FS_PATH = "resources/shaders/compiled/sprite.frag.spv";
const char[*] FONT_FS_PATH = "resources/shaders/compiled/font.frag.spv";
const char[*] RECT_FS_PATH = "resources/shaders/compiled/rect.frag.spv";

const char[*] SPRITE_VS_PATH = "resources/shaders/compiled/sprite.vert.spv";
const char[*] RECT_VS_PATH = "resources/shaders/compiled/rect.vert.spv";

const char[*] STYLESHEET_PATH = "resources/style.css";

fn int main(String[] args)
{
	ArenaAllocator arena;
	char[] mem = mem::new_array(char, 1024*1024);
	defer (void)mem::free(mem);
	arena.init(mem);

	ugui::Ctx ui;
	ui.init(&arena)!!;
	defer ui.free();

	ren::Renderer ren;
	ren.init("Ugui Test", 800, 600, true);
	defer ren.free();
	ui.input_window_size(800, 600)!!;

	// ========================================================================================== //
	// FONT LOADING                                                                               //
	// ========================================================================================== //
	// import font in the ui context
	ui.load_font("font1", "resources/hack-nerd.ttf", 16)!!;

	// create the rendering pipeline
	ren.font_atlas_id = ui.get_font_id("font1");
	ren.load_spirv_shader_from_file("UGUI_PIPELINE_FONT", SPRITE_VS_PATH, FONT_FS_PATH, 1, 0);
	ren.create_pipeline("UGUI_PIPELINE_FONT", SPRITE);

	// send the atlas to the gpu
	Atlas* font_atlas = ui.get_font_atlas("font1")!!;
	ren.new_texture("font1", JUST_ALPHA, font_atlas.buffer, font_atlas.width, font_atlas.height);

	// ========================================================================================== //
	// ICON LOADING                                                                               //
	// ========================================================================================== //
	// create the atlas and upload some icons
	ui.sprite_atlas_create("icons", AtlasType.ATLAS_R8G8B8A8, 512, 512)!!;
	ui.import_sprite_file_qoi("tux", "resources/tux.qoi")!!;
	ui.import_sprite_file_qoi("tick", "resources/tick_sdf.qoi", SpriteType.SPRITE_MSDF)!!;

	// create the rendering pipelines
	ren.sprite_atlas_id = ui.get_sprite_atlas_id("icons");
	// normal sprite pipeline
	ren.load_spirv_shader_from_file("UGUI_PIPELINE_SPRITE", SPRITE_VS_PATH, SPRITE_FS_PATH, 1, 0);
	ren.create_pipeline("UGUI_PIPELINE_SPRITE", SPRITE);
	// msdf sprite pipeline
	ren.load_spirv_shader_from_file("UGUI_PIPELINE_SPRITE_MSDF", SPRITE_VS_PATH, MSDF_FS_PATH, 1, 0);
	ren.create_pipeline("UGUI_PIPELINE_SPRITE_MSDF", SPRITE);

	// upload the atlas to the gpu
	Atlas atlas = ui.sprite_atlas.atlas;
	ren.new_texture("icons", FULL_COLOR, atlas.buffer, atlas.width, atlas.height);

	// ========================================================================================== //
	// RECT PIPELINE                                                                              //
	// ========================================================================================== //
	ren.load_spirv_shader_from_file("UGUI_PIPELINE_RECT", RECT_VS_PATH, RECT_FS_PATH, 0, 0);
	ren.create_pipeline("UGUI_PIPELINE_RECT", RECT);

	// ========================================================================================== //
	// CSS INPUT                                                                                  //
	// ========================================================================================== //
	io::printfn("imported %d styles", ui.import_style_from_file(STYLESHEET_PATH));

	// ========================================================================================== //
	// OTHER VARIABLES                                                                            //
	// ========================================================================================== //
	TextEdit te;
	te.buffer = mem::new_array(char, 256);
	defer mem::free(te.buffer);

	isz frame;
	double fps;
	time::Clock clock;
	time::Clock fps_clock;
	time::Clock sleep_clock;
	Times ui_times;
	Times draw_times;

	// ========================================================================================== //
	// MAIN LOOP                                                                                  //
	// ========================================================================================== //
	sdl::start_text_input(ren.win);

	sdl::Event e;
	bool quit = false;
	ugui::ModKeys mod;
	ugui::MouseButtons btn;
	while (!quit) {
		clock.mark();
		fps_clock.mark();
		sleep_clock.mark();

		do {
			switch (e.type) {
			case EVENT_QUIT:
				quit = true;
			case EVENT_KEY_UP: 
				ui.input_key_release();
				nextcase;
			case EVENT_KEY_DOWN:
				ui.input_key_press();
				if (e.key.repeat) ui.input_key_repeat();

				mod.rctrl = e.key.key == K_RCTRL ? !!(e.type == EVENT_KEY_DOWN) : mod.rctrl;
				mod.lctrl = e.key.key == K_LCTRL ? !!(e.type == EVENT_KEY_DOWN) : mod.lctrl;
				mod.bkspc = e.key.key == K_BACKSPACE ? !!(e.type == EVENT_KEY_DOWN) : mod.bkspc;
				mod.del   = e.key.key == K_DELETE ? !!(e.type == EVENT_KEY_DOWN) : mod.del;
				mod.up    = e.key.key == K_UP ? !!(e.type == EVENT_KEY_DOWN) : mod.up;
				mod.down  = e.key.key == K_DOWN ? !!(e.type == EVENT_KEY_DOWN) : mod.down;
				mod.left  = e.key.key == K_LEFT ? !!(e.type == EVENT_KEY_DOWN) : mod.left;
				mod.right = e.key.key == K_RIGHT ? !!(e.type == EVENT_KEY_DOWN) : mod.right;

				// pressing ctrl+key or alt+key does not generate a character as such no
				// TEXT_INPUT event is generated. When those keys are pressed we have to
				// do manual text input, bummer
				if (e.type == EVENT_KEY_DOWN && (mod.lctrl || mod.rctrl)) {
					if (ascii::is_alnum_m((uint)e.key.key)) {
						ui.input_char((char)e.key.key);
					}
				}

				if (e.type == EVENT_KEY_DOWN && e.key.key == K_RETURN) ui.input_char('\n');

			case EVENT_TEXT_INPUT:
				ui.input_text_utf8(e.text.text.str_view());
			case EVENT_WINDOW_RESIZED:
				ui.input_window_size((short)e.window.data1, (short)e.window.data2)!!;
			case EVENT_WINDOW_FOCUS_GAINED:
				ui.input_changefocus(true);
			case EVENT_WINDOW_FOCUS_LOST:
				ui.input_changefocus(false);
			case EVENT_MOUSE_MOTION:
				ui.input_mouse_abs((short)e.motion.x, (short)e.motion.y);
			case EVENT_MOUSE_WHEEL:
				ui.input_mouse_wheel((short)e.wheel.integer_x, (short)e.wheel.integer_y);
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
			case EVENT_POLL_SENTINEL: break;
			default:
				io::eprintfn("unhandled event: %s", e.type);
			}
		} while(sdl::poll_event(&e));
		ui.input_mod_keys(mod);
		ui.input_mouse_button(btn);

		/* End Input Handling */

		/* Start UI Handling */
		ui.frame_begin()!!;

		if (ui.check_key_combo(ugui::KMOD_CTRL, "q")) quit = true;

const String APPLICATION = "calculator";
$switch APPLICATION:
$case "debug":
		debug_app(&ui);
$case "calculator":
		calculator(&ui, &te);
$endswitch

		// Timings counter
		TimeStats dts = draw_times.get_stats();
		TimeStats uts = ui_times.get_stats();

/*
		ui.layout_set_floating()!!;
		ui.@div({0, ui.height-150, -300, 150}) {
			ui.layout_set_column()!!;
			ui.text_unbounded(string::tformat("frame %d, fps = %.2f", frame, fps))!!;
			ui.text_unbounded(string::tformat("ui avg: %s\ndraw avg: %s\nTOT: %s", uts.avg, dts.avg, uts.avg+dts.avg))!!;
			ui.text_unbounded(string::tformat("%s %s", mod.lctrl, (String)ui.input.keyboard.text[:ui.input.keyboard.text_len]))!!;
		}!!;
*/

		ui.frame_end()!!;
		/* End UI Handling */
		ui_times.push(clock.mark());
		//ui_times.print_stats();

		/* Start UI Drawing */
		ren.begin_render(true);

		ren.render_ugui(&ui.cmd_queue);

		ren.end_render();

		draw_times.push(clock.mark());
		//draw_times.print_stats();
		/* End Drawing */

		// wait for the next event, timeout after 100ms

		sdl::wait_event_timeout(&e, (int)(100.0-sleep_clock.mark().to_ms()-0.5));

		fps = 1.0 / fps_clock.mark().to_sec();
		frame++;
	}

	return 0;
}

/*
fn void debug_app(ugui::Ctx* ui)
{
	static bool toggle;
	ui.div_begin({.w=-100})!!;
	{
		ui.layout_set_column()!!;
		if (ui.button(icon:"tux")!!.mouse_press) {
			io::printn("press button0");
			toggle = !toggle;
		}
		//ui.layout_next_column()!!;
		if (ui.button(label: "ciao", icon: "tick")!!.mouse_press) {
			io::printn("press button1");
		}
		//ui.layout_next_column()!!;
		if (ui.button()!!.mouse_release) {
			io::printn("release button2");
		}

		ui.layout_set_row()!!;
		ui.layout_next_row()!!;
		static float rf, gf, bf, af;
		ui.slider_ver({0,0,30,100}, &rf)!!;
		ui.slider_ver({0,0,30,100}, &gf)!!;
		ui.slider_ver({0,0,30,100}, &bf)!!;
		ui.slider_ver({0,0,30,100}, &af)!!;

		ui.layout_next_column()!!;
		ui.text_unbounded("Ciao Mamma\nAbilità ⚡\n'\udb80\udd2c'")!!;

		ui.layout_next_column()!!;
		ui.button("Continua!")!!;

		ui.layout_next_row()!!;
		static bool check;
		ui.checkbox("", {}, &check, "tick")!!;
		ui.checkbox("", {}, &check)!!;
		ui.toggle("", {}, &toggle)!!;

		ui.sprite("tux")!!;
		static char[128] text_box = "ciao mamma";
		static usz text_len = "ciao mamma".len;
		ui.text_box({0,0,200,200}, text_box[..], &text_len)!!;
	};
	ui.div_end()!!;

	ui.div_begin(ugui::DIV_FILL, scroll_x: true, scroll_y: true)!!;
	{
		ui.layout_set_column()!!;
		static float slider2 = 0.5;
		if (ui.slider_ver({0,0,30,100}, &slider2)!!.update) {
			io::printfn("other slider: %f", slider2);
		}
		ui.button()!!;
		ui.button()!!;
		ui.button()!!;
		ui.button()!!;
		if (toggle) {
			ui.button()!!;
			ui.button()!!;
			ui.button()!!;
			ui.button()!!;
		}
		ui.layout_next_column()!!;
		ui.layout_set_row()!!;
		static float f1, f2;
		ui.slider_hor({0,0,100,30}, &f1)!!;
		ui.slider_hor({0,0,100,30}, &f2)!!;
	};
	ui.div_end()!!;
}
*/

import std::os::process;

fn void calculator(ugui::Ctx* ui, TextEdit* te)
{
	static char[128] buffer;
	static usz len;
	bool eval;

	// keyboard input
	switch(ui.get_keys()) {
	case "+": nextcase;
	case "-": nextcase;
	case "*": nextcase;
	case "/": nextcase;
	case "(": nextcase;
	case ")": nextcase;
	case ".": nextcase;
	case "0": nextcase;
	case "1": nextcase;
	case "2": nextcase;
	case "3": nextcase;
	case "4": nextcase;
	case "5": nextcase;
	case "6": nextcase;
	case "7": nextcase;
	case "8": nextcase;
	case "9":
		buffer[len++] = ui.get_keys()[0];
	case "\n":
		eval = true;
	case "c":
		len = 0;
	case "d":
		if (len > 0) len--;
	}

	// ui input/output
	ui.@div(ugui::@grow(), ugui::@grow(), ROW, CENTER) { // center everything on the screen
	ui.@div(ugui::@fit(), ugui::@fit(), COLUMN, TOP_LEFT) {

		ui.@div(ugui::@grow(), ugui::@fit(), ROW, CENTER) {ui.text("SHITTY AHH CALCULATOR")!!;}!!;
		ui.@div(ugui::@grow(), ugui::@exact(100), ROW, RIGHT) {
			ui.text((String)buffer[:len])!!;
		}!!;
		ui.@div(ugui::@fit(), ugui::@fit(), ROW, TOP_LEFT) {
			ui.@div(ugui::@fit(), ugui::@fit(), COLUMN) {
				ui.button("7")!!.mouse_press ? buffer[len++] = '7' : 0;
				ui.button("4")!!.mouse_press ? buffer[len++] = '4' : 0;
				ui.button("1")!!.mouse_press ? buffer[len++] = '1' : 0;
				ui.button("0")!!.mouse_press ? buffer[len++] = '0' : 0;
			}!!;
			ui.@div(ugui::@fit(), ugui::@fit(), COLUMN) {
				ui.button("8")!!.mouse_press ? buffer[len++] = '8' : 0;
				ui.button("5")!!.mouse_press ? buffer[len++] = '5' : 0;
				ui.button("2")!!.mouse_press ? buffer[len++] = '2' : 0;
				ui.button(".")!!.mouse_press ? buffer[len++] = '.' : 0;
			}!!;
			ui.@div(ugui::@fit(), ugui::@fit(), COLUMN) {
				ui.button("9")!!.mouse_press ? buffer[len++] = '9' : 0;
				ui.button("6")!!.mouse_press ? buffer[len++] = '6' : 0;
				ui.button("3")!!.mouse_press ? buffer[len++] = '3' : 0;
				ui.button("(")!!.mouse_press ? buffer[len++] = '(' : 0;
			}!!;
			ui.@div(ugui::@exact(10), ugui::@exact(10)) {}!!;
			ui.@div(ugui::@fit(), ugui::@fit(), COLUMN) {
				ui.button("x")!!.mouse_press ? buffer[len++] = '*' : 0;
				ui.button("/")!!.mouse_press ? buffer[len++] = '/' : 0;
				ui.button("+")!!.mouse_press ? buffer[len++] = '+' : 0;
				ui.button(")")!!.mouse_press ? buffer[len++] = ')' : 0;
			}!!;
			ui.@div(ugui::@fit(), ugui::@fit(), COLUMN) {
				ui.button("C")!!.mouse_press ? len = 0 : 0;
				ui.button("D")!!.mouse_press ? len > 0 ? len-- : 0 : 0;
				ui.button("-")!!.mouse_press ? buffer[len++] = '-' : 0;

				// eval the expression with 'bc'
				if (ui.button("=")!!.mouse_press || eval) {
					char[128] out;
					String y = string::tformat("echo '%s' | bc", (String)buffer[:len]);
					String x = process::execute_stdout_to_buffer(out[:128], (String[]){"sh", "-c", y}) ?? "";
					buffer[:x.len] = x[..];
					len = x.len;
				}
			}!!;
		}!!;

		ui.@div(ugui::@grow(), ugui::@fit(), anchor: CENTER) {
			static bool state;
			ui.checkbox("boolean", &state, "tick")!!;
			ui.sprite("tux")!!;
			ui.toggle("lmao", &state)!!;
		}!!;
		ui.@div(ugui::@grow(), ugui::@exact(50), anchor: CENTER, scroll_y: true) {
			static float f;
			ui.slider_hor(ugui::@exact(100), ugui::@exact(20), &f)!!;
			ui.slider_ver(ugui::@exact(20), ugui::@exact(100), &f)!!;
		}!!;
		ui.@div(ugui::@grow(), ugui::@fit(), anchor: CENTER, scroll_y: true) {
			ui.text_box(ugui::@grow(), ugui::@exact(100), te)!!;
		}!!;

	}!!; }!!;
}
