module ugui;

import schrift;
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

<*
@param [&inout] font
@param [in] name
@param [&in] path
@require height > 0, scale > 0: "height and scale must be positive non-zero"
*>
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

<*
@param [&inout] font
*>
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

<*
@param [&inout] font
*>
fn void Font.free(&font)
{
	font.atlas.free();
	font.table.free();
	schrift::freefont(font.sft.font);
}


// ---------------------------------------------------------------------------------- //
//                           FONT LOAD AND QUERY                                      //
// ---------------------------------------------------------------------------------- //

<*
@param [&inout] ctx
@param [in] name
@param [&in] path
@require height > 0, scale > 0: "height and scale must be positive non-zero"
*>
fn void? Ctx.load_font(&ctx, String name, ZString path, uint height, float scale = 1.0)
{
	return ctx.font.load(name, path, height, scale);
}

<*
@param [&in] ctx
@param [in] label
*>
// TODO: check if the font is present in the context
fn Id Ctx.get_font_id(&ctx, String label) => (Id)label.hash();

<*
@param [&in] ctx
@param [in] name
*>
fn Atlas*? Ctx.get_font_atlas(&ctx, String name)
{
	// TODO: use the font name, for now there is only one font
	if (name.hash() != ctx.font.id) {
		return WRONG_ID?;
	}

	return &ctx.font.atlas;
}

<* @param [&in] font *>
fn int Font.line_height(&font) => (int)(font.ascender - font.descender + (float)0.5);
