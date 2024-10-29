module ugui;

import std::io;

// TODO: this could be a bitstruct
bitstruct InputEvents : uint {
	bool resize : 0; // window size was changed
	bool change_focus : 1; // window focus changed
	bool mouse_move : 2; // mouse was moved
	bool mouse_btn : 3; // mouse button pressed or released
}

// Window size was changed
fn void! Ctx.input_window_size(&ctx, short width, short height)
{
	if (width <= 0 || height <= 0) {
		return UgError.INVALID_SIZE?;
	}
	ctx.width = width;
	ctx.height = height;
	ctx.input.events.resize = true;
}

// Window gained/lost focus
fn void Ctx.input_changefocus(&ctx, bool has_focus)
{
	// FIXME: raylib only has an API to query the focus status so we have to
	//        update the input flag only if the focus changed
	if (ctx.has_focus != has_focus) {
		ctx.input.events.change_focus = true;
	}
	ctx.has_focus = has_focus;
}

bitstruct MouseButtons : uint {
	bool btn_left : 0;
	bool btn_middle : 1;
	bool btn_right : 2;
	bool btn_4 : 3;
	bool btn_5 : 4;
}

// Mouse Button moved
fn void Ctx.input_mouse_button(&ctx, MouseButtons buttons)
{
	ctx.input.mouse.updated = ctx.input.mouse.down ^ buttons;
	ctx.input.mouse.down = buttons;
	ctx.input.events.mouse_btn = true;

	io::printfn(
	    "Mouse Down: %s%s%s%s%s",
	    buttons.btn_left ? "BTN_LEFT " : "",
	    buttons.btn_right ? "BTN_RIGHT " : "",
	    buttons.btn_middle ? "BTN_MIDDLE " : "",
	    buttons.btn_4 ? "BTN_4 " : "",
	    buttons.btn_5 ? "BTN_5 " : ""
	);
}

// Mouse was moved, report absolute position
// TODO: implement this
fn void Ctx.input_mouse_abs(&ctx, short x, short y) { return; }

// Mouse was moved, report relative motion
fn void Ctx.input_mouse_delta(&ctx, short dx, short dy)
{
	ctx.input.mouse.delta.x = dx;
	ctx.input.mouse.delta.y = dy;

	short mx, my;
	mx = ctx.input.mouse.pos.x + dx;
	my = ctx.input.mouse.pos.y + dy;

	ctx.input.mouse.pos.x = clamp(mx, 0u16, ctx.width);
	ctx.input.mouse.pos.y = clamp(my, 0u16, ctx.height);

	ctx.input.events.mouse_move = true;
}
