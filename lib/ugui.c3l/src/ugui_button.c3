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
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;
	Style* style_norm = ctx.styles.get_style(@str_hash("button"));

	elem.bounds = ctx.position_element(parent, size, style_norm);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return {}; }

	Style* style_active = ctx.styles.get_style(@str_hash("button-active"));

	elem.events = ctx.get_elem_events(elem);
	bool is_active = active || ctx.elem_focus(elem) || elem.events.mouse_hover;

	// Draw the button
	ctx.push_rect(elem.bounds, parent.div.z_index, is_active ? style_active : style_norm)!;

	return elem.events;
}

macro Ctx.button_label(&ctx, String label, Rect size = {0,0,short.max,short.max}, bool active = false, ...)
	=> ctx.button_label_id(@compute_id($vasplat), label, size, active);
fn ElemEvents? Ctx.button_label_id(&ctx, Id id, String label, Rect size, bool active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;
	Style* style_norm = ctx.styles.get_style(@str_hash("button"));
	Style* style_active = ctx.styles.get_style(@str_hash("button-active"));

	// TODO: cache text_size just like text_unbounded() does
	Rect text_size = ctx.get_text_bounds(label)!;
	Rect btn_size = text_size.grow({10,10});

	// 2. Layout
	elem.bounds = ctx.position_element(parent, btn_size, style_norm);
	if (elem.bounds.is_null()) { return {}; }
	
	text_size.x = elem.bounds.x;
	text_size.y = elem.bounds.y;
	text_size = text_size.center_to(elem.bounds);

	elem.events = ctx.get_elem_events(elem);

	bool is_active = active || ctx.elem_focus(elem) || elem.events.mouse_hover;
	Style* style = is_active ? style_active : style_norm;

	// Draw the button
	ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
	ctx.push_string(text_size, label, parent.div.z_index, style.fg)!;

	return elem.events;
}

macro Ctx.button_icon(&ctx, String icon, String on_icon = "", bool active = false, ...)
	=> ctx.button_icon_id(@compute_id($vasplat), icon, on_icon, active);
fn ElemEvents? Ctx.button_icon_id(&ctx, Id id, String icon, String on_icon, bool active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;

	Sprite* def_sprite = ctx.sprite_atlas.get(icon)!;
	Sprite* on_sprite = ctx.sprite_atlas.get(on_icon) ?? &&(Sprite){};
	Rect max_size = def_sprite.rect().max(on_sprite.rect());

	Style* style_norm = ctx.styles.get_style(@str_hash("button"));

	elem.bounds = ctx.position_element(parent, max_size, style_norm);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return {}; }

	Style* style_active = ctx.styles.get_style(@str_hash("button-active"));

	elem.events = ctx.get_elem_events(elem);

	bool is_active = active || ctx.elem_focus(elem) || elem.events.mouse_hover;
	Style* style = is_active ? style_active : style_norm;

	Id tex_id = ctx.sprite_atlas.id;
	if (active && on_icon != "") {
		ctx.push_sprite(elem.bounds, on_sprite.uv(), tex_id, parent.div.z_index, type: on_sprite.type)!;
	} else {
		ctx.push_sprite(elem.bounds, def_sprite.uv(), tex_id, parent.div.z_index, type: def_sprite.type)!;
	}

	// Draw the button
	ctx.push_rect(elem.bounds, parent.div.z_index, style)!;

	return elem.events;
}

// FIXME: this should be inside the style
macro Ctx.checkbox(&ctx, String desc, Point off, bool* active, String tick_sprite = {}, ...)
	=> ctx.checkbox_id(@compute_id($vasplat), desc, off, active, tick_sprite);
fn void? Ctx.checkbox_id(&ctx, Id id, String description, Point off, bool* active, String tick_sprite)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;
	Style* style = ctx.styles.get_style(@str_hash("checkbox"));

	Rect size = {off.x, off.y, style.size, style.size};
	elem.bounds = ctx.position_element(parent, size, style);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) return;

	elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);
	
	if (tick_sprite != {}) {
		ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
		if (*active) {
			ctx.draw_sprite_raw(tick_sprite, elem.bounds, center: true)!;
		}
	} else {
		ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
		if (*active) {
			ushort x = style.size / 4;
			Rect check = elem.bounds.add({x, x, -x*2, -x*2});
			Style s = *style;
			s.bg = s.primary;
			s.margin = s.border = s.padding = {};
			ctx.push_rect(check, parent.div.z_index, &s)!;
		}
	}
}

// FIXME: this should be inside the style
macro Ctx.toggle(&ctx, String desc, Point off, bool* active)
	=> ctx.toggle_id(@compute_id($vasplat), desc, off, active);
fn void? Ctx.toggle_id(&ctx, Id id, String description, Point off, bool* active)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;
	Style* style = ctx.styles.get_style(@str_hash("toggle"));

	Rect size = {off.x, off.y, style.size*2, style.size};
	elem.bounds = ctx.position_element(parent, size, style);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) return;

	elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);

	// Draw the button
	// FIXME: THIS IS SHIT
	ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
	Rect t = elem.bounds.add({*active ? (style.size+3) : +3, +3, -style.size-6, -6});
	Style s = *style;
	s.bg = s.primary;
	s.margin = s.border = s.padding = {};
	ctx.push_rect(t, parent.div.z_index, &s)!;
}
