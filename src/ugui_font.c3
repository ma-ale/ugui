module ugui;

import schrift;
import std::collections::map;
import std::core::mem;
import std::io;

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
	Id atlas_id;
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
	GlyphTable table;

	float size;
	float ascender, descender, linegap; // Line Metrics
}


fn void! Ctx.font_load(&cxt, String path, uint height, float scale = 1)
{
	Font* font = ctx.font;
	font.table.new_init(capacity: FONT_CACHED);

	font.size = height*scale;

	font.sft = schrift::Sft{
		.xScale = (double)font.size,
		.yScale = (double)font.size,
		.flags = schrift::SFT_DOWNWARD_Y,
	};

	font.sft.font = schrift::loadfile(path);
	if (font.sft.font == null) {
		return UgFontError.TTF_LOAD_FAILED?;
	}

	schrift::SftLMetrics lmetrics;
	schrift::lmetrics(&font.sft, &lmetrics);
	font.ascender  = (float)lmetrics.ascender;
	font.descender = (float)lmetrics.descender;
	font.linegap   = (float)lmetrics.lineGap;
	//io::printfn("ascender:%d, descender:%d, linegap:%d", font.ascender, font.descender, font.linegap);
}

fn Glyph*! Ctx.get_glyph(&ctx, Codepoint code, bool* is_new = null)
{
	Font* font = &ctx.font;
	Glyph*! gp;
	gp = font.table.get_ref(code);

	if (catch excuse = gp) {
		if (excuse != SearchResult.MISSING) {
			return excuse?;
		}
	} else {
		if (is_new) { *is_new = false; }
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

	// TODO: allocate buffer based on FONT_CACHED and the size of a sample letter
	//       like the letter 'A'
	ushort size = (ushort)font.size*256;
	Point uv;
	Id id = ctx.place_sprite(&uv, ATLAS_ALPHA, pixels, glyph.w, glyph.h, size, size)!;
	glyph.atlas_id = id;
	glyph.u = uv.x;
	glyph.v = uv.y;

	mem::free(pixels);

	font.table.set(code, glyph);

	if (is_new) { *is_new = true; }
	return font.table.get_ref(code);
}

// FIXME: maybe some atlases should be exclusive to fonts
fn void Font.free(&font)
{
	schrift::freefont(font.sft.font);
}
