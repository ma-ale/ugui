module ugui;

import schrift;
import grapheme;
import std::collections::map;
import std::core::mem;
import std::core::mem::allocator;
import std::io;
import std::ascii;


// ---------------------------------------------------------------------------------- //
//                                CODEPOINT                                           //
// ---------------------------------------------------------------------------------- //

// unicode code point, different type for a different hash
alias Codepoint = uint;

<*
@require off != null
@require str.ptr != null
*>
fn Codepoint str_to_codepoint(char[] str, usz* off)
{
	Codepoint cp;
	isz b = grapheme::decode_utf8(str, str.len, (uint*)&cp);
	if (b == 0 || b > str.len) {
		return 0;
	}
	*off = b;
	return cp;
}

//macro uint Codepoint.hash(self) => ((uint)self).hash();

// ---------------------------------------------------------------------------------- //
//                                FONT ATLAS                                          //
// ---------------------------------------------------------------------------------- //

/* width and height of a glyph contain the kering advance
 * (u,v)
 *   +-------------*---+ -
 *   |       ^     |   | ^
 *   |       |oy   |   | |
 *   |       v     |   | |
 *   |      .ii.   |   | |
 *   |     @@@@@@. |   | |
 *   |    V@Mio@@o |   | |
 *   |    :i.  V@V |   | h
 *   |      :oM@@M |   | |
 *   |    :@@@MM@M |   | |
 *   |    @@o  o@M |   | |
 *   |<->:@@.  M@M |   | |
 *   |ox  @@@o@@@@ |   | |
 *   |    :M@@V:@@.|   | v
 *   +-------------*---+ -
 *   |<---- w ---->|
 *   |<------ adv ---->|
 */
struct Glyph {
	Codepoint code;
	ushort u, v;
	ushort w, h;
	short adv, ox, oy;
}

const uint FONT_CACHED = 255;
alias GlyphTable = map::HashMap{Codepoint, Glyph};

faultdef TTF_LOAD_FAILED, MISSING_GLYPH, BAD_GLYPH_METRICS, RENDER_ERROR;

struct Font {
	schrift::Sft sft;
	String path;
	Id id; // font id, same as atlas id
	GlyphTable table;

	float size;
	float ascender, descender, linegap; // Line Metrics
	Atlas atlas;
	bool should_update; // should send update_atlas command, resets at frame_end()
}

fn void? Font.load(&font, String name, ZString path, uint height, float scale)
{
	font.table.init(allocator::mem, capacity: FONT_CACHED);
	font.id = name.hash();

	font.size = height*scale;

	font.sft = {
		.xScale = (double)font.size,
		.yScale = (double)font.size,
		.flags = schrift::SFT_DOWNWARD_Y,
	};

	font.sft.font = schrift::loadfile(path);
	if (font.sft.font == null) {
		font.table.free();
		return TTF_LOAD_FAILED?;
	}

	schrift::SftLMetrics lmetrics;
	schrift::lmetrics(&font.sft, &lmetrics);
	font.ascender  = (float)lmetrics.ascender;
	font.descender = (float)lmetrics.descender;
	font.linegap   = (float)lmetrics.lineGap;
	//io::printfn("ascender:%d, descender:%d, linegap:%d", font.ascender, font.descender, font.linegap);

	// TODO: allocate buffer based on FONT_CACHED and the size of a sample letter
	//       like the letter 'A'
	ushort size = (ushort)font.size*(ushort)($$sqrt((float)FONT_CACHED));
	font.atlas.new(font.id, ATLAS_GRAYSCALE, size, size)!;

// FIXME: this crashes with O1 or greater, why??
	// preallocate the ASCII range
	for (char c = ' '; c < '~'; c++) {
		font.get_glyph((Codepoint)c)!;
	}
}

fn Glyph*? Font.get_glyph(&font, Codepoint code)
{
	Glyph*? gp;
	gp = font.table.get_ref(code);

	if (catch excuse = gp) {
		if (excuse != NOT_FOUND) {
			return excuse?;
		}
	} else {
		return gp;
	}

	// missing glyph, render and place into an atlas
	Glyph glyph;

	schrift::SftGlyph gid;
	schrift::SftGMetrics gmtx;

	if (schrift::lookup(&font.sft, (SftUChar)code, &gid) < 0) {
		return MISSING_GLYPH?;
	}

	if (schrift::gmetrics(&font.sft, gid, &gmtx) < 0) {
		return BAD_GLYPH_METRICS?;
	}

	schrift::SftImage img = {
		.width = gmtx.minWidth,
		.height = gmtx.minHeight,
	};
	char[] pixels = mem::new_array(char, (usz)img.width * img.height);
	img.pixels = pixels;
	if (schrift::render(&font.sft, gid, img) < 0) {
		return RENDER_ERROR?;
	}

	glyph.code = code;
	glyph.w = (ushort)img.width;
	glyph.h = (ushort)img.height;
	glyph.ox = (short)gmtx.leftSideBearing;
	glyph.oy = (short)gmtx.yOffset;
	glyph.adv = (short)gmtx.advanceWidth;
	//io::printfn("code=%c, w=%d, h=%d, ox=%d, oy=%d, adv=%d",
	//    glyph.code, glyph.w, glyph.h, glyph.ox, glyph.oy, glyph.adv);

	Point uv = font.atlas.place(pixels, glyph.w, glyph.h, (ushort)img.width)!;
	glyph.u = uv.x;
	glyph.v = uv.y;

	mem::free(pixels);

	font.table.set(code, glyph);

	font.should_update = true;
	return font.table.get_ref(code);
}

fn void Font.free(&font)
{
	font.atlas.free();
	font.table.free();
	schrift::freefont(font.sft.font);
}


// ---------------------------------------------------------------------------------- //
//                           FONT LOAD AND QUERY                                      //
// ---------------------------------------------------------------------------------- //

fn void? Ctx.load_font(&ctx, String name, ZString path, uint height, float scale = 1.0)
{
	return ctx.font.load(name, path, height, scale);
}

// TODO: check if the font is present in the context
fn Id Ctx.get_font_id(&ctx, String label)
{
	return (Id)label.hash();
}

fn Atlas*? Ctx.get_font_atlas(&ctx, String name)
{
	// TODO: use the font name, for now there is only one font
	if (name.hash() != ctx.font.id) {
		return WRONG_ID?;
	}

	return &ctx.font.atlas;
}

fn int Font.line_height(&font) => (int)(font.ascender - font.descender + (float)0.5);

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

	Codepoint cp = str_to_codepoint(text[off..], &x);
	for (; cp != 0; cp = str_to_codepoint(text[off..], &x)) {
		off += x;
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

// layout a string inside a bounding box, following the given alignment (anchor).
// returns the position of the cursor, the returned height is the line height and the width is the last
// character's advance value
// TODO: implement a "reflow" flag to toggle reflow if a character goes out of bounds
// TODO: also return the total bounds of the laid out string
fn Rect? Ctx.layout_string(&ctx, String text, Rect bounds, Anchor anchor, int z_index, Color hue, isz cursor = -1)
{
	Font* font = &ctx.font;
	short line_height = (short)font.line_height();
	Rect cursor_rect = {.h = line_height};

	if (bounds.w <= 0 || bounds.h <= 0) return cursor_rect;
	ctx.push_scissor(bounds, z_index)!;

	if (text == "") {
		// when text is empty but we need to draw a cursor use a visually empty string
		if (cursor >= 0) {
			text = "\f";
		} else {
			return cursor_rect;
		}
	}

	Id texture_id = font.id;
	short baseline = (short)font.ascender;
	short line_gap = (short)font.linegap;
	short space_width = font.get_glyph(' ').adv!;
	short tab_width = space_width * TAB_SIZE;

	Point origin = bounds.position();

	// measure string height inside the bounds to center it vertically
	// FIXME: this is fast but it just gives back the height in LINES, most lines have only short
	//        characters which would result in a lower height
	int string_height = line_height;
	foreach (c: text) {
		string_height += (line_height + line_gap) * (int)(c == '\n');
	}

	switch (anchor) {
	case TOP_LEFT: nextcase;
	case TOP: nextcase;
	case TOP_RIGHT:
		origin.y += 0;
	case LEFT: nextcase;
	case CENTER: nextcase;
	case RIGHT:
		origin.y += (short)(bounds.h - string_height)/2;
	case BOTTOM_LEFT: nextcase;
	case BOTTOM: nextcase;
	case BOTTOM_RIGHT:
		origin.y += (short)(bounds.h - string_height);
	}

	// measure the line until it exits the bounds or the string ends
	usz line_start, line_end;
	do {
		int line_width;
		Point o = {.x = bounds.x, .y = bounds.y};

		Codepoint cp;
		isz off = line_start;
		for ITER: (usz x; (cp = str_to_codepoint(text[off..], &x)) != 0; off += x) {
			Glyph* gp = font.get_glyph(cp)!;

			switch {
			case cp == '\n':
				off += x;
				break ITER;
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

				if (b.x + b.w > bounds.x + bounds.w) {
					break ITER;
				}
				o.x += gp.adv;
				line_width += gp.adv;
			}
		}
		line_end = off;
		if (line_end == line_start) unreachable("something went wrong in measuring the line");

		// with the line width calculate the right origin and layout the line
		origin.x = bounds.x;
		short next_line_x = bounds.x; // the x coordinate of the origin if the line_width is zero
		switch (anchor) {
		case TOP_LEFT: nextcase;
		case LEFT: nextcase;
		case BOTTOM_LEFT:
			// TODO: we didn't need to measure the line width with this alignment
			origin.x += 0;
			next_line_x += 0;
		case TOP: nextcase;
		case CENTER: nextcase;
		case BOTTOM:
			origin.x += (short)(bounds.w - line_width)/2+1;
			next_line_x += bounds.w/2;
		case TOP_RIGHT: nextcase;
		case RIGHT: nextcase;
		case BOTTOM_RIGHT:
			origin.x += (short)(bounds.w - line_width);
			next_line_x += bounds.w;
		}

		// reset the cursor to the line
		if (line_start <= cursor && cursor <= line_end) {
			cursor_rect.x = origin.x;
			cursor_rect.y = origin.y;
			cursor_rect.w = 0;
			if (cursor && text[cursor-1] == '\n') {
				cursor_rect.x = next_line_x;
				cursor_rect.y += line_height;
			}
		}

		Point line_origin = origin;

		// see the fixme when measuring the height
		//ctx.push_rect({.x = origin.x,.y=origin.y,.w=(short)line_width,.h=(short)string_height}, z_index, &&(Style){.bg=0xff000042u.@to_rgba()})!;
		String line = text[line_start:line_end-line_start];
		off = 0;
		for (usz x; (cp = str_to_codepoint(line[off..], &x)) != 0 && off < line.len; off += x) {
			Glyph* gp = font.get_glyph(cp)!;

			switch {
			case cp == '\t':
				origin.x += tab_width;
			case ascii::is_cntrl((char)cp):
				break;
			default:
				Rect b = {
					.x = origin.x + gp.ox,
					.y = origin.y + gp.oy + baseline,
					.w = gp.w,
					.h = gp.h
				};
				Rect uv = {
					.x = gp.u,
					.y = gp.v,
					.w = gp.w,
					.h = gp.h
				};
				ctx.push_sprite(b, uv, texture_id, z_index, hue)!;
				//ctx.push_rect(b, z_index, &&(Style){.bg=0x0000ff66u.@to_rgba()})!;

				origin.x += gp.adv;
			}

			if (line_start + off < cursor && text[cursor-1] != '\n') {
				cursor_rect.x = origin.x;
				cursor_rect.y = origin.y;
				cursor_rect.w = gp.adv;
			}
		}

		// done with the line
		line_start = line_end;
		origin.y += line_height + line_gap;
	} while(line_end < text.len);

	ctx.reset_scissor(z_index)!;

	return cursor_rect;
}
