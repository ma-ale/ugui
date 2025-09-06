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

// TODO: change the name
// TODO: reorder to make smaller
struct TextInfo {
	Font* font;
	Rect bounds;
	String text;
	usz off;
	Size width, height;
	
	// current glyph info
	Point origin;
	Rect glyph_bounds;
	Rect glyph_uv;
	
	// cursor info
	usz cursor_idx;
	Point cursor_pos;
	
	// current text bounds
	Rect text_bounds;
}

<*
@require f != null
*>
fn void TextInfo.init(&self, Font* f, String s, Rect bounds = RECT_MAX)
{
	*self = {};
	self.font = f;
	self.text = s;
	self.bounds = bounds;
	self.origin = bounds.position();
	self.text_bounds = { .x = bounds.x, .y = bounds.y };
}

fn void TextInfo.reset(&self)
{
	TextInfo old = *self;
	self.init(old.font, old.text, old.bounds);
}

fn bool? TextInfo.place_glyph(&self, bool reflow)
{
	if (self.off >= self.text.len) {
		return false;
	}
	if (!self.origin.in_rect(self.bounds)) {
		return false;
	}

	short baseline = (short)self.font.ascender;
	short line_height = (short)self.font.ascender - (short)self.font.descender;
	short line_gap = (short)self.font.linegap;

	Codepoint cp;
	Glyph* gp;
	usz x;
	
	cp = str_to_codepoint(self.text[self.off..], &x);
	if (cp == 0) return false;
	self.off += x;

	if (ascii::is_cntrl((char)cp) == false) {
		gp = self.font.get_glyph(cp)!;
		self.glyph_uv = {
			.x = gp.u,
			.y = gp.v,
			.w = gp.w,
			.h = gp.h,
		};
		self.glyph_bounds = {
			.x = self.origin.x + gp.ox,
			.y = self.origin.y + gp.oy + baseline,
			.w = gp.w,
			.h = gp.h,
		};
		// try to wrap the text if the charcater goes outside of the bounds
		if (reflow && !self.bounds.contains(self.glyph_bounds)) {
			self.origin.y += line_height + line_gap;
			self.glyph_bounds.y += line_height + line_gap;

			self.origin.x = self.bounds.x;
			self.glyph_bounds.x = self.bounds.x;
		}

		// handle tab
		if (cp == '\t') {
			self.origin.x += gp.adv*TAB_SIZE;
		} else {
			self.origin.x += gp.adv;
		}

	} else if (cp == '\n'){
		self.origin.y += line_height + line_gap;
		self.origin.x = self.bounds.x;
	}

	self.text_bounds = containing_rect(self.text_bounds, self.glyph_bounds);

	if (self.off == self.cursor_idx) {
		self.cursor_pos = self.origin;
	}

	return true;
}

fn Rect? Ctx.get_text_bounds(&ctx, String text)
{
	TextInfo ti;
	ti.init(&ctx.font, text);
	while (ti.place_glyph(false)!);
	return ti.text_bounds;
}


struct TextSize {
	Size width, height;
}

// Measeure the size of a string.
// width.min: as if each word is broken up by a new line
// width.max: the width of the string left as-is
// height.min: the height of the string left as-is
// height.max: the height of the string with each word broken up by a new line
fn TextSize? Ctx.measure_string(&ctx, String text)
{
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
			word_width += gp.w + gp.ox;
			if (off < text.len) word_width += gp.adv;
		}
	}
	// end of string is also end of word
	if (word_width > ts.width.min) ts.width.min = word_width;

	ts.width.max = bounds.w;
	ts.height.min = bounds.h;
	ts.height.max = words * line_height + line_gap * (words-1);

	return ts;
}
