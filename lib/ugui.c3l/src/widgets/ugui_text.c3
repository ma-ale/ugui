module ugui;

import std::io;

struct ElemText {
	Id hash;
	TextSize size;
	TextEdit* te;
}

macro Ctx.text(&ctx, String text, ...)
	=> ctx.text_id(@compute_id($vasplat), text);
fn void? Ctx.text_id(&ctx, Id id, String text)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_TEXT)!;
	Style* style = ctx.styles.get_style(@str_hash("text"));

	Id text_hash = text.hash();
	if (elem.flags.is_new || elem.text.hash != text_hash) {
		elem.text.size = ctx.measure_string(text)!;
	}
	elem.text.hash = text_hash;

	elem.layout.w = @fit(style.size);
	elem.layout.h = @fit(style.size);
	elem.layout.text = elem.text.size;
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	ctx.layout_string(text, elem.bounds.pad(elem.layout.content_offset), TOP_LEFT, parent.div.z_index, style.fg)!;
}


macro Ctx.text_box(&ctx, Size w, Size h, TextEdit* te, ...)
	=> ctx.text_box_id(@compute_id($vasplat), w, h, te);
fn ElemEvents? Ctx.text_box_id(&ctx, Id id, Size w, Size h, TextEdit* te)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_TEXT)!;
	Style* style = ctx.styles.get_style(@str_hash("text-box"));

	elem.text.te = te;

	Id text_hash = te.to_string().hash();
	if (elem.flags.is_new || elem.text.hash != text_hash) {
		elem.text.size = ctx.measure_string(te.to_string())!;
	}
	elem.text.hash = text_hash;

	elem.layout.w = w;
	elem.layout.h = h;
	elem.layout.text = elem.text.size;
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	// check input and update the text
	elem.events = ctx.get_elem_events(elem);

	if (elem.events.text_input || elem.events.key_press) {
		ctx.text_edit(elem.text.te);
	}

	// draw the box

	Rect bg_bounds = elem.bounds.pad(style.margin);
	Rect text_bounds = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_rect(bg_bounds, parent.div.z_index, style)!;
	Rect cur;
	cur = ctx.layout_string(elem.text.te.to_string(), text_bounds, TOP_LEFT, parent.div.z_index, style.fg, elem.text.te.cursor)!;

	// draw the cursor if the element has focus
	if (elem.events.has_focus) {
		cur.w = 2;
		// FIXME: gross hack for when text is empty
		if (cur.x == 0 && cur.y == 0) {
			cur.x = text_bounds.x;
			cur.y = text_bounds.y;
		}
		ctx.push_rect(cur, parent.div.z_index, &&(Style){.bg = style.fg})!;
	}
	return elem.events;
}