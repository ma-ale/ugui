module ugui;

import schrift;
import grapheme;
import std::collections::map;
import std::core::mem;
import std::io;
import std::ascii;


// unicode code point, different type for a different hash
def Codepoint = uint;


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

const uint FONT_CACHED = 512;
def GlyphTable = map::HashMap(<Codepoint, Glyph>) @private;

fault UgFontError {
	TTF_LOAD_FAILED,
	MISSING_GLYPH,
	BAD_GLYPH_METRICS,
	RENDER_ERROR,
}

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

fn void! Font.load(&font, String name, ZString path, uint height, float scale)
{
	font.table.new_init(capacity: FONT_CACHED);
	font.id = name.hash();

	font.size = height*scale;

	font.sft = schrift::Sft{
		.xScale = (double)font.size,
		.yScale = (double)font.size,
		.flags = schrift::SFT_DOWNWARD_Y,
	};

	font.sft.font = schrift::loadfile(path);
	if (font.sft.font == null) {
		font.table.free();
		return UgFontError.TTF_LOAD_FAILED?;
	}

	schrift::SftLMetrics lmetrics;
	schrift::lmetrics(&font.sft, &lmetrics);
	font.ascender  = (float)lmetrics.ascender;
	font.descender = (float)lmetrics.descender;
	font.linegap   = (float)lmetrics.lineGap;
	//io::printfn("ascender:%d, descender:%d, linegap:%d", font.ascender, font.descender, font.linegap);

	// TODO: allocate buffer based on FONT_CACHED and the size of a sample letter
	//       like the letter 'A'
	ushort size = (ushort)font.size*256;
	font.atlas.new(font.id, ATLAS_GRAYSCALE, size, size)!;

	// preallocate the ASCII range
	for (char c = ' '; c < '~'; c++) {
		font.get_glyph((Codepoint)c)!;
	}
}

fn Glyph*! Font.get_glyph(&font, Codepoint code)
{
	Glyph*! gp;
	gp = font.table.get_ref(code);

	if (catch excuse = gp) {
		if (excuse != SearchResult.MISSING) {
			return excuse?;
		}
	} else {
		return gp;
	}

	// missing glyph, render and place into an atlas
	Glyph glyph;

	schrift::SftGlyph gid;
	schrift::SftGMetrics gmtx;

	if (schrift::lookup(&font.sft, code, &gid) < 0) {
		return UgFontError.MISSING_GLYPH?;
	}

	if (schrift::gmetrics(&font.sft, gid, &gmtx) < 0) {
		return UgFontError.BAD_GLYPH_METRICS?;
	}

	schrift::SftImage img = {
		.width = gmtx.minWidth,
		.height = gmtx.minHeight,
	};
	char[] pixels = mem::new_array(char, (usz)img.width * img.height);
	img.pixels = pixels;
	if (schrift::render(&font.sft, gid, img) < 0) {
		return UgFontError.RENDER_ERROR?;
	}

	glyph.code = code;
	glyph.w = (ushort)img.width;
	glyph.h = (ushort)img.height;
	glyph.ox = (short)gmtx.leftSideBearing;
	glyph.oy = (short)gmtx.yOffset;
	glyph.adv = (short)gmtx.advanceWidth;
	//io::printfn("code=%c, w=%d, h=%d, ox=%d, oy=%d, adv=%d",
	//    glyph.code, glyph.w, glyph.h, glyph.ox, glyph.oy, glyph.adv);

	Point uv = font.atlas.place(pixels, glyph.w, glyph.h)!;
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
	schrift::freefont(font.sft.font);
}

fn void! Ctx.load_font(&ctx, String name, ZString path, uint height, float scale = 1.0)
{
	return ctx.font.load(name, path, height, scale);
}

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

fn Point Ctx.center_text(&ctx, Rect text_bounds, Rect bounds)
{
	short dw = bounds.w - text_bounds.w;
	short dh = bounds.h - text_bounds.h;

	return Point{.x = dw/2, .y = dh/2};
}

// TODO: check if the font is present in the context
fn Id Ctx.get_font_id(&ctx, String label)
{
	return (Id)label.hash();
}
