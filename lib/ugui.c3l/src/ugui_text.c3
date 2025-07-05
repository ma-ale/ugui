module ugui;

import std::io;

struct ElemText {
	char[] str;
	usz cursor; // cursor offset
}

macro Ctx.text_unbounded(&ctx, String text, ...)
	=> ctx.text_unbounded_id(@compute_id($vasplat), text);
fn void? Ctx.text_unbounded_id(&ctx, Id id, String text)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_TEXT)!;
	Style* style = ctx.styles.get_style(0);

	elem.text.str = text;

	// if the element is new or the parent was updated then redo layout
	Rect text_size = ctx.get_text_bounds(text)!;
	// 2. Layout
	elem.bounds = ctx.position_element(parent, text_size, style);
	if (elem.bounds.is_null()) { return; }

	ctx.push_string(elem.bounds, text, parent.div.z_index, style.fg)!;
}

macro Ctx.text_box(&ctx, Rect size, char[] text, usz* text_len, ...)
	=> ctx.text_box_id(@compute_id($vasplat), size, text, text_len);
fn ElemEvents? Ctx.text_box_id(&ctx, Id id, Rect size, char[] text, usz* text_len)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_TEXT)!;
	Style* style = ctx.styles.get_style(0);

	elem.text.str = text;
	
	// layout the text box
	elem.bounds = ctx.position_element(parent, size, style);

	// check input and update the text
	elem.events = ctx.get_elem_events(elem);
	
	if (elem.events.text_input) {
		usz l = ctx.input.keyboard.text_len;
		char[] t = ctx.input.keyboard.text[..l];
				
		if (l != 0 && l < text.len - *text_len) {
			text[*text_len..*text_len+l] = t[..];
			*text_len += l;
		}
		
		if (ctx.input.keyboard.modkeys.bkspc) {
			*text_len = *text_len > 0 ? *text_len-1 : 0;
		}
		
	}
	elem.text.cursor = *text_len;

	// draw the box
	short line_height = (short)ctx.font.line_height();
	Rect text_box = elem.bounds.sub({0,0,0,line_height});
	Rect input_box = {
		.x = elem.bounds.x,
		.y = elem.bounds.y + elem.bounds.h - line_height,
		.w = elem.bounds.w,
		.h = line_height,
	};
	Rect cursor;
	Point b = ctx.get_cursor_position((String)text[:elem.text.cursor])!;
	cursor = {
		.x = b.x,
		.y = b.y,
		.w = 3,
		.h = line_height,
	};
	cursor = cursor.off(elem.bounds.position());

	ctx.push_rect(text_box, parent.div.z_index, style)!;
	ctx.push_string(text_box, text[:*text_len], parent.div.z_index, style.fg)!;
	ctx.push_rect(input_box, parent.div.z_index, style)!;
	ctx.push_rect(cursor, parent.div.z_index, style)!;

	return elem.events;
}
