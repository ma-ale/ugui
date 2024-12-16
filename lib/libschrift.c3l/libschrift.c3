module schrift;

def SftFont = void*;
def SftUChar = uint;
def SftGlyph = uint;

const int SFT_DOWNWARD_Y = 0x01;

struct Sft
{
	SftFont   font;
	double    xScale;
	double    yScale;
	double    xOffset;
	double    yOffset;
	int       flags;
}

struct SftLMetrics
{
	double ascender;
	double descender;
	double lineGap;
}

struct SftGMetrics
{
	double advanceWidth;
	double leftSideBearing;
	int    yOffset;
	int    minWidth;
	int    minHeight;
}

struct SftKerning
{
	double xShift;
	double yShift;
}

struct SftImage
{
	void *pixels;
	int   width;
	int   height;
}

extern fn ZString sft_version() @extern("sft_version");

extern fn SftFont loadmem(void* mem, usz size) @extern("sft_loadmem");
extern fn SftFont loadfile(ZString filename) @extern("sft_loadfile");
extern fn void freefont(SftFont font) @extern("sft_freefont");

extern fn int lmetrics(Sft* sft, SftLMetrics* metrics) @extern("sft_lmetrics");
extern fn int lookup(Sft* sft, SftUChar codepoint, SftGlyph* glyph) @extern("sft_lookup");
extern fn int gmetrics(Sft* sft, SftGlyph glyph, SftGMetrics* metrics) @extern("sft_gmetrics");
extern fn int kerning(Sft* sft, SftGlyph leftGlyph, SftGlyph rightGlyph, SftKerning* kerning) @extern("sft_kerning");
extern fn int render(Sft* sft, SftGlyph glyph, SftImage image) @extern("sft_render");
