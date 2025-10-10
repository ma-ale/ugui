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
	bool key_press    : 7;
	bool key_release  : 8;
	bool key_repeat   : 9;
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
// Modifier Keys, intended as any key that is not text
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
	bool bkspc  : 12;
	bool del    : 13;
	// arrow keys
	bool up     : 14;
	bool down   : 15;
	bool left   : 16;
	bool right  : 17;
}

const ModKeys KMOD_CTRL  = {.lctrl  = true, .rctrl  = true};
const ModKeys KMOD_SHIFT = {.lshift = true, .rshift = true};
const ModKeys KMOD_ALT   = {.lalt   = true, .ralt   = true};
const ModKeys KMOD_GUI   = {.lgui   = true, .rgui   = true};
const ModKeys KMOD_TXT   = {.bkspc  = true, .del    = true}; // modkeys that act like text input
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

fn bool Ctx.check_key_combo(&ctx, ModKeys mod, String ...keys)
{
	bool is_mod = (bool)(ctx.current_input.keyboard.modkeys & mod);
	bool is_keys = true;
	String haystack = (String)ctx.get_keys();
	foreach (needle: keys) {
		is_keys = is_keys && haystack.contains(needle);
	}
	return is_mod && is_keys;
}

// Window size was changed
fn void? Ctx.input_window_size(&ctx, short width, short height)
{
	if (width <= 0 || height <= 0) {
		return INVALID_SIZE?;
	}
	ctx.current_input.events.resize = ctx.width != width || ctx.height != height;
	ctx.width = width;
	ctx.height = height;
}

// Window gained/lost focus
fn void Ctx.input_changefocus(&ctx, bool has_focus)
{
	// FIXME: raylib only has an API to query the focus status so we have to
	//        update the input flag only if the focus changed
	ctx.current_input.events.change_focus = ctx.has_focus != has_focus;
	ctx.has_focus = has_focus;
}

macro Ctx.mouse_pressed(&ctx) => ctx.current_input.mouse.updated & ctx.current_input.mouse.down;
macro Ctx.mouse_released(&ctx) => ctx.current_input.mouse.updated & ~ctx.current_input.mouse.down;
macro Ctx.mouse_down(&ctx) => ctx.current_input.mouse.down;

// FIXME: hthis compairson could be done with a cast using MouseButtons.inner
// property but I could not figure out how
macro Ctx.is_mouse_pressed(&ctx, MouseButtons btn) => (ctx.mouse_pressed() & btn) != BTN_NONE;
macro Ctx.is_mouse_released(&ctx, MouseButtons btn) => (ctx.mouse_released() & btn) != BTN_NONE;
macro Ctx.is_mouse_down(&ctx, MouseButtons btn) => (ctx.mouse_down() & btn) != BTN_NONE;

// Mouse Buttons down
fn void Ctx.input_mouse_button(&ctx, MouseButtons buttons)
{
	ctx.current_input.mouse.updated = ctx.current_input.mouse.down ^ buttons;
	ctx.current_input.mouse.down = buttons;
	ctx.current_input.events.mouse_btn = (uint)ctx.current_input.mouse.down != 0 || (uint)ctx.current_input.mouse.updated != 0;
}

// Mouse was moved, report absolute position
fn void Ctx.input_mouse_abs(&ctx, short x, short y)
{
	ctx.current_input.mouse.pos.x = math::clamp(x, (short)0, ctx.width);
	ctx.current_input.mouse.pos.y = math::clamp(y, (short)0, ctx.height);

	short dx, dy;
	dx = x - ctx.current_input.mouse.pos.x;
	dy = y - ctx.current_input.mouse.pos.y;

	ctx.current_input.mouse.delta.x = dx;
	ctx.current_input.mouse.delta.y = dy;

	ctx.current_input.events.mouse_move = dx != 0 || dy != 0;
}

// Mouse was moved, report relative motion
fn void Ctx.input_mouse_delta(&ctx, short dx, short dy)
{
	ctx.current_input.mouse.delta.x = dx;
	ctx.current_input.mouse.delta.y = dy;

	short mx, my;
	mx = ctx.current_input.mouse.pos.x + dx;
	my = ctx.current_input.mouse.pos.y + dy;

	ctx.current_input.mouse.pos.x = math::clamp(mx, (short)0, ctx.width);
	ctx.current_input.mouse.pos.y = math::clamp(my, (short)0, ctx.height);

	ctx.current_input.events.mouse_move = dx != 0 || dy != 0;
}

fn void Ctx.input_mouse_wheel(&ctx, short x, short y, float scale = 1.0)
{
	ctx.current_input.mouse.scroll.x = (short)((float)-x*scale);
	ctx.current_input.mouse.scroll.y = (short)((float)-y*scale);
	ctx.current_input.events.mouse_scroll = x !=0 || y != 0;
}

fn void Ctx.input_key_press(&ctx)
{
	ctx.current_input.events.key_press = true;
}

fn void Ctx.input_key_release(&ctx)
{
	ctx.current_input.events.key_release = true;
}

fn void Ctx.input_key_repeat(&ctx)
{
	ctx.current_input.events.key_repeat = true;
}

// append utf-8 encoded text to the context text input
fn void Ctx.input_text_utf8(&ctx, char[] text)
{
	if (text.len == 0) { return; }

	usz remaining = ctx.current_input.keyboard.text.len - ctx.current_input.keyboard.text_len;
	usz len = text.len > remaining ? remaining : text.len;
	char[] s = ctx.current_input.keyboard.text[ctx.current_input.keyboard.text_len ..];
	s[..len-1] = text[..len-1];
	ctx.current_input.keyboard.text_len += len;
	ctx.current_input.events.text_input = true;
}

fn void Ctx.input_text_unicode(&ctx, char[] text)
{
	if (text.ptr == null || text.len == 0) { return; }

	char[32] tmp;
	usz remaining = ctx.current_input.keyboard.text.len - ctx.current_input.keyboard.text_len;
	char[] s = ctx.current_input.keyboard.text[ctx.current_input.keyboard.text_len ..];

	usz off;
	foreach (idx, cp: text) {
		if (off >= remaining) { break; }
		usz enc = grapheme::encode_utf8(cp, tmp[..], tmp.len);
		s[off..off+enc] = tmp[..enc];
		off += enc;
	}
	ctx.current_input.keyboard.text_len += off;

	ctx.current_input.events.text_input = true;
}

fn void Ctx.input_char(&ctx, char c)
{
	char[1] b = {c};
	ctx.input_text_utf8(b[..]);
}

fn String Ctx.get_keys(&ctx) => (String)ctx.input.keyboard.text[:ctx.input.keyboard.text_len];
fn ModKeys Ctx.get_mod(&ctx) => ctx.input.keyboard.modkeys;

// Modifier keys, like control or backspace
// TODO: make this call repetible to input modkeys one by one
fn void Ctx.input_mod_keys(&ctx, ModKeys modkeys)
{
	ctx.current_input.keyboard.modkeys = modkeys;
	ctx.current_input.events.mod_key = (uint)ctx.current_input.keyboard.modkeys != 0;
}
