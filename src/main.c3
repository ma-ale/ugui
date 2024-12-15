import std::io;
import vtree;
import cache;
import ugui;
import rl;
import std::time;
import std::collections::ringbuffer;

def Times = ringbuffer::RingBuffer(<time::NanoDuration, 128>);

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

fn int main(String[] args)
{
	ugui::Ctx ui;
	ui.init()!!;
	ui.load_font("font1", "/usr/share/fonts/TTF/HackNerdFontMono-Regular.ttf", 16)!!;

	short width = 800;
	short height = 450;
	rl::set_config_flags(rl::FLAG_WINDOW_RESIZABLE);
	rl::init_window(width, height, "Ugui Test");
	ui.input_window_size(width, height)!!;
	rl::set_target_fps(60);
	rl::enable_event_waiting();

	isz frame;
	bool toggle = true;
	time::Clock clock;
	Times ui_times;
	Times draw_times;

	// Main loop
	while (!rl::window_should_close()) {
		clock.mark();

		/* Start Input Handling */
		if (rl::is_window_resized()) {
			width  = (short)rl::get_screen_width();
			height = (short)rl::get_screen_height();
			ui.input_window_size(width, height)!!;
		}

		ui.input_changefocus(rl::is_window_focused());

		rl::Vector2 mpos = rl::get_mouse_position();
		ui.input_mouse_abs((short)mpos.x, (short)mpos.y);

		ugui::MouseButtons buttons;
		buttons.btn_left = rl::is_mouse_button_down(rl::MOUSE_BUTTON_LEFT);
		buttons.btn_right = rl::is_mouse_button_down(rl::MOUSE_BUTTON_RIGHT);
		buttons.btn_middle = rl::is_mouse_button_down(rl::MOUSE_BUTTON_MIDDLE);
		ui.input_mouse_button(buttons);
		/* End Input Handling */

		/* Start UI Handling */
		ui.frame_begin()!!;

		// main div, fill the whole window
		ui.div_begin("main", ugui::Rect{.w=ui.width/2})!!;
		{|

			ui.layout_set_row()!!;
			if (ui.button("button0", ugui::Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button0");
				toggle = !toggle;
				ui.force_update()!!;
			}
			//ui.layout_next_column()!!;
			if (ui.button("button1", ugui::Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button1");
			}
			//ui.layout_next_column()!!;
			if (toggle) {
				if (ui.button("button2", ugui::Rect{0,0,30,30})!!.mouse_release) {
					io::printn("release button2");
				}
			}
			if (ui.slider_ver("slider", ugui::Rect{0,0,30,100})!!.update) {
				ugui::Elem* e = ui.get_elem_by_label("slider")!!;
				io::printfn("slider: %f", e.slider.value);
			}

			ui.text_unbounded("text1", "Ciao Mamma\nAbilità ⚡")!!;
		|};
		ui.div_end()!!;

		ui.div_begin("second", ugui::DIV_FILL)!!;
		ugui::Elem* de = ui.get_elem_by_label("second")!!;
		de.div.scroll.can_y = true;
		{|
			ui.layout_set_column()!!;
			if (ui.slider_ver("slider_other", ugui::Rect{0,0,30,100})!!.update) {
				ugui::Elem* e = ui.get_elem_by_label("slider_other")!!;
				io::printfn("other slider: %f", e.slider.value);
			}
			ui.button("button10", ugui::Rect{0,0,50,50})!!;
			ui.button("button11", ugui::Rect{0,0,50,50})!!;
			ui.button("button12", ugui::Rect{0,0,50,50})!!;
			ui.button("button13", ugui::Rect{0,0,50,50})!!;
			ui.button("button14", ugui::Rect{0,0,50,50})!!;
			ui.button("button15", ugui::Rect{0,0,50,50})!!;
			ui.button("button16", ugui::Rect{0,0,50,50})!!;
			ui.button("button17", ugui::Rect{0,0,50,50})!!;
		|};
		ui.div_end()!!;

		ui.frame_end()!!;
		/* End UI Handling */
		ui_times.push(clock.mark());
		ui_times.print_stats();

		/* Start UI Drawing */
		rl::begin_drawing();
		// ClearBackground(BLACK);

		rl::Color c;
		rl::Rectangle r;
		static rl::Image font_atlas;
		static rl::Texture2D font_texture;
		for (Cmd* cmd; (cmd = ui.cmd_queue.dequeue() ?? null) != null;) {
			switch (cmd.type) {
			case ugui::CmdType.CMD_RECT:
				c = rl::Color{
				    .r = cmd.rect.color.r,
				    .g = cmd.rect.color.g,
				    .b = cmd.rect.color.b,
				    .a = cmd.rect.color.a,
				};
				r = rl::Rectangle{
					.x = cmd.rect.rect.x,
					.y = cmd.rect.rect.y,
					.height = cmd.rect.rect.h,
					.width = cmd.rect.rect.w,
				};
			    float rad = cmd.rect.radius;
				// for some weird-ass reason the straight forward inverse formula does not work
			    float roundness = r.width > r.height ? (2.1*rad)/r.height : (2.1*rad)/r.width;
				rl::draw_rectangle_rounded(r, roundness, 0, c);
			case ugui::CmdType.CMD_UPDATE_ATLAS:
				rl::unload_image(font_atlas);
				font_atlas.data = cmd.update_atlas.raw_buffer;
				font_atlas.width = cmd.update_atlas.width;
				font_atlas.height = cmd.update_atlas.height;
				font_atlas.mipmaps = 1;
				//font_atlas.format = rl::PixelFormat.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE;
				font_atlas.format = 1;
				if (rl::is_texture_ready(font_texture)) {
					rl::unload_texture(font_texture);
				}
				font_texture = rl::load_texture_from_image(font_atlas);
				//rl::draw_texture(font_texture, 0, 0, rl::WHITE);
			case ugui::CmdType.CMD_SPRITE:
				rl::Rectangle source = {
					.x = cmd.sprite.texture_rect.x,
					.y = cmd.sprite.texture_rect.y,
					.width = cmd.sprite.texture_rect.w,
					.height = cmd.sprite.texture_rect.h,
				};
				rl::Vector2 position = {
					.x = cmd.sprite.rect.x,
					.y = cmd.sprite.rect.y,
				};

				rl::draw_texture_rec(font_texture, source, position, rl::WHITE);
				//rl::draw_rectangle(cmd.sprite.rect.x,
				//    cmd.sprite.rect.y,
				//    cmd.sprite.rect.w,
				//    cmd.sprite.rect.h,
				//    rl::WHITE
				//);
			default:
				io::printfn("Unknown cmd type: %s", cmd.type);
			}
		}
		draw_times.push(clock.mark());
		draw_times.print_stats();
		rl::end_drawing();
		/* End Drawing */

	}

	rl::close_window();

	ui.free();
	return 0;
}

/*
fn void! test_vtree() @test
{
	vtree::VTree(<String>) vt;
	vt.init(10)!!;
	defer vt.free();

	assert(vt.size() == 10, "Size is incorrect");

	isz ref = vt.add("Ciao Mamma", 0)!!;
	String s = vt.get(ref)!!;
	assert(s == "Ciao Mamma", "String is incorrect");
	isz par = vt.parentof(0)!!;
	assert(ref == par, "Not Root");

	vt.print();
}

def StrCache = cache::Cache(<int, String, 256>);
fn void! test_cache() @test
{
	StrCache cc;
	cc.init()!!;
	defer cc.free();

	String*! r = cc.search(1);
	if (catch ex = r) {
		if (ex != SearchResult.MISSING) {
			return ex?;
		}
	}

	r = cc.get_or_insert(&&"Ciao Mamma", 1)!;
	assert(*r!! == "Ciao Mamma", "incorrect string");
}
*/
