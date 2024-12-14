module ugui;

import std::io;
import std::ascii;
import grapheme;

<*
@require off != null
*>
fn Codepoint str_to_codepoint(char[] str, usz* off)
{
	Codepoint cp;
	isz b = grapheme::decode_utf8(str, str.len, &cp);
	if (b == 0 || b > str.len) {
		return 0;
	}
	*off = b;
	return cp;
}

fn Rect! Ctx.get_text_bounds(&ctx, String text, bool* update_atlas)
{
	Rect text_bounds;
	short line_height = (short)ctx.font.ascender - (short)ctx.font.descender;
	short line_gap = (short)ctx.font.linegap;
	text_bounds.h = line_height;
	Glyph* gp;

	// TODO: account for unicode codepoints
	short line_len;
	Codepoint cp;
	usz off, x;
	while ((cp = str_to_codepoint(text[off..], &x)) != 0) {
		off += x;
		bool n;
		if (!ascii::is_cntrl((char)cp)) {
			gp = ctx.font.get_glyph(cp, &n)!;
			line_len += gp.adv;
			if (n) { *update_atlas = true; }
		} else if (cp == '\n'){
			text_bounds.h += line_height + line_gap;
			line_len = 0;
		} else {
			continue;
		}
		if (line_len > text_bounds.w) {
			text_bounds.w = line_len;
		}
	}

	return text_bounds;
}

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
	bool update_atlas;
	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		Rect text_size = ctx.get_text_bounds(text, &update_atlas)!;

		// 2. Layout
		c_elem.bounds = ctx.position_element(parent, text_size, true);

		// 3. Fill the button specific fields
		c_elem.text.str = text;
	}

	if (update_atlas) {
		// FIXME: atlas here is hardcoded, look at the todo in ugui_data
		Cmd up = {
			.type = CMD_UPDATE_ATLAS,
			.update_atlas = {
				.raw_buffer = ctx.font.atlas[0].buffer,
				.width = ctx.font.atlas[0].width,
				.height = ctx.font.atlas[0].height,
			},
		};
		ctx.cmd_queue.enqueue(&up)!;
	}

	Cmd bounds = {
		.type = CMD_RECT,
		.rect.rect = c_elem.bounds,
		.rect.color = uint_to_rgba(0x000000ff),
	};
	ctx.cmd_queue.enqueue(&bounds)!;

	ctx.push_string(c_elem.bounds, text)!;
}
