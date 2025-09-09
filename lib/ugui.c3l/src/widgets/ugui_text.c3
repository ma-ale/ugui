module ugui;

import std::io;

struct ElemText {
	usz cursor; // cursor offset
	Id hash;
	TextSize size;
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

	update_parent_grow(elem, parent);
	update_parent_size(elem, parent);

	ctx.layout_string(text, elem.bounds.pad(elem.layout.content_offset), TOP_LEFT, parent.div.z_index, style.fg)!;
}

/*
macro Ctx.text_box(&ctx, Rect size, char[] text, usz* text_len, ...)
	=> ctx.text_box_id(@compute_id($vasplat), size, text, text_len);
fn ElemEvents? Ctx.text_box_id(&ctx, Id id, Rect size, char[] text, usz* text_len)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_TEXT)!;
	Style* style = ctx.styles.get_style(@str_hash("text-box"));

	elem.text.str = (String)text;
	
	// layout the text box
	elem.bounds = ctx.layout_element(parent, size, style);

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
	Rect text_box = elem.bounds;
	ctx.push_rect(text_box, parent.div.z_index, style)!;
	ctx.push_string(text_box, text[:*text_len], parent.div.z_index, style.fg, true)!;
	
	// TODO: draw cursor

	return elem.events;
}
*/