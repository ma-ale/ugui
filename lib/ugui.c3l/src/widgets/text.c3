module ugui;

import std::io;

struct ElemText {
	Id hash;
	TextSize size;
	TextEdit* te;
}

/* Layout some text without bounds.
 * There is a limitation where the current frame bounds are based on the last frame, this is usually
 * not a problem but it is in the situation where the text changes almost all frames.
 */
macro Ctx.text(&ctx, String text, ...)
	=> ctx.text_id(@compute_id($vasplat), text);
fn void? Ctx.text_id(&ctx, Id id, String text)
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_TEXT)!.unpack(&elem, &parent);
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

	ctx.layout_string(text, elem.bounds.pad(elem.layout.content_offset), TOP_LEFT, parent.z_index, style.fg)!;
}


macro Ctx.text_box(&ctx, Size w, Size h, TextEdit* te, Anchor text_alignment = TOP_LEFT, bool reflow = true, ...)
	=> ctx.text_box_id(@compute_id($vasplat), w, h, te, text_alignment, reflow);
fn ElemEvents? Ctx.text_box_id(&ctx, Id id, Size w, Size h, TextEdit* te, Anchor text_alignment, bool reflow)
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_TEXT)!.unpack(&elem, &parent);
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
	//elem.events = ctx.get_elem_events(elem);

	if (elem.events.text_input || elem.events.key_press) {
		ctx.text_edit(elem.text.te);
	}

	Rect bg_bounds = elem.bounds.pad(style.margin);
	Rect text_bounds = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_rect(bg_bounds, parent.z_index, style)!;
	String s = elem.text.te.to_string();
	if (te.sel_len) {
		usz start = te.sel_len > 0 ? te.cursor : te.cursor + te.sel_len;
		usz end = (te.sel_len > 0 ? te.cursor + te.sel_len : te.cursor) - 1;
		ctx.draw_string_selection(s, text_bounds, text_alignment, start, end, parent.z_index, style.accent, reflow)!;
	}
	ctx.layout_string(s, text_bounds, text_alignment, parent.z_index, style.fg, reflow)!;

	// draw the cursor if the element has focus
	if (elem.events.has_focus) {
		if (elem.events.mouse_press || elem.events.mouse_hold) {
			usz cur = ctx.hit_test_string(s, text_bounds, text_alignment, ctx.input.mouse.pos, reflow)!;
			te.set_cursor(cur, elem.events.mouse_hold & !elem.events.mouse_press);
		}
		Rect cur = ctx.get_cursor_position(s, text_bounds, text_alignment, te.cursor, reflow)!;
		cur.w = 2;
		ctx.push_rect(cur, parent.z_index, &&(Style){.bg = style.fg})!;
	}
	return elem.events;
}