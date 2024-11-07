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

	isz frame;

	// Main loop
	while (!rl::window_should_close()) {
		const int PARTIAL_INPUT  = 0;
		const int PARTIAL_LAYOUT = 1;
		const int PARTIAL_DRAW   = 2;

		/* Start Input Handling */
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
		/* End Input Handling */

		/* Start UI Handling */
		ctx.frame_begin()!!;

		// main div, fill the whole window
		ctx.div_begin("main", ugui::Rect{.w=ctx.width/2})!!;
		{|
			ctx.layout_set_column()!!;
			if (ctx.button("button0", ugui::Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button0");
			}
			ctx.layout_next_column()!!;
			if (ctx.button("button1", ugui::Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button1");
			}
			ctx.layout_next_column()!!;
			if (ctx.button("button2", ugui::Rect{0,0,30,30})!!.mouse_release) {
				io::printn("release button2");
			}
			if (ctx.slider_ver("slider", ugui::Rect{0,0,30,100})!!.update) {
				ugui::Elem* e = ctx.get_elem_by_label("slider")!!;
				io::printfn("slider: %f", e.slider.value);
			}
		|};
		ctx.div_end()!!;

		ctx.div_begin("second", ugui::DIV_FILL)!!;
		{|
			if (ctx.slider_ver("slider_other", ugui::Rect{0,0,30,100})!!.update) {
				ugui::Elem* e = ctx.get_elem_by_label("slider_other")!!;
				io::printfn("other slider: %f", e.slider.value);
			}
		|};
		ctx.div_end()!!;

		ctx.frame_end()!!;
		/* End UI Handling */

		/* Start UI Drawing */
		rl::begin_drawing();
		// ClearBackground(BLACK);

		rl::Color c;
		for (Cmd* cmd; (cmd = ctx.cmd_queue.dequeue() ?? null) != null;) {
			switch (cmd.type) {
			case ugui::CmdType.CMD_RECT:
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

		rl::end_drawing();

		// TODO: throttle FPS
	}

	rl::close_window();

	ctx.free();
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
