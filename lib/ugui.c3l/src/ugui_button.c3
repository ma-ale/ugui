module ugui;

import std::io;

// button element
struct ElemButton {
	int filler;
}


macro Ctx.button(&ctx, String label = "", String icon = "", ...)
	=> ctx.button_id(@compute_id($vasplat), label, icon);
fn ElemEvents? Ctx.button_id(&ctx, Id id, String label, String icon)
{
	id = ctx.gen_id(id)!;
	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_BUTTON)!;
	Style* style = ctx.styles.get_style(@str_hash("button"));
	
	Sprite* sprite = icon != "" ? ctx.sprite_atlas.get(icon)! : &&(Sprite){};

	// TODO: get min size by style
	TextSize text_size = ctx.measure_string(label)!;
	Rect icon_size = sprite.rect();
	
	ushort min_size = style.size; 
	ushort half_lh = (ushort)(ctx.font.line_height() / 2);
	ushort left_pad = label != "" ? half_lh : 0;
	ushort inner_pad = label != "" && icon != "" ? half_lh : 0;
	ushort right_pad = left_pad;
	
	/*    |left_pad
	 * +--v-----------------------------------+
	 * |<->+--------+                         |
	 * |   |        |   +-----------------+   |
	 * |   |  icon  |   |     label       |   |
	 * |   |        |   +-----------------+   |
	 * |   +--------+<->|                 |<->|
	 * +-------------^--------------------^---+
	 *               |inner_pad           |right_pad
	 */
	
	elem.layout.w = {
		.min = (short)max(min_size, left_pad + icon_size.w + inner_pad + text_size.width.min + right_pad),
		.max = (short)max(min_size, left_pad + icon_size.w + inner_pad + text_size.width.max + right_pad),
	};
	elem.layout.h = {
		.min = (short)max(min_size, left_pad + icon_size.h + text_size.height.min + right_pad),
		.max = (short)max(min_size, left_pad + icon_size.w + text_size.height.max + right_pad),
	};
	// add style border and padding
	elem.layout.margin = style.margin;
	elem.layout.border = style.border;
	elem.layout.padding = style.padding;

	elem.layout.children.w = elem.layout.w;
	elem.layout.children.h = elem.layout.h;

	update_parent_grow(elem, parent);
	update_parent_size(elem, parent);

	elem.events = ctx.get_elem_events(elem);
	Rect content_bounds = elem.content_bounds(style);
	
	Rect text_bounds = {
		.x = content_bounds.x + icon_size.w + left_pad + inner_pad,
		.y = content_bounds.y,
		.w = content_bounds.w - icon_size.w - left_pad - inner_pad - right_pad,
		.h = content_bounds.h
	};
	//text_bounds = text_size.center_to(text_bounds);
	
	Rect icon_bounds = {
		.x = content_bounds.x,
		.y = content_bounds.y,
		.w = icon_size.w + right_pad + inner_pad,
		.h = (short)max(icon_size.h, content_bounds.h)
	};
	icon_bounds = icon_size.center_to(icon_bounds);

	bool is_active = ctx.elem_focus(elem) || elem.events.mouse_hover;
	Style s = *style;
	if (is_active) {
		s.secondary = s.primary;
		s.bg = s.accent;
	}

	ctx.push_rect(elem.bounds, parent.div.z_index, &s)!;
	if (icon != "") {
		ctx.push_sprite(icon_bounds, sprite.uv(), ctx.sprite_atlas.id, parent.div.z_index, type: sprite.type)!;
	}
	if (label != "") {
		ctx.push_string(text_bounds, label, parent.div.z_index, style.fg)!;
	}
	return elem.events;
}

/*

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
	elem.bounds = ctx.layout_element(parent, size, style);

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
	elem.bounds = ctx.layout_element(parent, size, style);

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
*/