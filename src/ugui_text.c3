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

fn Rect! Ctx.get_text_bounds(&ctx, String text)
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
			gp = ctx.font.get_glyph(cp)!;
			line_len += gp.adv;
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
