module ugui;

import std::io;

// button element
struct ElemButton {
	Color color;
	bool active;
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
		elem.button.color = uint_to_rgba(0x0000ffff);
	} else if (elem.type != ETYPE_BUTTON) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) { return ElemEvents{}; }

	elem.events = ctx.get_elem_events(elem);
	if (elem.events.mouse_hover) {
		if (parent.flags.has_focus) {
			elem.flags.has_focus = true;
			elem.button.color = uint_to_rgba(0x00ff00ff);
		}
	} else {
		elem.button.color = uint_to_rgba(0x0000ffff);
	}

	if (state) {
		elem.button.color = uint_to_rgba(0xff00ffff);
	}

	// Draw the button
	ctx.push_rect(elem.bounds, elem.button.color, do_border: true, do_radius: true)!;

	return elem.events;
}
