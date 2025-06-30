module ugui;

import std::io;

// button element
struct ElemButton {
	int filler;
}


// draw a button, return the events on that button
macro Ctx.button(&ctx, Rect size, bool state = false, ...)
	=> ctx.button_id(@compute_id($vasplat), size, state);
fn ElemEvents? Ctx.button_id(&ctx, Id id, Rect size, bool active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	if (elem.flags.is_new) {
		elem.type = ETYPE_BUTTON;
	} else if (elem.type != ETYPE_BUTTON) {
		return WRONG_ELEMENT_TYPE?;
	}

	elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return {}; }

	Color col = 0x0000ffffu.to_rgba();
	elem.events = ctx.get_elem_events(elem);
	if (active) {
		col = 0xff0000ffu.to_rgba();
	} else if (ctx.elem_focus(elem) || elem.events.mouse_hover) {
		col = 0xff00ffffu.to_rgba();
	}

	// Draw the button
	ctx.push_rect(elem.bounds, col, parent.div.z_index, do_border: true, do_radius: true)!;

	return elem.events;
}

macro Ctx.button_label(&ctx, String label, Rect size = {0,0,short.max,short.max}, bool active = false, ...)
	=> ctx.button_label_id(@compute_id($vasplat), label, size, active);
fn ElemEvents? Ctx.button_label_id(&ctx, Id id, String label, Rect size, bool active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	// this resets the flags
	elem.type = ETYPE_BUTTON;

	short line_height = (short)ctx.font.ascender - (short)ctx.font.descender;
	Rect text_size = ctx.get_text_bounds(label)!;
	Rect btn_size = text_size.add({0,0,10,10});

	// 2. Layout
	elem.bounds = ctx.position_element(parent, btn_size, true);
	if (elem.bounds.is_null()) { return {}; }

	Color col = 0x0000ffffu.to_rgba();
	elem.events = ctx.get_elem_events(elem);
	if (active) {
		col = 0xff0000ffu.to_rgba();
	} else if (ctx.elem_focus(elem) || elem.events.mouse_hover) {
		col = 0xff00ffffu.to_rgba();
	}

	// Draw the button
	text_size.x = elem.bounds.x;
	text_size.y = elem.bounds.y;
	Point off = ctx.center_text(text_size, elem.bounds);
	text_size.x += off.x;
	text_size.y += off.y;
	ctx.push_rect(elem.bounds, col, parent.div.z_index, do_border: true, do_radius: true)!;
	ctx.push_string(text_size, label, parent.div.z_index)!;

	return elem.events;
}

macro Ctx.button_icon(&ctx, String icon, String on_icon = "", bool active = false, ...)
	=> ctx.button_icon_id(@compute_id($vasplat), icon, on_icon, active);
fn ElemEvents? Ctx.button_icon_id(&ctx, Id id, String icon, String on_icon, bool active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	if (elem.flags.is_new) {
		elem.type = ETYPE_BUTTON;
	} else if (elem.type != ETYPE_BUTTON) {
		return WRONG_ELEMENT_TYPE?;
	}

	Sprite* def_sprite = ctx.sprite_atlas.get(icon)!;
	Sprite* on_sprite = ctx.sprite_atlas.get(on_icon) ?? &&(Sprite){};
	Rect max_size = def_sprite.rect().max(on_sprite.rect());

	elem.bounds = ctx.position_element(parent, max_size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return {}; }

	Color col = 0x0000ffffu.to_rgba();
	elem.events = ctx.get_elem_events(elem);

	Id tex_id = ctx.sprite_atlas.id;
	if (active && on_icon != "") {
		ctx.push_sprite(elem.bounds, on_sprite.uv(), tex_id, parent.div.z_index, type: on_sprite.type)!;
	} else {
		ctx.push_sprite(elem.bounds, def_sprite.uv(), tex_id, parent.div.z_index, type: def_sprite.type)!;
	}

	// Draw the button
	ctx.push_rect(elem.bounds, col, parent.div.z_index, do_border: true, do_radius: true)!;

	return elem.events;
}

// FIXME: this should be inside the style
const ushort DEFAULT_CHECKBOX_SIZE = 16;
macro Ctx.checkbox(&ctx, String desc, Point off, bool* active, String tick_sprite = {}, ...)
	=> ctx.checkbox_id(@compute_id($vasplat), desc, off, active, tick_sprite);
fn void? Ctx.checkbox_id(&ctx, Id id, String description, Point off, bool* active, String tick_sprite)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// FIXME: for now checkboxes and buttons have no members so the element types
	//        can be the same
	if (elem.flags.is_new) {
		elem.type = ETYPE_BUTTON;
	} else if (elem.type != ETYPE_BUTTON) {
		return WRONG_ELEMENT_TYPE?;
	}

	Rect size = {off.x, off.y, DEFAULT_CHECKBOX_SIZE, DEFAULT_CHECKBOX_SIZE};
	elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) return;

	elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);

	Color col;
	if (tick_sprite != {}) {
		col = ctx.style.bgcolor;
		ctx.push_rect(elem.bounds, col, parent.div.z_index, do_border: true, do_radius: true)!;
		if (*active) {
			ctx.draw_sprite_raw(tick_sprite, elem.bounds)!;
		}
	} else {
		if (*active) {
			col = 0xff0000ffu.to_rgba();
		} else {
			col = 0xff00ffffu.to_rgba();
		}
		// Draw the button
		ctx.push_rect(elem.bounds, col, parent.div.z_index, do_border: true, do_radius: true)!;
	}
}

// FIXME: this should be inside the style
const short DEFAULT_SWITCH_SIZE = 16;
macro Ctx.toggle(&ctx, String desc, Point off, bool* active)
	=> ctx.toggle_id(@compute_id($vasplat), desc, off, active);
fn void? Ctx.toggle_id(&ctx, Id id, String description, Point off, bool* active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// FIXME: for now switches and buttons have no members so the element types
	//        can be the same
	if (elem.flags.is_new) {
		elem.type = ETYPE_BUTTON;
	} else if (elem.type != ETYPE_BUTTON) {
		return WRONG_ELEMENT_TYPE?;
	}

	Rect size = {off.x, off.y, DEFAULT_SWITCH_SIZE*2, DEFAULT_SWITCH_SIZE};
	elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) return;

	elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);

	Color col;
	if (*active) {
		col = 0xff0000ffu.to_rgba();
	} else {
		col = 0xff00ffffu.to_rgba();
	}
	// Draw the button
	// FIXME: THIS IS SHIT
	ctx.push_rect(elem.bounds, ctx.style.bgcolor, parent.div.z_index, do_border: true, do_radius: true)!;
	Rect t = elem.bounds.add({*active ? (DEFAULT_SWITCH_SIZE+3) : +3, +3, -DEFAULT_SWITCH_SIZE-6, -6});
	ctx.push_rect(t, col, parent.div.z_index, do_border: false, do_radius: true)!;
}
