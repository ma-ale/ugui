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
<*
@require value != null
*>
fn ElemEvents! Ctx.slider_hor(&ctx,
    String label,
    Rect size,
    float* value,
    float hpercent = 0.25,
    Color bgcolor = uint_to_rgba(0x0000ffff),
    Color handlecolor = uint_to_rgba(0x0ff000ff))
{
	Id id = ctx.gen_id(label)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	if (elem.flags.is_new) {
		elem.type = ETYPE_SLIDER;
	} else if (elem.type != ETYPE_SLIDER) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	// 2. Layout
	elem.bounds = ctx.position_element(parent, size, true);

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
	
	if (ctx.elem_focus(elem) && elem.events.mouse_hold) {
		*value = calc_value(elem.bounds.x, m.x, elem.bounds.w, hw);
		elem.slider.handle.x = calc_slider(elem.bounds.x, elem.bounds.w-hw, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	ctx.push_rect(elem.bounds, bgcolor)!;
	ctx.push_rect(elem.slider.handle, handlecolor)!;

	return elem.events;
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
fn ElemEvents! Ctx.slider_ver(&ctx,
    String label,
    Rect size,
    float* value,
    float hpercent = 0.25,
    Color bgcolor = uint_to_rgba(0x0000ffff),
    Color handlecolor = uint_to_rgba(0x0ff000ff))
{
	Id id = ctx.gen_id(label)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	if (elem.flags.is_new) {
		elem.type = ETYPE_SLIDER;
	} else if (elem.type != ETYPE_SLIDER) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	// 2. Layout
	elem.bounds = ctx.position_element(parent, size, true);

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

	if (ctx.elem_focus(elem) && elem.events.mouse_hold) {
		*value = calc_value(elem.bounds.y, m.y, elem.bounds.h, hh);
		elem.slider.handle.y = calc_slider(elem.bounds.y, elem.bounds.h-hh, *value);
		elem.events.update = true;
	}

	// Draw the slider background and handle
	ctx.push_rect(elem.bounds, bgcolor)!;
	ctx.push_rect(elem.slider.handle, handlecolor)!;

	return elem.events;
}

macro short calc_slider(ushort off, ushort dim, float value) => (short)off + (short)(dim * value);
macro float calc_value(ushort off, ushort mouse, ushort dim, ushort slider) => math::clamp((float)(mouse-off-slider/2)/(float)(dim-slider), 0.0f, 1.0f);
