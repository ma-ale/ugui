module ugui;

import std::io;

// TODO: this could be a bitstruct
bitstruct InputEvents : uint {
	bool resize : 0; // window size was changed
	bool change_focus : 1; // window focus changed
	bool mouse_move : 2; // mouse was moved
	bool mouse_btn : 3; // mouse button pressed or released
	bool force_update : 4;
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

macro Ctx.mouse_pressed(&ctx)
{
    return ctx.input.mouse.updated & ctx.input.mouse.down;
}

macro Ctx.mouse_released(&ctx)
{
    return ctx.input.mouse.updated & ~ctx.input.mouse.down;
}

macro Ctx.mouse_down(&ctx)
{
    return ctx.input.mouse.down;
}

const MouseButtons BTN_NONE = (MouseButtons)0u;
const MouseButtons BTN_ANY = (MouseButtons)(uint.max);
const MouseButtons BTN_LEFT = {.btn_left = true};
const MouseButtons BTN_MIDDLE = {.btn_middle = true};
const MouseButtons BTN_RIGHT = {.btn_right = true};
const MouseButtons BTN_4 = {.btn_4 = true};
const MouseButtons BTN_5 = {.btn_5 = true};

// FIXME: hthis compairson could be done with a cast using MouseButtons.inner
// property but I could not figure out how
macro Ctx.is_mouse_pressed(&ctx, MouseButtons btn)
{
    return (ctx.mouse_pressed() & btn) != BTN_NONE;
}

macro Ctx.is_mouse_released(&ctx, MouseButtons btn)
{
    return (ctx.mouse_released() & btn) != BTN_NONE;
}

macro Ctx.is_mouse_down(&ctx, MouseButtons btn)
{
    return (ctx.mouse_down() & btn) != BTN_NONE;
}

macro ElemEvents Ctx.get_elem_events(&ctx, Elem *elem)
{
	// TODO: add the other events
	// FIXME: active should be elsewhere
	bool active = elem.events.mouse_hold || ctx.is_hovered(elem);
	ElemEvents ev = {
		.mouse_hover = ctx.is_hovered(elem),
		.mouse_press = active & ctx.is_mouse_pressed(BTN_ANY),
		.mouse_release = active & ctx.is_mouse_released(BTN_ANY),
		.mouse_hold = active & ctx.is_mouse_down(BTN_ANY),
	};
	return ev;
}

// Mouse Button moved
fn void Ctx.input_mouse_button(&ctx, MouseButtons buttons)
{
	ctx.input.mouse.updated = ctx.input.mouse.down ^ buttons;
	ctx.input.mouse.down = buttons;
	ctx.input.events.mouse_btn = true;
}

// Mouse was moved, report absolute position
fn void Ctx.input_mouse_abs(&ctx, short x, short y)
{
	ctx.input.mouse.pos.x = clamp(x, 0u16, ctx.width);
	ctx.input.mouse.pos.y = clamp(y, 0u16, ctx.height);

	short dx, dy;
	dx = x - ctx.input.mouse.pos.x;
	dy = y - ctx.input.mouse.pos.y;

	ctx.input.mouse.delta.x = dx;
	ctx.input.mouse.delta.y = dy;

	ctx.input.events.mouse_move = true;
}

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
