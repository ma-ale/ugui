module ugui;

import std::io;
import std::math;

// slider element
struct ElemSlider {
	Rect handle;
}

/*       handle
 * +----+-----+---------------------+
 * |    |#####|                     |
 * +----+-----+---------------------+
 */
macro Ctx.slider_hor(&ctx, Size w, Size h, float* value, float hpercent = 0.25, ...)
	=> ctx.slider_hor_id(@compute_id($vasplat), w, h, value, hpercent);
<*
@require value != null
*>
fn ElemEvents? Ctx.slider_hor_id(&ctx, Id id, Size w, Size h, float* value, float hpercent = 0.25)
{
	id = ctx.gen_id(id)!;

	Elem* parent = ctx.get_parent()!;
	Elem* elem = ctx.get_elem(id, ETYPE_SLIDER)!;
	Style* style = ctx.styles.get_style(@str_hash("slider"));

	elem.layout.w = w;
	elem.layout.h = h;
	elem.layout.content_offset = style.margin + style.border + style.padding;
	update_parent_size(elem, parent);

	Rect bg_bounds = elem.bounds.pad(style.margin);
	Rect content_bounds = elem.bounds.pad(style.margin + style.border + style.padding);

	// handle width
	short hw = (short)(content_bounds.w * hpercent);
	Rect handle = {
		.x = calc_slider(content_bounds.x, content_bounds.w-hw, *value),
		.y = content_bounds.y,
		.w = hw,
		.h = content_bounds.h,
	};
	elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	elem.events = ctx.get_elem_events(elem);

	if (ctx.elem_focus(elem) && ctx.is_mouse_down(BTN_LEFT)) {
		*value = calc_value(content_bounds.x, m.x, content_bounds.w, hw);
		elem.slider.handle.x = calc_slider(content_bounds.x, content_bounds.w-hw, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	Style s = *style;
	Rect padding = s.padding;
	s.padding = {};
	ctx.push_rect(bg_bounds, parent.z_index, &s)!;
	s.bg = s.primary;
	s.padding = padding;
	s.border = {};
	ctx.push_rect(elem.slider.handle, parent.z_index, &s)!;

	return elem.events;
}


/*
 * +--+
 * |  |
 * |  |
 * +--+
 * |##| handle
 * |##|
 * +--+
 * |  |
 * |  |
 * +--+
 */
macro Ctx.slider_ver(&ctx, Size w, Size h, float* value, float hpercent = 0.25, ...)
	=> ctx.slider_ver_id(@compute_id($vasplat), w, h, value, hpercent);
fn ElemEvents? Ctx.slider_ver_id(&ctx, Id id, Size w, Size h, float* value, float hpercent = 0.25)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_SLIDER)!;
	Style* style = ctx.styles.get_style(@str_hash("slider"));

	elem.layout.w = w;
	elem.layout.h = h;
	elem.layout.content_offset = style.margin + style.border + style.padding;
	update_parent_size(elem, parent);

	// 2. Layout
	Rect bg_bounds = elem.bounds.pad(style.margin);
	Rect content_bounds = elem.bounds.pad(style.margin + style.border + style.padding);

	// handle height
	short hh = (short)(content_bounds.h * hpercent);
	Rect handle = {
		.x = content_bounds.x,
		.y = calc_slider(content_bounds.y, content_bounds.h-hh, *value),
		.w = content_bounds.w,
		.h = hh,
	};
	elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	elem.events = ctx.get_elem_events(elem);

	if (ctx.elem_focus(elem) && ctx.is_mouse_down(BTN_LEFT)) {
		*value = calc_value(content_bounds.y, m.y, content_bounds.h, hh);
		elem.slider.handle.y = calc_slider(content_bounds.y, content_bounds.h-hh, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	Style s = *style;
	Rect padding = s.padding;
	s.padding = {};
	ctx.push_rect(bg_bounds, parent.z_index, &s)!;
	s.bg = s.primary;
	s.padding = padding;
	s.border = {};
	ctx.push_rect(elem.slider.handle, parent.z_index, &s)!;

	return elem.events;
}


fn void? Ctx.scrollbar(&ctx, Id id, float *value, float handle_percent, bool vertical = true)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_SLIDER)!;
	Style* style = ctx.styles.get_style(@str_hash("scrollbar"));

	Rect pb = parent.bounds.pad(parent.layout.content_offset);
	elem.bounds.x = vertical ? pb.bottom_right().x - style.size: pb.x;
	elem.bounds.y = vertical ? pb.y : pb.bottom_right().y - style.size;
	if (vertical) {
		elem.layout.w = @exact(style.size);
		elem.layout.h = @grow();
		elem.bounds.x -= style.margin.x + style.margin.w + style.border.x + style.border.w;
	} else {
		elem.layout.w = @grow();
		elem.layout.h = @exact(style.size);
		elem.bounds.y -= style.margin.y + style.margin.h + style.border.y + style.border.h;
	}
	elem.layout.content_offset = style.margin + style.border + style.padding;
	elem.layout.absolute = true;
	update_parent_size(elem, parent);

	Rect content_bounds = elem.bounds.pad(elem.layout.content_offset);
	elem.events = ctx.get_elem_events(elem);

	short o = vertical ? content_bounds.y : content_bounds.x;
	short m = vertical ? ctx.input.mouse.pos.y : ctx.input.mouse.pos.x;
	short s = vertical ? content_bounds.h : content_bounds.w;
	short h = (short)((float)s * handle_percent);
	if (elem.events.has_focus && ctx.is_mouse_down(BTN_LEFT)) {
		*value = calc_value(o, m, s, h);
		elem.events.update = true;
	}
	short handle_pos = calc_slider(o, s-h, *value);

	elem.slider.handle = {
		.x = vertical ? content_bounds.x : handle_pos,
		.y = vertical ? handle_pos : content_bounds.y,
		.w = vertical ? content_bounds.w : h,
		.h = vertical ? h : content_bounds.h,
	};


	Rect bg_bounds = elem.bounds.pad(style.margin);
	ctx.push_rect(bg_bounds, parent.z_index, style)!;
	ctx.push_rect(elem.slider.handle, parent.z_index, &&(Style){.bg = style.primary, .radius = style.radius})!;
}

macro short calc_slider(short off, short dim, float value) => (short)off + (short)(dim * value);
macro float calc_value(short off, short mouse, short dim, short slider)
	=> math::clamp((float)(mouse-off-slider/2)/(float)(dim-slider), 0.0f, 1.0f);
