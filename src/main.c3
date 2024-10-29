import std::io;
import vtree;
import cache;
import ugui;
import rl;

fn int main(String[] args)
{
	ugui::Ctx ctx;
	ctx.init()!!;

	short width = 800;
	short height = 450;
	rl::set_config_flags(rl::FLAG_WINDOW_RESIZABLE);
	rl::init_window(width, height, "Ugui Test");
	ctx.input_window_size(width, height)!!;

	double[10][4] median_times;
	isz frame;
	double median_input, median_layout, median_draw, median_tot;

	// Main loop
	while (!rl::window_should_close()) {
		const int PARTIAL_INPUT  = 0;
		const int PARTIAL_LAYOUT = 1;
		const int PARTIAL_DRAW   = 2;
		//timer_start();

		/*** Start Input Handling ***/
		if (rl::is_window_resized()) {
			width  = (short)rl::get_screen_width();
			height = (short)rl::get_screen_height();
			ctx.input_window_size(width, height)!!;
		}

		ctx.input_changefocus(rl::is_window_focused());

		// FIXME: In raylib it doesn't seem to be a quick way to check if
		//        a mouse input event was received, so for now just use
		//        the delta information
		rl::Vector2 mousedelta = rl::get_mouse_delta();
		if (mousedelta.x || mousedelta.y) {
			ctx.input_mouse_delta((short)mousedelta.x, (short)mousedelta.y);
		}

		ugui::MouseButtons buttons;
		buttons.btn_left = rl::is_mouse_button_down(rl::MOUSE_BUTTON_LEFT);
		buttons.btn_right = rl::is_mouse_button_down(rl::MOUSE_BUTTON_RIGHT);
		buttons.btn_middle = rl::is_mouse_button_down(rl::MOUSE_BUTTON_MIDDLE);
		ctx.input_mouse_button(buttons);

		//timer_partial(PARTIAL_INPUT);
		/*** End Input Handling ***/

		/*** Start UI Handling ***/
		ctx.frame_begin()!!;

		// main div, fill the whole window
		ctx.div_begin("main", ugui::DIV_FILL)!!;
		{|
			ctx.layout_set_column()!!;
			if (ctx.button("button0", ugui::Rect{.y = 100, .x = 100, .w = 30, .h = 30})!!.mouse_hold) {
				io::printn("HOLDING button0");
			}
			ctx.layout_next_column()!!;
			ctx.button("button1", ugui::Rect{.w = 30, .h = 30})!!;
			ctx.layout_next_column()!!;
			ctx.button("button2", ugui::Rect{.w = 30, .h = 30})!!;
		|};
		ctx.div_end()!!;

		ctx.frame_end()!!;
		//timer_partial(PARTIAL_LAYOUT);
		/*** End UI Handling ***/

		/*** Start UI Drawing ***/
		rl::begin_drawing();
		// ClearBackground(BLACK);

		io::printn("----- Draw Begin -----");
		rl::Color c;
		for (Cmd* cmd; (cmd = ctx.cmd_queue.dequeue() ?? null) != null;) {
			switch (cmd.type) {
			case ugui::CmdType.CMD_RECT:
				io::printfn(
				    "draw rect x=%d y=%d w=%d h=%d",
				    cmd.rect.rect.x,
				    cmd.rect.rect.y,
				    cmd.rect.rect.w,
				    cmd.rect.rect.h
				);
				c = rl::Color{
				    .r = cmd.rect.color.r,
				    .g = cmd.rect.color.g,
				    .b = cmd.rect.color.b,
				    .a = cmd.rect.color.a,
				};
				rl::draw_rectangle(
				    cmd.rect.rect.x,
				    cmd.rect.rect.y,
				    cmd.rect.rect.w,
				    cmd.rect.rect.h,
				    c
				);
			default:
				io::printfn("Unknown cmd type: %d", cmd.type);
			}
		}
		io::printf("----- Draw End -----\n\n");

		rl::end_drawing();
		//timer_partial(PARTIAL_DRAW);
		//timer_stop();
		/*** End UI Drawing ***/
		/*
		median_times[frame][PARTIAL_INPUT] =
		    1e3 * timer_get_sec(PARTIAL_INPUT);
		median_times[frame][PARTIAL_LAYOUT] =
		    1e3 * timer_get_sec(PARTIAL_LAYOUT);
		median_times[frame][PARTIAL_DRAW] =
		    1e3 * timer_get_sec(PARTIAL_DRAW);
		median_times[frame][3] = 1e3 * timer_get_sec(-1);
		*/
		frame += 1;
		frame %= 10;
		/*
		if (frame == 0) {
			median_input  = 0;
			median_layout = 0;
			median_draw   = 0;
			median_tot    = 0;
			for (size_t i = 0; i < 10; i++) {
				median_input += median_times[i][PARTIAL_INPUT];
				median_layout += median_times[i][PARTIAL_LAYOUT];
				median_draw += median_times[i][PARTIAL_DRAW];
				median_tot += median_times[i][3];
			}
			median_input /= 10;
			median_layout /= 10;
			median_draw /= 10;
			median_tot /= 10;
		}

		printf("input time: %lfms\n", median_input);
		printf("layout time: %lfms\n", median_layout);
		printf("draw time: %lfms\n", median_draw);
		printf("total time: %lfms\n", median_tot);

		// Throttle Frames
		// TODO: add an fps limit, time frame generation and log it
		const float TARGET_FPS = 100;
		float wait_time = MAX((1.0 / TARGET_FPS) - timer_get_sec(-1), 0);
		WaitTime(wait_time);
		*/
	}

	rl::close_window();

	ctx.free();
	return 0;
}

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
