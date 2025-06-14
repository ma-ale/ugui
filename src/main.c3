import std::io;
import vtree;
import cache;
import ugui;
import std::time;
import std::collections::ringbuffer;
import std::core::string;
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


fn int main(String[] args)
{
	ugui::Ctx ui;
	ui.init()!!;
	defer ui.free();

	ren::Renderer ren;
	ren.init("Ugui Test", 640, 480);
	defer ren.free();
	ui.input_window_size(640, 480)!!;

	//
	// FONT LOADING
	//
	{
		// import font in the ui context
		ui.load_font("font1", "resources/hack-nerd.ttf", 16)!!;
		
		// create the rendering pipeline
		ren.font_atlas_id = ui.get_font_id("font1");
		ren.load_spirv_shader_from_file("UGUI_PIPELINE_FONT", SPRITE_VS_PATH, FONT_FS_PATH, 1, 0);
		ren.create_pipeline("UGUI_PIPELINE_FONT", SPRITE);
		
		// send the atlas to the gpu
		Atlas* font_atlas = ui.get_font_atlas("font1")!!;
		ren.new_texture("font1", JUST_ALPHA, font_atlas.buffer, font_atlas.width, font_atlas.height);
	}

	//
	// ICON LOADING
	//
	{
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
	}

	//
	// RECT PIPELINE
	//
	ren.load_spirv_shader_from_file("UGUI_PIPELINE_RECT", RECT_VS_PATH, RECT_FS_PATH, 0, 0);
	ren.create_pipeline("UGUI_PIPELINE_RECT", RECT);


	isz frame;
	bool toggle = true;
	time::Clock clock;
	Times ui_times;
	Times draw_times;


	//
	// MAIN LOOP
	//
	sdl::Event e;
	bool quit = false;
	while (!quit) {
		clock.mark();
		
		// FIXME: modkeys input is broken
		ugui::ModKeys mod;
		while (sdl::poll_event(&e)) {
			switch (e.type) {
			case EVENT_QUIT: 
				quit = true;
			case EVENT_KEY_DOWN:
				mod.rctrl = !!(e.key.key == K_RCTRL);
				mod.lctrl = !!(e.key.key == K_LCTRL);
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
				ugui::MouseButtons b = {
					.btn_left = !!(mb & BUTTON_LMASK),
					.btn_right = !!(mb & BUTTON_RMASK),
					.btn_middle = !!(mb & BUTTON_MMASK),
					.btn_4 = !!(mb & BUTTON_X1MASK),
					.btn_5 = !!(mb & BUTTON_X2MASK),
				};
				ui.input_mouse_button(b);
			default:
				io::eprintfn("unhandled event: %s", e.type);
			}
		}
		ui.input_mod_keys(mod);

		/*
		for (rl::KeyboardKey key; (key = (KeyboardKey)rl::getKeyPressed()) != 0;) {
			ZString kname = rl::getKeyName(key);
			if (kname == null) continue;
			ui.input_text_unicode(kname.str_view());
		}
		*/

		/* End Input Handling */

		/* Start UI Handling */
		ui.frame_begin()!!;

		if (ui.check_key_combo(ugui::KMOD_CTRL, "q")) quit = true;

/*
		ui.div_begin("main", ugui::DIV_FILL)!!;
		ui.button("button0", {0,0,30,30})!!;
		ui.draw_sprite("sprite1", "tux")!!;
		ui.text_unbounded("text1", "Ciao")!!;
		ui.div_end()!!;
*/

		ui.div_begin("main", {.w=-100})!!;
		{
			ui.layout_set_column()!!;
			if (ui.button("button0", {0,0,30,30}, toggle)!!.mouse_press) {
				io::printn("press button0");
				toggle = !toggle;
			}
			//ui.layout_next_column()!!;
			if (ui.button("button1", {0,0,30,30})!!.mouse_press) {
				io::printn("press button1");
			}
			//ui.layout_next_column()!!;
			if (ui.button("button2", {0,0,30,30})!!.mouse_release) {
				io::printn("release button2");
			}

			ui.layout_set_row()!!;
			ui.layout_next_row()!!;
			static float rf, gf, bf, af;
			ui.slider_ver("slider_r", {0,0,30,100}, &rf)!!;
			ui.slider_ver("slider_g", {0,0,30,100}, &gf)!!;
			ui.slider_ver("slider_b", {0,0,30,100}, &bf)!!;
			ui.slider_ver("slider_a", {0,0,30,100}, &af)!!;

			ui.layout_next_column()!!;
			ui.text_unbounded("text1", "Ciao Mamma\nAbilità ⚡\n'\udb80\udd2c'")!!;

			ui.layout_next_column()!!;
			ui.button_label("Continua!")!!;

			ui.layout_next_row()!!;
			static bool check;
			ui.checkbox("check1", "", {}, &check, "tick")!!;
			ui.toggle("toggle1", "", {}, &toggle)!!;

/*
			ui.layout_set_column()!!;
			ui.button_label(" A ")!!;
			ui.button_label(" B ")!!;
			ui.layout_next_column()!!;
			ui.button_label(" C ")!!;
			ui.button_label(" D ")!!;
			ui.layout_next_row()!!;
			ui.button_label(" E ")!!;
*/
		};
		ui.draw_sprite("sprite1", "tux")!!;
		ui.div_end()!!;

		ui.div_begin("second", ugui::DIV_FILL, scroll_x: true, scroll_y: true)!!;
		{
			ui.layout_set_column()!!;
			static float slider2 = 0.5;
			if (ui.slider_ver("slider", {0,0,30,100}, &slider2)!!.update) {
				io::printfn("other slider: %f", slider2);
			}
			ui.button("button0", {0,0,50,50})!!;
			ui.button("button1", {0,0,50,50})!!;
			ui.button("button2", {0,0,50,50})!!;
			ui.button("button3", {0,0,50,50})!!;
			if (toggle) {
				ui.button("button4", {0,0,50,50})!!;
				ui.button("button5", {0,0,50,50})!!;
				ui.button("button6", {0,0,50,50})!!;
				ui.button("button7", {0,0,50,50})!!;
			}
			ui.layout_next_column()!!;
			ui.layout_set_row()!!;
			static float f1, f2;
			ui.slider_hor("hs1", {0,0,100,30}, &f1)!!;
			ui.slider_hor("hs2", {0,0,100,30}, &f2)!!;
		};
		ui.div_end()!!;

		// Timings counter
		TimeStats dts = draw_times.get_stats();
		TimeStats uts = ui_times.get_stats();

		ui.layout_set_floating()!!;
		ui.div_begin("fps", {0, ui.height-100, -300, 100})!!;
		{
			ui.layout_set_column()!!;
			ui.text_unbounded("frame number", string::tformat("frame %d", frame))!!;
			ui.text_unbounded("draw times", string::tformat("ui avg: %s\ndraw avg: %s\nTOT: %s", uts.avg, dts.avg, uts.avg+dts.avg))!!;
			ui.text_unbounded("ui text input", (String)ui.input.keyboard.text[..])!!;
		};
		ui.div_end()!!;


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

		frame++;
	}

	return 0;
}
