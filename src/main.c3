import std::io;
import vtree;
import cache;
import ugui;
import rl;
import std::time;
import std::collections::ringbuffer;
import std::core::string;

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

	return TimeStats{.min = min, .max = max, .avg = avg};
}


const ZString FONT_FS = `
#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

void main()
{
    vec4 alpha = texture(texture0, fragTexCoord);
    finalColor = colDiffuse*fragColor;
    finalColor.a *= alpha.r;
}
`;

macro rl::Color ugui::Color.conv(color)
{
	return rl::Color{.r = color.r, .g = color.g, .b = color.b, .a = color.a};
}

macro rl::Rectangle ugui::Rect.conv(rect)
{
	return rl::Rectangle{.x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h};
}

fn int main(String[] args)
{
	ugui::Ctx ui;
	ui.init()!!;
	ui.load_font("font1", "resources/hack-nerd.ttf", 16)!!;

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

	// font stuff
	rl::Shader font_shader = rl::load_shader_from_memory(null, FONT_FS);
	rl::Image font_atlas;
	rl::Texture2D font_texture;
	ugui::Id font_id = ui.get_font_id("font1");

	// Main loop
	while (!rl::window_should_close()) {
		clock.mark();

/*
		KeyboardKey k;
		do {
			k = rl::get_key_pressed();
			if (!k) { break; }
			if (rl::is_key_down(k)) { io::print("down "); }
			if (rl::is_key_pressed(k)) { io::print("pressed "); }
			if (rl::is_key_released(k)) { io::print("released "); }
			io::printfn("%s", k);
		} while (k != 0);
*/
		for (int c; (c = rl::get_char_pressed()) != 0;) {
			int[1] ts;
			ts[0] = c;
			ui.input_text_unicode(ts[..]);
		}

		/* Start Input Handling */
		if (rl::is_window_resized()) {
			width  = (short)rl::get_screen_width();
			height = (short)rl::get_screen_height();
			ui.input_window_size(width, height)!!;
		}

		ui.input_changefocus(rl::is_window_focused());

		rl::Vector2 mpos = rl::get_mouse_position();
		ui.input_mouse_abs((short)mpos.x, (short)mpos.y);
		rl::Vector2 mwheel = rl::get_mouse_wheel_move_v();
		ui.input_mouse_wheel((short)mwheel.x, (short)mwheel.y);

		ugui::MouseButtons buttons = {
			.btn_left = rl::is_mouse_button_down(rl::MOUSE_BUTTON_LEFT),
			.btn_right = rl::is_mouse_button_down(rl::MOUSE_BUTTON_RIGHT),
			.btn_middle = rl::is_mouse_button_down(rl::MOUSE_BUTTON_MIDDLE),
		};
		ui.input_mouse_button(buttons);
		/* End Input Handling */

		/* Start UI Handling */
		ui.frame_begin()!!;

		// main div, fill the whole window
		ui.div_begin("main", ugui::Rect{.w=-100})!!;
		{|
			ui.layout_set_column()!!;
			if (ui.button("button0", ugui::Rect{0,0,30,30}, toggle)!!.mouse_press) {
				io::printn("press button0");
				toggle = !toggle;
			}
			//ui.layout_next_column()!!;
			if (ui.button("button1", ugui::Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button1");
			}
			//ui.layout_next_column()!!;
			if (ui.button("button2", ugui::Rect{0,0,30,30})!!.mouse_release) {
				io::printn("release button2");
			}
			
			ui.layout_set_row()!!;
			ui.layout_next_row()!!;
			static float rf, gf, bf, af;
			ui.slider_ver("slider_r", ugui::Rect{0,0,30,100}, &rf)!!;
			ui.slider_ver("slider_g", ugui::Rect{0,0,30,100}, &gf)!!;
			ui.slider_ver("slider_b", ugui::Rect{0,0,30,100}, &bf)!!;
			ui.slider_ver("slider_a", ugui::Rect{0,0,30,100}, &af)!!;

			ui.layout_next_column()!!;
			ui.text_unbounded("text1", "Ciao Mamma\nAbilità ⚡")!!;

			ui.layout_next_column()!!;
			ui.button_label("Continua!")!!;
		|};
		ui.div_end()!!;

		ui.div_begin("second", ugui::DIV_FILL, scroll_x: true, scroll_y: true)!!;
		{|
			ui.layout_set_column()!!;
			static float slider2 = 0.5;
			if (ui.slider_ver("slider", ugui::Rect{0,0,30,100}, &slider2)!!.update) {
				io::printfn("other slider: %f", slider2);
			}
			ui.button("button0", ugui::Rect{0,0,50,50})!!;
			ui.button("button1", ugui::Rect{0,0,50,50})!!;
			ui.button("button2", ugui::Rect{0,0,50,50})!!;
			ui.button("button3", ugui::Rect{0,0,50,50})!!;
			if (toggle) {
				ui.button("button4", ugui::Rect{0,0,50,50})!!;
				ui.button("button5", ugui::Rect{0,0,50,50})!!;
				ui.button("button6", ugui::Rect{0,0,50,50})!!;
				ui.button("button7", ugui::Rect{0,0,50,50})!!;
			}
			ui.layout_next_column()!!;
			ui.layout_set_row()!!;
			static float f1, f2;
			ui.slider_hor("hs1", ugui::Rect{0,0,100,30}, &f1)!!;
			ui.slider_hor("hs2", ugui::Rect{0,0,100,30}, &f2)!!;
		|};
		ui.div_end()!!;
		
		// Timings counter
		TimeStats dts = draw_times.get_stats();
		TimeStats uts = ui_times.get_stats();

		ui.layout_set_floating()!!;
		ui.div_begin("fps", ugui::Rect{0, ui.height-100, -300, 100})!!;
		{|
			ui.layout_set_column()!!;
			ui.text_unbounded("draw times", string::tformat("ui avg: %s\ndraw avg: %s\nTOT: %s", uts.avg, dts.avg, uts.avg+dts.avg))!!;
			ui.text_unbounded("ui text input", (String)ui.input.keyboard.text[..])!!;
		|};
		ui.div_end()!!;

		ui.frame_end()!!;
		/* End UI Handling */
		ui_times.push(clock.mark());
		//ui_times.print_stats();

		/* Start UI Drawing */
		rl::begin_drawing();
		// ClearBackground(BLACK);

		for (Cmd* cmd; (cmd = ui.cmd_queue.dequeue() ?? null) != null;) {
			switch (cmd.type) {
			case ugui::CmdType.CMD_RECT:
				Rect r = cmd.rect.rect;
				float rad = cmd.rect.radius;
				// for some weird-ass reason the straight forward inverse formula does not work
				float roundness = r.w > r.h ? (2.1f*rad)/(float)r.h : (2.1f*rad)/(float)r.w;
				rl::draw_rectangle_rounded(cmd.rect.rect.conv(), roundness, 0, cmd.rect.color.conv());
			case ugui::CmdType.CMD_UPDATE_ATLAS:
				if (cmd.update_atlas.id != font_id) { break; }
				//rl::unload_image(font_atlas);
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
			case ugui::CmdType.CMD_SPRITE:
				if (cmd.sprite.texture_id != font_id) { break; }
				rl::Vector2 position = {
					.x = cmd.sprite.rect.x,
					.y = cmd.sprite.rect.y,
				};
				rl::begin_shader_mode(font_shader);
				rl::draw_texture_rec(font_texture, cmd.sprite.texture_rect.conv(), position, cmd.sprite.hue.conv());
				rl::end_shader_mode();
			case ugui::CmdType.CMD_SCISSOR:
				if (cmd.scissor.rect.w == 0 && cmd.scissor.rect.h == 0) {
					rl::end_scissor_mode();
				} else {
					rl::begin_scissor_mode(cmd.scissor.rect.x, cmd.scissor.rect.y, cmd.scissor.rect.w, cmd.scissor.rect.h);
				}
			default:
				io::printfn("Unknown cmd type: %s", cmd.type);
			}
		}
		draw_times.push(clock.mark());
		//draw_times.print_stats();
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
