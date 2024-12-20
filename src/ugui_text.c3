module ugui;

import std::io;

struct ElemText {
	char* str;
}

fn void! Ctx.text_unbounded(&ctx, String label, String text)
{
	Id id = ctx.gen_id(label)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	// this resets the flags
	elem.type = ETYPE_TEXT;
	elem.text.str = text;

	// if the element is new or the parent was updated then redo layout
	Rect text_size = ctx.get_text_bounds(text)!;
	// 2. Layout
	elem.bounds = ctx.position_element(parent, text_size, true);
	if (elem.bounds.is_null()) { return; }

	ctx.push_string(elem.bounds, text)!;
}
