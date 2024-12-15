module ugui;

import std::io;

fn void! Ctx.text_unbounded(&ctx, String label, String text)
{
	Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	// this resets the flags
	c_elem.type = ETYPE_TEXT;

	short baseline = (short)ctx.font.ascender;
	short line_height = (short)ctx.font.ascender - (short)ctx.font.descender;
	short line_gap = (short)ctx.font.linegap;
	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		Rect text_size = ctx.get_text_bounds(text)!;

		// 2. Layout
		c_elem.bounds = ctx.position_element(parent, text_size, true);

		// 3. Fill the button specific fields
		c_elem.text.str = text;
	}

	ctx.push_string(c_elem.bounds, text)!;
}
