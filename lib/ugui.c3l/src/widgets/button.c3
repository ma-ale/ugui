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
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_BUTTON)!.unpack(&elem, &parent);
	Style* style = ctx.styles.get_style(@str_hash("button"));

	Sprite* sprite = icon != "" ? ctx.sprite_atlas.get(icon)! : &&(Sprite){};
	Rect icon_size = sprite.rect();

	ushort min_size = style.size;
	ushort half_lh = (ushort)(ctx.font.line_height() / 2);
	ushort inner_pad = label != "" && icon != "" ? half_lh : 0;
	/*
	 * +--------------------------------------+
	 * |   +--------+                         |
	 * |   |        |   +-----------------+   |
	 * |   |  icon  |   |     label       |   |
	 * |   |        |   +-----------------+   |
	 * |   +--------+<->|                     |
	 * +-------------^------------------------+
	 *               |inner_pad
	 */
	Point content_size = {
		.x = icon_size.w + inner_pad, // text sizing is handled differently
		.y = icon_size.h + inner_pad,
	};
	elem.layout.w = @fit(min_size);
	elem.layout.h = @fit(min_size);
	elem.layout.children.w = @exact(content_size.x);
	elem.layout.children.h = @exact(content_size.y);
	elem.layout.text = ctx.measure_string(label)!;
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	//elem.events = ctx.get_elem_events(elem);
//	if (ctx.input.z_index == elem.z_index) println("true ", elem.z_index);
	Rect content_bounds = elem.content_bounds();

	Rect icon_bounds = {
		.x = content_bounds.x,
		.y = content_bounds.y,
		.w = icon_size.w,
		.h = icon_size.h
	};
	icon_bounds = icon_size.center_to(icon_bounds);

	Rect text_bounds = {
		.x = content_bounds.x + icon_bounds.w + inner_pad,
		.y = content_bounds.y,
		.w = content_bounds.w - icon_bounds.w - inner_pad,
		.h = content_bounds.h,
	};
	//text_bounds = text_size.center_to(text_bounds);

	bool is_active = elem.events.has_focus || elem.events.mouse_hover;
	Style s = *style;
	if (is_active) {
		s.secondary = s.primary;
		s.bg = s.accent;
	}

	ctx.push_rect(elem.bounds.pad(style.margin), parent.z_index, &s)!;
	if (icon != "") {
		ctx.push_sprite(icon_bounds, sprite.uv(), ctx.sprite_atlas.id, parent.z_index, type: sprite.type)!;
	}
	if (label != "") {
		ctx.layout_string(label, text_bounds, CENTER, parent.z_index, style.fg)!;
	}
	return elem.events;
}


macro Ctx.checkbox(&ctx, String desc, bool* active, String tick_sprite = "", ...)
	=> ctx.checkbox_id(@compute_id($vasplat), desc, active, tick_sprite);
fn void? Ctx.checkbox_id(&ctx, Id id, String description, bool* active, String tick_sprite)
{
	id = ctx.gen_id(id)!;
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_BUTTON)!.unpack(&elem, &parent);
	Style* style = ctx.styles.get_style(@str_hash("checkbox"));

	short inner_pad = description != "" ? style.size/2 : 0;
	/*
	 *                       |< >| style.size/2
	 * +---------------------|---|-----------+
	 * |                     |    .-----. ---|--
	 * |   +-----------------+   '  ###  '   | ^
	 * |   |   description   |   | ##### |   | style.size
	 * |   +-----------------+   .  ###  .   | v
	 * |                          '-----' ---|--
	 * +-------------------------|-------|---+
	 *                           |<----->| style.size
	 */

	elem.layout.w = @fit(style.size);
	elem.layout.h = @fit(style.size);
	elem.layout.children.w = @exact(style.size + inner_pad);
	elem.layout.children.h = @exact(style.size);
	elem.layout.text = ctx.measure_string(description)!;
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	//elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);


	Rect content_bounds = elem.bounds.pad(elem.layout.content_offset);
	Rect text_bounds = {
		.x = content_bounds.x,
		.y = content_bounds.y,
		.w = content_bounds.w - inner_pad - style.size,
		.h = content_bounds.h
	};
	Rect check_bounds = {
		.x = content_bounds.x + text_bounds.w + inner_pad,
		.y = content_bounds.y + (content_bounds.h - style.size)/2,
		.w = style.size,
		.h = style.size,
	};

	Style s;
	s.bg = style.bg;
	s.secondary = style.secondary;
	s.border = style.border;
	s.radius = style.radius;

	ctx.layout_string(description, text_bounds, CENTER, parent.z_index, style.fg)!;
	if (tick_sprite != "") {
		ctx.push_rect(check_bounds, parent.z_index, &s)!;
		if (*active) {
			Sprite* sprite = ctx.sprite_atlas.get(tick_sprite)!;
			Id tex_id = ctx.sprite_atlas.id;
			ctx.push_sprite(sprite.rect().center_to(check_bounds), sprite.uv(), tex_id, parent.z_index, type: sprite.type)!;
		}
	} else {
		if (*active) {
			s.bg = style.primary;
			ctx.push_rect(check_bounds, parent.z_index, &s)!;
		} else {
			ctx.push_rect(check_bounds, parent.z_index, &s)!;
		}
	}
}

macro Ctx.toggle(&ctx, String desc, bool* active)
	=> ctx.toggle_id(@compute_id($vasplat), desc, active);
fn void? Ctx.toggle_id(&ctx, Id id, String description, bool* active)
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_BUTTON)!.unpack(&elem, &parent);
	Style* style = ctx.styles.get_style(@str_hash("toggle"));

	short inner_pad = description != "" ? style.size/2 : 0;
	/*
	 *                       |< >| style.size/2
	 * +---------------------|---|-----------------+
	 * |                     |    .-----------. ---|--
	 * |   +-----------------+   ' #####       '   | ^
	 * |   |   description   |   | #####       |   | style.size
	 * |   +-----------------+   . #####       .   | v
	 * |                          '-----------' ---|--
	 * +-------------------------|-------------|---+
	 *                           |<----->| style.size*2
	 */

	elem.layout.w = @fit(style.size*2);
	elem.layout.h = @fit(style.size);
	elem.layout.children.w = @exact(style.size*2 + inner_pad);
	elem.layout.children.h = @exact(style.size);
	elem.layout.text = ctx.measure_string(description)!;
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	//elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover && elem.events.mouse_release) *active = !(*active);

	Rect content_bounds = elem.bounds.pad(elem.layout.content_offset);
	Rect text_bounds = {
		.x = content_bounds.x,
		.y = content_bounds.y,
		.w = content_bounds.w - inner_pad - style.size*2,
		.h = content_bounds.h
	};
	Rect toggle_bounds = {
		.x = content_bounds.x + text_bounds.w + inner_pad,
		.y = content_bounds.y + (content_bounds.h - style.size)/2,
		.w = style.size*2,
		.h = style.size,
	};
	Rect toggle = {
		.x = toggle_bounds.x + (*active ? style.size : 0),
		.y = toggle_bounds.y,
		.w = style.size,
		.h = style.size
	};

	Style s;
	s.bg = style.bg;
	s.secondary = style.secondary;
	s.border = style.border;
	s.radius = style.radius;
	ctx.layout_string(description, text_bounds, CENTER, parent.z_index, style.fg)!;
	ctx.push_rect(toggle_bounds, parent.z_index, &s)!;
	s.bg = style.primary;
	s.border = {};
	ctx.push_rect(toggle.pad(style.border), parent.z_index, &s)!;

}
