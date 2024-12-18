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
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	if (c_elem.flags.is_new) {
		c_elem.type = ETYPE_BUTTON;
		c_elem.button.color = uint_to_rgba(0x0000ffff);
	} else if (c_elem.type != ETYPE_BUTTON) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}

	c_elem.bounds = ctx.position_element(parent, size, true);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (c_elem.bounds.is_null()) { return ElemEvents{}; }

	c_elem.events = ctx.get_elem_events(c_elem);
	if (c_elem.events.mouse_hover) {
		if (parent.flags.has_focus) {
			c_elem.flags.has_focus = true;
			c_elem.button.color = uint_to_rgba(0x00ff00ff);
		}
	} else {
		c_elem.button.color = uint_to_rgba(0x0000ffff);
	}

	if (state) {
		c_elem.button.color = uint_to_rgba(0xff00ffff);
	}

	// Draw the button
	ctx.push_rect(c_elem.bounds, c_elem.button.color, do_border: true, do_radius: true)!;

	return c_elem.events;
}
