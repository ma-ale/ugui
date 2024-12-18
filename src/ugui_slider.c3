module ugui;

import std::io;
import std::math;

// slider element
struct ElemSlider {
	Rect handle;
}

const Elem SLIDER_DEFAULT = {
	.type = ETYPE_SLIDER,
};

/*       handle
 * +----+-----+---------------------+
 * |    |#####|                     |
 * +----+-----+---------------------+
 */
<*
@require value != null
*>
fn ElemEvents! Ctx.slider_hor(&ctx, String label, Rect size, float* value)
{
	Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	if (c_elem.flags.is_new) {
		*c_elem = SLIDER_DEFAULT;
	} else if (c_elem.type != SLIDER_DEFAULT.type) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	// 2. Layout
	c_elem.bounds = ctx.position_element(parent, size, true);

	// handle width
	short hw = (short)(c_elem.bounds.w * 0.25);
	Rect handle = {
		.x = calc_slider(c_elem.bounds.x, c_elem.bounds.w-hw, *value),
		.y = c_elem.bounds.y,
		.w = hw,
		.h = c_elem.bounds.h,
	};
	c_elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	c_elem.events = ctx.get_elem_events(c_elem);
	
	if (parent.flags.has_focus && c_elem.events.mouse_hover &&
	    point_in_rect(m, handle) && c_elem.events.mouse_hold) {
		*value = calc_value(c_elem.bounds.x, m.x, c_elem.bounds.w, hw);
		c_elem.slider.handle.x = calc_slider(c_elem.bounds.x, c_elem.bounds.w-hw, *value);
		c_elem.events.update = true;
	}

	// Draw the slider background and handle
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);
	ctx.push_rect(c_elem.bounds, bg_color)!;
	ctx.push_rect(c_elem.slider.handle, handle_color)!;

	return c_elem.events;
}

/*
 * +-+
 * | |
 * | |
 * +-+
 * |#| handle
 * |#|
 * +-+
 * | |
 * | |
 * +-+
 */
fn ElemEvents! Ctx.slider_ver(&ctx, String label, Rect size, float* value)
{
	Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	if (c_elem.flags.is_new) {
		*c_elem = SLIDER_DEFAULT;
	} else if (c_elem.type != SLIDER_DEFAULT.type) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	// 2. Layout
	c_elem.bounds = ctx.position_element(parent, size, true);

	// handle height
	short hh = (short)(c_elem.bounds.h * 0.25);
	Rect handle = {
		.x = c_elem.bounds.x,
		.y = calc_slider(c_elem.bounds.y, c_elem.bounds.h-hh, *value),
		.w = c_elem.bounds.w,
		.h = hh,
	};
	c_elem.slider.handle = handle;

	Point m = ctx.input.mouse.pos;
	c_elem.events = ctx.get_elem_events(c_elem);
	
	if (parent.flags.has_focus && c_elem.events.mouse_hover &&
	    point_in_rect(m, handle) &&
	    c_elem.events.mouse_hold) {
		*value = calc_value(c_elem.bounds.y, m.y, c_elem.bounds.h, hh);
		c_elem.slider.handle.y = calc_slider(c_elem.bounds.y, c_elem.bounds.h-hh, *value);
		c_elem.events.update = true;
	}

	// Draw the slider background and handle
	Color bg_color = uint_to_rgba(0x0000ffff);
	Color handle_color = uint_to_rgba(0x0ff000ff);
	ctx.push_rect(c_elem.bounds, bg_color)!;
	ctx.push_rect(c_elem.slider.handle, handle_color)!;

	return c_elem.events;
}

macro short calc_slider(ushort off, ushort dim, float value) => (short)off + (short)(dim * value);
macro float calc_value(ushort off, ushort mouse, ushort dim, ushort slider) => math::clamp((float)(mouse-off-slider/2)/(float)(dim-slider), 0.0f, 1.0f);
