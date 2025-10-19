module ugui;

import std::collections::list;
import std::core::string;

struct LineInfo @local {
	usz start, end;
	short width, height;
	short first_off; // first character offset
}

macro usz LineInfo.len(li) => li.end-li.start;

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


struct GlyphIterator {
	short baseline;
	short line_height;
	short line_gap;
	short space_width;
	short tab_width;
	Rect bounds;
	Anchor anchor;
	bool reflow;
	Font* font;

	LineStack lines;
	usz line_off, line_idx;
	String text;

	Codepoint cp;
	Glyph* gp;
	short adv; // prev advance
	Point o;
	Rect str_bounds;
}

<*
@param [&inout] self
@param [in] text
@param [&inout] font
*>
fn void? GlyphIterator.init(&self, Allocator allocator, String text, Rect bounds, Font* font, Anchor anchor, bool reflow, uint tab_size)
{
	self.font = font;

	self.line_height = (short)font.line_height();
	self.baseline = (short)font.ascender;
	self.line_gap = (short)font.linegap;
	self.space_width = font.get_glyph(' ').adv!;
	self.tab_width = self.space_width * (short)tab_size;

	self.bounds = bounds;
	self.o = bounds.position();
	self.reflow = reflow;
	self.text = text;
	self.anchor = anchor;

	// if the anchor is top_left we can skip dividing the string line by line, in GlyphIterator.next
	// this has to be accounted for
	if (anchor != TOP_LEFT) {
		self.lines.init(allocator, 4);
		self.populate_lines_stack()!;
		self.line_off = 0;
		self.line_idx = 0;
	
		if (self.lines.len() > 0) {
			self.o.y += bounds.y_off(self.str_bounds.h, anchor);
			self.o.x += bounds.x_off(self.lines[0].width, anchor) - self.lines[0].first_off;
		}
	}
}


fn void? GlyphIterator.populate_lines_stack(&self)
{
	usz line_start;
	LineInfo li;
	Point o = self.o;
	StringIterator ti = self.text.iterator();

	usz prev_off;
	for (Codepoint cp; ti.has_next();) {
		cp = ti.next()!;
		usz off = ti.current;
		bool push = false;

		li.height = self.line_height;
		switch {
		case cp == '\n':
			push = true;
		case cp == '\t':
			o.x += self.tab_width;
		case ascii::is_cntrl((char)cp):
			break;
		default:
			Glyph* gp = self.font.get_glyph(cp)!;

			if (off == line_start) {
				li.first_off = gp.ox;
				o.x -= gp.ox;
			}

			Rect b = gp.bounds().off(o);
			b.y += self.baseline;
			
			if (self.reflow && b.x + b.w > self.bounds.x + self.bounds.w) {
				push = true;
				// roll back this character since it is on the next line
				ti.current = prev_off;
				off = prev_off;
			} else {
				o.x += gp.adv;
				li.width += gp.adv;
			}
		}
		
		if (push) {
			li.start = line_start;
			li.end = off;
			self.lines.push(li);
			self.str_bounds.w = max(self.str_bounds.w, li.width);
			self.str_bounds.h += li.height;

			o.x = self.bounds.x;
			o.y += self.line_height;
			line_start = off;

			li.height = 0;
			li.width = 0;
		}
		
		prev_off = off;
	}
	if (line_start != ti.current) {
		// FIXME: crap, can we not repeat this code?
		li.start = line_start;
		li.end = ti.current;
		self.lines.push(li);
		self.str_bounds.w = max(self.str_bounds.w, li.width);
		self.str_bounds.h += li.height;
	}
	
	self.str_bounds.h += (short)(self.lines.len()-1) * self.line_gap;
}

fn String GlyphIterator.current_line(&self)
{
	LineInfo li = self.lines[self.line_idx];
	return self.text[li.start:li.len()];
}


fn Rect? GlyphIterator.next(&self)
{
	// check if there is a next glyph and maybe update the line and offset indices
	if (self.anchor != TOP_LEFT) {
		if (self.line_idx >= self.lines.len()) {
			return NO_MORE_ELEMENT?;
		}
	
		LineInfo li = self.lines[self.line_idx];
		if (self.line_off >= li.len()) {
			self.line_idx++;
			
			if (self.line_idx >= self.lines.len()) {
				return NO_MORE_ELEMENT?;
			}
			
			self.line_off = 0;
			li = self.lines[self.line_idx];
	
			self.o.y += self.line_height + self.line_gap;
			self.o.x = self.bounds.x + self.bounds.x_off(li.width, self.anchor) - li.first_off;
		}
	} else if (self.line_off >= self.text.len) {
		return NO_MORE_ELEMENT?;
	}

	String t;
	if (self.anchor != TOP_LEFT) {
		t = self.current_line()[self.line_off..];
	} else {
		t = self.text[self.line_off..];
	}
	
	usz read = t.len < 4 ? t.len : 4;
	self.cp = conv::utf8_to_char32(&t[0], &read)!;
	self.line_off += read;
	self.gp = self.font.get_glyph(self.cp)!;
	
	Rect b = {.x = self.o.x, .y = self.o.y};

	Point prev_o = self.o;
	self.adv = 0;
	switch {
	case self.cp == '\n':
		if (self.anchor == TOP_LEFT) {
			self.o.x = self.bounds.x;
			self.o.y += self.line_height + self.line_gap;
			self.line_idx++;
		}
		break;
	case self.cp == '\t':
		self.o.x += self.tab_width;
	case ascii::is_cntrl((char)self.cp):
		break;
	default:
		b = self.gp.bounds().off(self.o);
		b.y += self.baseline;
		if (self.anchor == TOP_LEFT) {
			//if (self.o.x == self.bounds.x) self.bounds.x -= self.gp.ox;
			if (self.reflow && b.bottom_right().x > self.bounds.bottom_right().x) {
				self.o.x = self.bounds.x - self.gp.ox;
				self.o.y += self.line_height + self.line_gap;
				self.line_idx++;
				b = self.gp.bounds().off(self.o);
				b.y += self.baseline;
			}
		}
		self.o.x += self.gp.adv;
		self.adv = self.o.x - prev_o.x;
	}

	return b;
}

fn bool GlyphIterator.has_next(&self)
{
	if (self.anchor == TOP_LEFT) {
		return self.line_off < self.text.len;
	}

	if (self.line_idx >= self.lines.len()) {
		return false;
	}
	
	LineInfo li = self.lines[self.line_idx];
	if (self.line_idx == self.lines.len() - 1 && self.line_off >= li.len()) {
		return false;
	}

	return true;
}

fn usz GlyphIterator.current_offset(&self)
{
	if (self.anchor == TOP_LEFT) return self.line_off;
	return self.lines[self.line_idx].start + self.line_off;
}


// layout a string inside a bounding box, following the given alignment (anchor).
<*
@param [&in] ctx
@param [in] text
*>
fn void? Ctx.layout_string(&ctx, String text, Rect bounds, Anchor anchor, int z_index, Color hue, bool reflow = false)
{
	if (text == "") return;
	if (bounds.w <= 0 || bounds.h <= 0) return;
	ctx.push_scissor(bounds, z_index)!;

	Font* font = &ctx.font;
	Id texture_id = font.id;
	
	GlyphIterator gi;
	gi.init(tmem, text, bounds, font, anchor, reflow, TAB_SIZE)!;
	while (gi.has_next()) {
		Rect b = gi.next()!;
		Rect uv = gi.gp.uv();
		ctx.push_sprite(b, uv, texture_id, z_index, hue)!;
	}

	ctx.reset_scissor(z_index)!;
//	ctx.dbg_rect(str_bounds.off(bounds.position()));
}


// ---------------------------------------------------------------------------------- //
//                              CURSOR AND MOUSE                                      //
// ---------------------------------------------------------------------------------- //


fn Rect? Ctx.get_cursor_position(&ctx, String text, Rect bounds, Anchor anchor, usz cursor, bool reflow = false)
{
	if (bounds.w <= 0 || bounds.h <= 0) return {};

	Font* font = &ctx.font;
	Id texture_id = font.id;
	
	if (text == "") text = "\f";

	GlyphIterator gi;
	gi.init(tmem, text, bounds, font, anchor, reflow, TAB_SIZE)!;
	Rect cursor_rect;
	cursor_rect.x = gi.o.x;
	cursor_rect.y = gi.o.y;
	cursor_rect.h = (short)font.line_height();
	if (cursor == 0) return cursor_rect;

	while (gi.has_next()) {
		Rect b = gi.next()!;
		if (gi.current_offset() == cursor) {
			if (gi.cp == '\n') {
				if (!gi.has_next()) {
					cursor_rect.x = bounds.x + bounds.x_off(0, anchor);
					cursor_rect.y = b.y + gi.line_height + gi.line_gap;
				} else {
					gi.next()!;
					cursor_rect.x = gi.o.x - gi.gp.adv;
					cursor_rect.y = gi.o.y;
				}
			} else {
				// Use the updated origin position instead of glyph bounds
				cursor_rect.x = gi.o.x;
				cursor_rect.y = gi.o.y;
			}
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
	
	GlyphIterator gi;
	gi.init(tmem, text, bounds, font, anchor, reflow, TAB_SIZE)!;
	
	usz prev_offset = 0;
	Point prev_o = gi.o;
	
	while (gi.has_next()) {
		Point o_before = gi.o;
		usz offset_before = gi.current_offset();
		Rect b = gi.next()!;
		
		switch {
		case gi.cp == '\n':
			// Check if point is on this line before the newline
			Rect line_rect = {
				.x = prev_o.x,
				.y = prev_o.y,
				.w = (short)(o_before.x - prev_o.x),
				.h = gi.line_height
			};
			if (p.in_rect(line_rect)) return offset_before;
			prev_o = gi.o;
			break;
		case gi.cp == '\t':
			// Check if point is in the tab space
			Rect tab_rect = {
				.x = o_before.x,
				.y = o_before.y,
				.w = gi.tab_width,
				.h = gi.line_height
			};
			if (p.in_rect(tab_rect)) return offset_before;
			break;
		case ascii::is_cntrl((char)gi.cp):
			break;
		default:
			// Create a hit test rect for this character
			Rect hit_rect = {
				.x = o_before.x,
				.y = o_before.y,
				.w = gi.gp.adv,
				.h = gi.line_height
			};

			if (p.in_rect(hit_rect)) {
				// Check if cursor should be before or after this character
				// by checking which half of the character was clicked
				short mid_x = o_before.x + gi.gp.adv / 2;
				if (p.x < mid_x) {
					return offset_before;
				} else {
					return gi.current_offset();
				}
			}
		}
		
		prev_offset = gi.current_offset();
	}
	
	// Point is after all text
	return text.len;
}

// TODO: implement a function `layout_string_with_selection` to avoid iterating over the string twice
fn void? Ctx.draw_string_selection(&ctx, String text, Rect bounds, Anchor anchor, usz start, usz end, int z_index, Color hue, bool reflow = false)
{
	if (text == "") return;
	if (bounds.w <= 0 || bounds.h <= 0) return;

	if (start > end) @swap(start, end);

	// Ensure start < end
	if (start > end) {
		usz temp = start;
		start = end;
		end = temp;
	}
	
	ctx.push_scissor(bounds, z_index)!;

	Font* font = &ctx.font;
	
	GlyphIterator gi;
	gi.init(tmem, text, bounds, font, anchor, reflow, TAB_SIZE)!;

	Rect sel_rect = { .h = gi.line_height }; // selection rect
	isz sel_line = -1; // selection line
	while (gi.has_next()) {
		Rect b = gi.next()!;
		usz off = gi.current_offset()-1;
		isz line = gi.line_idx;
		bool in_selection = start <= off && off <= end;

		if  (in_selection && line != sel_line) {
			if (sel_line != -1) {
				ctx.push_rect(sel_rect, z_index, &&{.bg = hue})!;
			}
			sel_rect = {.x = gi.o.x - gi.adv, .y = gi.o.y, .w = 0, .h = gi.line_height};
			sel_line = line;
		}
		if (in_selection) {
			sel_rect.w = gi.o.x - sel_rect.x;
			if (gi.cp == '\n') sel_rect.w += gi.space_width;
		}
		
		if (off > end) break;
	}
	ctx.push_rect(sel_rect, z_index, &&{.bg = hue})!;
	
	ctx.reset_scissor(z_index)!;
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
			Rect b = gp.bounds().off(origin);
			b.y += baseline;
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


