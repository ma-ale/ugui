module ugui;

import schrift;
import std::collections::map;
import std::core::mem;

// unicode code point, different type for a different hash
def Codepoint = uint;


/* width and height of a glyph contain the kering advance
 * (u,v)
 *   +-------------*---+ -
 *   |       ^     |   | ^
 *   |       |oy   |   | |
 *   |       v     |   | |
 *   |      .ii.   |   | |
 *   |     @@@@@@. |<->| |
 *   |    V@Mio@@o |adv| |h
 *   |    :i.  V@V |   | |
 *   |      :oM@@M |   | |
 *   |    :@@@MM@M |   | |
 *   |    @@o  o@M |   | |
 *   |<->:@@.  M@M |   | |
 *   |ox  @@@o@@@@ |   | |
 *   |    :M@@V:@@.|   | v
 *   +-------------*---+ -
 *   |<------------->|
 *           w
 */
struct Glyph {
	Codepoint code;
	ushort u, v;
	ushort w, h;
	short adv, ox, oy;
	short idx; // atlas index
}

const uint FONT_CACHED = 512;
def GlyphTable = map::HashMap(<Codepoint, Glyph>) @private;

fault UgFontError {
	TTF_LOAD_FAILED,
	MISSING_GLYPH,
	BAD_GLYPH_METRICS,
	RENDER_ERROR,
}

fault UgAtlasError {
	CANNOT_PLACE,
}

// black and white atlas
struct AtlasBW {
	ushort width, height;
	char[] buffer;

	Point row;
	ushort row_h;
}

struct Font {
	schrift::Sft sft;
	String path;
	GlyphTable table;

	float size;
	float ascender, descender, linegap; // Line Metrics
	AtlasBW[] atlas;
}

fn void! AtlasBW.new(&atlas, ushort width, ushort height)
{
	atlas.width = width;
	atlas.height = height;
	atlas.buffer = mem::new_array(char, (usz)atlas.width*atlas.height);
}

fn void AtlasBW.free(&atlas)
{
	free(atlas.buffer);
}

// place a rect inside the atlas
// uses a row first algorithm
// TODO: use a skyline algorithm https://jvernay.fr/en/blog/skyline-2d-packer/implementation/
fn Point! AtlasBW.place(&atlas, char[] pixels, ushort w, ushort h)
{
	Point p;

	if (atlas.row.x + w <= atlas.width && atlas.row.y + h <= atlas.height) {
		p = atlas.row;
	} else {
		atlas.row.x = 0;
		atlas.row.y = atlas.row.y + atlas.row_h;
		atlas.row_h = 0;
		if (atlas.row.x + w <= atlas.width && atlas.row.y + h <= atlas.height) {
			p = atlas.row;
		} else {
			return UgAtlasError.CANNOT_PLACE?;
		}
	}

	for (usz y = 0; y < h; y++) {
		for (usz x = 0; x < w; x++) {
			atlas.buffer[(usz)(p.y+y)*atlas.width + (p.x+x)] = pixels[y*w + x];
		}
	}

	atlas.row.x += w;
	if (h > atlas.row_h) {
		atlas.row_h = h;
	}

	return p;
}

fn void! Font.load(&font, String path, uint height, float scale = 1)
{
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

	// TODO: allocate buffer based on FONT_CACHED and the size of a sample letter
	//       like the letter 'A'
	font.atlas = mem::new_array(AtlasBW, 1);
	ushort size = (ushort)font.size*512;
	font.atlas[0].new(size, size)!;
	
	// preallocate the ASCII range
//	for (char c = ' '; c < '~'; c++) {
//		font.get_glyph((Codepoint)c)!;
//	}
}

fn Glyph*! Font.get_glyph(&font, Codepoint code, bool* is_new = null)
{
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
	glyph.ox = (short)-gmtx.leftSideBearing;
	glyph.oy = (short)-gmtx.yOffset;
	glyph.adv = (short)gmtx.advanceWidth;

	Point uv = font.atlas[0].place(pixels, glyph.w, glyph.h)!;
	glyph.idx = 0;
	glyph.u = uv.x;
	glyph.v = uv.y;

	mem::free(pixels);

	font.table.set(code, glyph);

	if (is_new) { *is_new = true; }
	return font.table.get_ref(code);
}

fn void Font.free(&font)
{
	foreach (atlas: font.atlas) {
		atlas.free();
	}
	schrift::freefont(font.sft.font);
}
