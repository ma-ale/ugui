module ugui;

import grapheme;
import std::io;
import std::math;
import std::core::string;

bitstruct InputEvents : uint {
	bool resize       : 0; // window size was changed
	bool change_focus : 1; // window focus changed
	bool mouse_move   : 2; // mouse was moved
	bool mouse_btn    : 3; // mouse button pressed or released
	bool mouse_scroll : 4; // mouse scroll wheel. x or y
	bool text_input   : 5;
	bool mod_key      : 6;
}

bitstruct MouseButtons : uint {
	bool btn_left   : 0;
	bool btn_middle : 1;
	bool btn_right  : 2;
	bool btn_4      : 3;
	bool btn_5      : 4;
}

// FIXME: all of these names were prefixed with key_ idk if this is better,
//        if it is remove the prefix on MouseButtons as well
// Modifier Keys, same as SDL
bitstruct ModKeys : uint {
	bool lshift :  0;
	bool rshift :  1;
	bool lctrl  :  2;
	bool rctrl  :  3;
	bool lalt   :  4;
	bool ralt   :  5;
	bool lgui   :  6;
	bool rgui   :  7;
	bool num    :  8;
	bool caps   :  9;
	bool mode   : 10;
	bool scroll : 11;
}

const ModKeys KMOD_CTRL  = {.lctrl  = true, .rctrl  = true};
const ModKeys KMOD_SHIFT = {.lshift = true, .rshift = true};
const ModKeys KMOD_ALT   = {.lalt   = true, .ralt   = true};
const ModKeys KMOD_GUI   = {.lgui   = true, .rgui   = true};
const ModKeys KMOD_NONE  = {};
const ModKeys KMOD_ANY   = (ModKeys)(ModKeys.inner.max);

const MouseButtons BTN_NONE   = {};
const MouseButtons BTN_ANY    = (MouseButtons)(MouseButtons.inner.max);
const MouseButtons BTN_LEFT   = {.btn_left   = true};
const MouseButtons BTN_MIDDLE = {.btn_middle = true};
const MouseButtons BTN_RIGHT  = {.btn_right  = true};
const MouseButtons BTN_4      = {.btn_4      = true};
const MouseButtons BTN_5      = {.btn_5      = true};

const ModKeys KEY_ANY = (ModKeys)(ModKeys.inner.max);

fn bool Ctx.check_key_combo(&ctx, ModKeys mod, String keys)
{
	bool is_mod = (bool)(ctx.input.keyboard.down & mod);
	bool is_keys = true;
	String haystack = (String)ctx.input.keyboard.text[0..ctx.input.keyboard.text_len];
	char[2] needle;
	foreach (c: keys) {
		needle[0] = c;
		is_keys = is_keys && haystack.contains((String)needle[..]);
	}
	return is_mod && is_keys;
}

// Window size was changed
fn void? Ctx.input_window_size(&ctx, short width, short height)
{
	if (width <= 0 || height <= 0) {
		return INVALID_SIZE?;
	}
	ctx.input.events.resize = ctx.width != width || ctx.height != height;
	ctx.width = width;
	ctx.height = height;
}

// Window gained/lost focus
fn void Ctx.input_changefocus(&ctx, bool has_focus)
{
	// FIXME: raylib only has an API to query the focus status so we have to
	//        update the input flag only if the focus changed
	ctx.input.events.change_focus = ctx.has_focus != has_focus;
	ctx.has_focus = has_focus;
}

macro Ctx.mouse_pressed(&ctx) => ctx.input.mouse.updated & ctx.input.mouse.down;
macro Ctx.mouse_released(&ctx) => ctx.input.mouse.updated & ~ctx.input.mouse.down;
macro Ctx.mouse_down(&ctx) => ctx.input.mouse.down;

// FIXME: hthis compairson could be done with a cast using MouseButtons.inner
// property but I could not figure out how
macro Ctx.is_mouse_pressed(&ctx, MouseButtons btn) => (ctx.mouse_pressed() & btn) != BTN_NONE;
macro Ctx.is_mouse_released(&ctx, MouseButtons btn) => (ctx.mouse_released() & btn) != BTN_NONE;
macro Ctx.is_mouse_down(&ctx, MouseButtons btn) => (ctx.mouse_down() & btn) != BTN_NONE;

// Mouse Buttons down
fn void Ctx.input_mouse_button(&ctx, MouseButtons buttons)
{
	ctx.input.mouse.updated = ctx.input.mouse.down ^ buttons;
	ctx.input.mouse.down = buttons;
	ctx.input.events.mouse_btn = (uint)ctx.input.mouse.down != 0 || (uint)ctx.input.mouse.updated != 0;
}

// Mouse was moved, report absolute position
fn void Ctx.input_mouse_abs(&ctx, short x, short y)
{
	ctx.input.mouse.pos.x = math::clamp(x, 0u16, ctx.width);
	ctx.input.mouse.pos.y = math::clamp(y, 0u16, ctx.height);

	short dx, dy;
	dx = x - ctx.input.mouse.pos.x;
	dy = y - ctx.input.mouse.pos.y;

	ctx.input.mouse.delta.x = dx;
	ctx.input.mouse.delta.y = dy;

	ctx.input.events.mouse_move = dx != 0 || dy != 0;
}

// Mouse was moved, report relative motion
fn void Ctx.input_mouse_delta(&ctx, short dx, short dy)
{
	ctx.input.mouse.delta.x = dx;
	ctx.input.mouse.delta.y = dy;

	short mx, my;
	mx = ctx.input.mouse.pos.x + dx;
	my = ctx.input.mouse.pos.y + dy;

	ctx.input.mouse.pos.x = math::clamp(mx, 0u16, ctx.width);
	ctx.input.mouse.pos.y = math::clamp(my, 0u16, ctx.height);

	ctx.input.events.mouse_move = dx != 0 || dy != 0;
}

fn void Ctx.input_mouse_wheel(&ctx, short x, short y, float scale = 1.0)
{
	ctx.input.mouse.scroll.x = (short)((float)-x*scale);
	ctx.input.mouse.scroll.y = (short)((float)-y*scale);
	ctx.input.events.mouse_scroll = x !=0 || y != 0;
}

// append utf-8 encoded text to the context text input
fn void Ctx.input_text_utf8(&ctx, char[] text)
{
	if (text.len == 0) { return; }

	usz remaining = ctx.input.keyboard.text.len - ctx.input.keyboard.text_len;
	usz len = text.len > remaining ? remaining : text.len;
	char[] s = ctx.input.keyboard.text[ctx.input.keyboard.text_len ..];
	s[..len-1] = text[..len-1];
	ctx.input.keyboard.text_len += len;
	ctx.input.events.text_input = true;
}

fn void Ctx.input_text_unicode(&ctx, char[] text)
{
	if (text.ptr == null || text.len == 0) { return; }

	char[32] tmp;
	usz remaining = ctx.input.keyboard.text.len - ctx.input.keyboard.text_len;
	char[] s = ctx.input.keyboard.text[ctx.input.keyboard.text_len ..];

	usz off;
	foreach (idx, cp: text) {
		if (off >= remaining) { break; }
		usz enc = grapheme::encode_utf8(cp, tmp[..], tmp.len);
		s[off..off+enc] = tmp[..enc];
		off += enc;
	}
	ctx.input.keyboard.text_len += off;

	ctx.input.events.text_input = true;
}

// Mouse Buttons down
fn void Ctx.input_mod_keys(&ctx, ModKeys modkeys)
{
	ctx.input.keyboard.down = modkeys;
	ctx.input.events.mod_key = (uint)ctx.input.keyboard.down != 0;
}
