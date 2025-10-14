module ugui;

import std::collections::list;
import std::core::string;

struct LineInfo @local {
	usz start, end;
	short width, height;
	short first_off; // first character offset
}

alias LineStack @local = list::List{LineInfo};

fn short Rect.y_off(Rect bounds, short height, Anchor anchor) @local
{
	short off;

	switch (anchor) {
	case TOP_LEFT: nextcase;
	case TOP: nextcase;
	case TOP_RIGHT:
		off = 0;
	case LEFT: nextcase;
	case CENTER: nextcase;
	case RIGHT:
		off = (short)(bounds.h - height)/2;
	case BOTTOM_LEFT: nextcase;
	case BOTTOM: nextcase;
	case BOTTOM_RIGHT:
		off = (short)(bounds.h - height);
	}
	return off;
}

fn short Rect.x_off(Rect bounds, short width, Anchor anchor) @local
{
	short off;

	switch (anchor) {
	case TOP_LEFT: nextcase;
	case LEFT: nextcase;
	case BOTTOM_LEFT:
		off = 0;
	case TOP: nextcase;
	case CENTER: nextcase;
	case BOTTOM:
		off = (short)(bounds.w - width)/2;
	case TOP_RIGHT: nextcase;
	case RIGHT: nextcase;
	case BOTTOM_RIGHT:
		off = (short)(bounds.w - width);
	}
	
	return off;
}


// ---------------------------------------------------------------------------------- //
//                                STRING LAYOUT                                       //
// ---------------------------------------------------------------------------------- //


<*
@param[&in] ctx
@param[in] text
*>
fn void? Ctx.layout_string(&ctx, String text, Rect bounds, Anchor anchor, int z_index, Color hue, bool reflow = false)
{
	if (anchor == TOP_LEFT) {
		return ctx.layout_string_topleft(text, bounds, z_index, hue, reflow);
	} else {
		return ctx.layout_string_aligned(text, bounds, anchor, z_index, hue, reflow);
	}
}

// layout a string inside a bounding box, following the given alignment (anchor).
// TODO: Following improvements
//         [ ] implement a macro to fetch and layout each character, this can be used to reduce code
//             repetition both here and in measure_string
//         [ ] implement a function hit_test_string() to get the character position at point, this can
//             be used to implement mouse interactions, like cursor movement and selection
<*
@param [&in] ctx
@param [in] text
*>
fn void? Ctx.layout_string_aligned(&ctx, String text, Rect bounds, Anchor anchor, int z_index, Color hue, bool reflow = false)
{
	if (text == "") return;
	if (bounds.w <= 0 || bounds.h <= 0) return;
	ctx.push_scissor(bounds, z_index)!;

	Font* font = &ctx.font;
	Id texture_id = font.id;
	short line_height = (short)font.line_height();
	short baseline = (short)font.ascender;
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;

	Point origin = bounds.position();

	LineStack lines;
	lines.init(tmem, 1);

	Rect str_bounds;

	usz line_start;
	LineInfo li;
	Point o;
	StringIterator ti = text.iterator();
	for (Codepoint cp; ti.has_next();) {
		// FIXME: what if the interface changes?
		cp = ti.next()!;
		usz off = ti.current;
		Glyph* gp = font.get_glyph(cp)!;
		bool push = false;

		switch {
		case cp == '\n':
			push = true;
		case cp == '\t':
			o.x += tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			if (off == line_start) li.first_off = gp.ox;

			Rect b = {
				.x = o.x + gp.ox,
				.y = o.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};

			if (reflow && b.x + b.w > bounds.w) {
				li.width += gp.ox + gp.w;
				li.height = line_height;
				push = true;
			} else {
				o.x += gp.adv;
				li.width += gp.adv;
				li.height = line_height;
			}
		}
		
		if (push) {
			li.start = line_start;
			li.end = off;
			lines.push(li);
			str_bounds.w = max(str_bounds.w, li.width);
			str_bounds.h += li.height;

			o.x = 0;
			o.y += line_height;
			line_start = off;

			li.height = 0;
			li.width = 0;
		}
	}
	// FIXME: crap
	li.start = line_start;
	li.end = ti.current;
	lines.push(li);
	str_bounds.w = max(str_bounds.w, li.width);
	str_bounds.h += li.height;
	
	// account for the line gap
	str_bounds.h += (short)(lines.len() - 1)*line_gap;

	o = bounds.position();
	o.y += bounds.y_off(str_bounds.h, anchor);
	foreach (idx, line : lines) {
		o.x = bounds.x + bounds.x_off(line.width, anchor) - line.first_off;
		
		StringIterator s = text[line.start:line.end-line.start].iterator();
		for (Codepoint cp; s.has_next();) {
			cp = s.next()!;
			Glyph* gp = font.get_glyph(cp)!;

			switch {
			case cp == '\n':
				break;
			case cp == '\t':
				o.x += tab_width;
			case ascii::is_cntrl((char)cp):
				break;
			default:
				Rect b = {
					.x = o.x + gp.ox,
					.y = o.y + gp.oy + baseline,
					.w = gp.w,
					.h = gp.h,
				};
				Rect uv = {
					.x = gp.u,
					.y = gp.v,
					.w = gp.w,
					.h = gp.h
				};

				ctx.push_sprite(b, uv, texture_id, z_index, hue)!;
				o.x += gp.adv;
			}
		}
		o.y += line.height + line_gap;
	}

	ctx.reset_scissor(z_index)!;
//	ctx.dbg_rect(str_bounds.off(bounds.position()));
}

// layout a string inside a bounding box, with TOP_LEFT alignment.
<*
@param[&in] ctx
@param[in] text
*>
fn void? Ctx.layout_string_topleft(&ctx, String text, Rect bounds, int z_index, Color hue, bool reflow = false)
{
	if (text == "") return;
	if (bounds.w <= 0 || bounds.h <= 0) return;
	ctx.push_scissor(bounds, z_index)!;

	Font* font = &ctx.font;
	Id texture_id = font.id;
	short line_height = (short)font.line_height();
	short baseline = (short)font.ascender;
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;

	Point o = bounds.position();
	StringIterator it = text.iterator();
	for (Codepoint cp; it.has_next();) {
		cp = it.next()!;
		Glyph* gp = font.get_glyph(cp)!;

		switch {
		case cp == '\n':
			o.y += line_height;
			o.x = bounds.x;
			break;
		case cp == '\t':
			o.x += tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			Rect b = {
				.x = o.x + gp.ox,
				.y = o.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};
			Rect uv = {
				.x = gp.u,
				.y = gp.v,
				.w = gp.w,
				.h = gp.h
			};

			if (reflow && b.x + b.w > bounds.x + bounds.w) {
				o.y += line_height + line_gap;
				o.x = bounds.x;
				b.x = o.x + gp.ox;
				b.y = o.y + gp.oy + baseline;
			}

			ctx.push_sprite(b, uv, texture_id, z_index, hue)!;
			o.x += gp.adv;
		}
	}

	ctx.reset_scissor(z_index)!;
}


// ---------------------------------------------------------------------------------- //
//                              CURSOR AND MOUSE                                      //
// ---------------------------------------------------------------------------------- //


// TODO: get_cursor_position and hit_test_string can be implemented with a glyph_iterator that
//       returns the position and offset in the string of each glyph

fn Rect? Ctx.get_cursor_position(&ctx, String text, Rect bounds, Anchor anchor, usz cursor, bool reflow = false)
{
	if (anchor != TOP_LEFT) {
		unreachable("TODO: anchor has to be TOP_LEFT");
	}

	if (bounds.w <= 0 || bounds.h <= 0) return {};
	if (text == "") text = "\f";

	Font* font = &ctx.font;
	Id texture_id = font.id;
	short line_height = (short)font.line_height();
	short baseline = (short)font.ascender;
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;
	
	Rect cursor_rect;
	cursor_rect.x = bounds.x;
	cursor_rect.y = bounds.y;
	cursor_rect.h = line_height;
	
	if (cursor == 0) return cursor_rect;

	Point o = bounds.position();
	StringIterator it = text.iterator();
	usz off;
	for (Codepoint cp; it.has_next();) {
		cp = it.next()!;
		off = it.current;
		Glyph* gp = font.get_glyph(cp)!;

		switch {
		case cp == '\n':
			o.y += line_height;
			o.x = bounds.x;
			break;
		case cp == '\t':
			o.x += tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			Rect b = {
				.x = o.x + gp.ox,
				.y = o.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};

			if (reflow && b.x + b.w > bounds.x + bounds.w) {
				o.y += line_height + line_gap;
				o.x = bounds.x;
				b.x = o.x + gp.ox;
				b.y = o.y + gp.oy + baseline;
			}

			o.x += gp.adv;
		}
		if (off == cursor) {
			cursor_rect.x = o.x;
			cursor_rect.y = o.y;
			return cursor_rect;
		}
	}
	return {};
}

<*
@param [&in] ctx
@param [in] text
*>
fn usz? Ctx.hit_test_string(&ctx, String text, Rect bounds, Anchor anchor, Point p, bool reflow = false)
{
	if (text == "") return 0;
	if (bounds.w <= 0 || bounds.h <= 0) return 0;

	Font* font = &ctx.font;
	Id texture_id = font.id;
	short line_height = (short)font.line_height();
	short baseline = (short)font.ascender;
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;

	Point origin = bounds.position();

	LineStack lines;
	lines.init(tmem, 1);

	Rect str_bounds;

	usz line_start;
	LineInfo li;
	Point o;
	StringIterator ti = text.iterator();
	for (Codepoint cp; ti.has_next();) {
		// FIXME: what if the interface changes?
		cp = ti.next()!;
		usz off = ti.current;
		Glyph* gp = font.get_glyph(cp)!;
		bool push = false;

		switch {
		case cp == '\n':
			push = true;
		case cp == '\t':
			o.x += tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			if (off == line_start) li.first_off = gp.ox;

			Rect b = {
				.x = o.x + gp.ox,
				.y = o.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};

			if (reflow && b.x + b.w > bounds.w) {
				li.width += gp.ox + gp.w;
				li.height = line_height;
				push = true;
			} else {
				o.x += gp.adv;
				li.width += gp.adv;
				li.height = line_height;
			}
		}
		
		if (push) {
			li.start = line_start;
			li.end = off;
			lines.push(li);
			str_bounds.w = max(str_bounds.w, li.width);
			str_bounds.h += li.height;

			o.x = 0;
			o.y += line_height;
			line_start = off;

			li.height = 0;
			li.width = 0;
		}
	}
	// FIXME: crap
	li.start = line_start;
	li.end = ti.current;
	lines.push(li);
	str_bounds.w = max(str_bounds.w, li.width);
	str_bounds.h += li.height;
	
	// account for the line gap
	str_bounds.h += (short)(lines.len() - 1)*line_gap;

	o = bounds.position();
	o.y += bounds.y_off(str_bounds.h, anchor);
	foreach (idx, line : lines) {
		o.x = bounds.x + bounds.x_off(line.width, anchor) - line.first_off;
		
		StringIterator s = text[line.start:line.end-line.start].iterator();
		usz prev;
		for (Codepoint cp; s.has_next(); prev = s.current) {
			cp = s.next()!;
			Glyph* gp = font.get_glyph(cp)!;

			switch {
			case cp == '\n':
				break;
			case cp == '\t':
				o.x += tab_width;
			case ascii::is_cntrl((char)cp):
				break;
			default:
				Rect b = {
					.x = o.x + gp.ox,
					.y = o.y + gp.oy + baseline,
					.w = gp.w,
					.h = gp.h,
				};
				
				// TODO: skip lines if p is not inside them
				Rect r = { .x = b.x, .y = b.y - gp.ox, .w = b.w, .h = line.height};
				if (p.in_rect(r)) return line.start + prev;
				
				o.x += gp.adv;
			}
		}
		o.y += line.height + line_gap;
	}
	return text.len;
}


// ---------------------------------------------------------------------------------- //
//                              TEXT MEASUREMENT                                      //
// ---------------------------------------------------------------------------------- //


const uint TAB_SIZE = 4;

struct TextSize {
	Size width, height;
	int area;
}

// Measeure the size of a string.
// width.min: as if each word is broken up by a new line
// width.max: the width of the string left as-is
// height.min: the height of the string left as-is
// height.max: the height of the string with each word broken up by a new line
<*
@param [&in] ctx
@param [in] text
*>
fn TextSize? Ctx.measure_string(&ctx, String text)
{
	if (text == "") return (TextSize){};

	Font* font = &ctx.font;
	short baseline = (short)font.ascender;
	short line_height = (short)font.line_height();
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;

	isz off;
	usz x;

	TextSize ts;

	short word_width;
	short words = 1;
	Rect bounds; // unaltered text bounds;
	Point origin;

	StringIterator it = text.iterator();
	for (Codepoint cp; it.has_next();) {
		cp = it.next()!;
		Glyph* gp = font.get_glyph(cp)!;

		// update the text bounds
		switch {
		case cp == '\n':
			origin.x = 0;
			origin.y += line_height + line_gap;
		case cp == '\t':
			origin.x += tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			Rect b = {
				.x = origin.x + gp.ox,
				.y = origin.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};
			bounds = containing_rect(bounds, b);
			origin.x += gp.adv;
		}

		// update the word width
		switch {
		case ascii::is_space((char)cp):
			if (word_width > ts.width.min) ts.width.min = word_width;
			word_width = 0;
			words++;
		default:
			//word_width += gp.w + gp.ox;
			if (off < text.len) {
				word_width += gp.adv;
			} else {
				word_width += gp.w + gp.ox;
			}
		}
	}
	// end of string is also end of word
	if (word_width > ts.width.min) ts.width.min = word_width;

	ts.width.max = bounds.w;
	ts.height.min = bounds.h;
	ts.height.max = words * line_height + line_gap * (words-1);
	ts.area = bounds.w * bounds.h;

	return ts;
}


