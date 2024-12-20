module ugui;

import std::io;

// button element
struct ElemButton {
	int filler;
}

// draw a button, return the events on that button
fn ElemEvents! Ctx.button(&ctx, String label, Rect size, bool state = false)
{
	Id id = ctx.gen_id(label)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	if (elem.flags.is_new) {
		elem.type = ETYPE_BUTTON;
	} else if (elem.type != ETYPE_BUTTON) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return ElemEvents{}; }

	Color col = uint_to_rgba(0x0000ffff);
	elem.events = ctx.get_elem_events(elem);
	if (state) {
		col = uint_to_rgba(0xff0000ff);
	} else if (ctx.elem_focus(elem) || elem.events.mouse_hover) {
		col = uint_to_rgba(0xff00ffff);
	}

	// Draw the button
	ctx.push_rect(elem.bounds, col, do_border: true, do_radius: true)!;

	return elem.events;
}
