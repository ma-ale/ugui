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
macro Ctx.slider_hor(&ctx, Rect size, float* value, float hpercent = 0.25, ...)
	=> ctx.slider_hor_id(@compute_id($vasplat), size, value, hpercent);
<*
@require value != null
*>
fn ElemEvents? Ctx.slider_hor_id(&ctx, Id id, Rect size, float* value, float hpercent = 0.25)
{
	id = ctx.gen_id(id)!;

	Elem* parent = ctx.get_parent()!;
	Elem* elem = ctx.get_elem(id, ETYPE_SLIDER)!;
	Style* style = ctx.styles.get_style(@str_hash("slider"));

	// 2. Layout
	elem.bounds = ctx.position_element(parent, size, style);

	// handle width
	short hw = (short)(elem.bounds.w * hpercent);
	Rect handle = {
		.x = calc_slider(elem.bounds.x, elem.bounds.w-hw, *value),
		.y = elem.bounds.y,
		.w = hw,
		.h = elem.bounds.h,
	};
	elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	elem.events = ctx.get_elem_events(elem);
	
	if (ctx.elem_focus(elem) && ctx.is_mouse_down(BTN_LEFT)) {
		*value = calc_value(elem.bounds.x, m.x, elem.bounds.w, hw);
		elem.slider.handle.x = calc_slider(elem.bounds.x, elem.bounds.w-hw, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
	Style s = *style;
	s.bg = s.primary;
	ctx.push_rect(elem.slider.handle, parent.div.z_index, &s)!;

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
macro Ctx.slider_ver(&ctx, Rect size, float* value, float hpercent = 0.25, ...)
	=> ctx.slider_ver_id(@compute_id($vasplat), size, value, hpercent);
fn ElemEvents? Ctx.slider_ver_id(&ctx, Id id, Rect size, float* value, float hpercent = 0.25)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_SLIDER)!;
	Style* style = ctx.styles.get_style(@str_hash("slider"));

	// 1. Fill the element fields
	if (elem.flags.is_new) {
		elem.type = ETYPE_SLIDER;
	} else if (elem.type != ETYPE_SLIDER) {
		return WRONG_ELEMENT_TYPE?;
	}

	// 2. Layout
	elem.bounds = ctx.position_element(parent, size, style);

	// handle height
	short hh = (short)(elem.bounds.h * hpercent);
	Rect handle = {
		.x = elem.bounds.x,
		.y = calc_slider(elem.bounds.y, elem.bounds.h-hh, *value),
		.w = elem.bounds.w,
		.h = hh,
	};
	elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	elem.events = ctx.get_elem_events(elem);

	if (ctx.elem_focus(elem) && ctx.is_mouse_down(BTN_LEFT)) {
		*value = calc_value(elem.bounds.y, m.y, elem.bounds.h, hh);
		elem.slider.handle.y = calc_slider(elem.bounds.y, elem.bounds.h-hh, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	ctx.push_rect(elem.bounds, parent.div.z_index, style)!;
	Style s = *style;
	s.bg = s.primary;
	ctx.push_rect(elem.slider.handle, parent.div.z_index, &s)!;

	return elem.events;
}

macro short calc_slider(short off, short dim, float value) => (short)off + (short)(dim * value);
macro float calc_value(short off, short mouse, short dim, short slider)
	=> math::clamp((float)(mouse-off-slider/2)/(float)(dim-slider), 0.0f, 1.0f);
