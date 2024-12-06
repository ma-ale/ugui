module schrift;

def SftFont = void*;
def SftUChar = uint;
def SftGlyph = uint;

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

extern fn char* sft_version() @extern("sft_version");

extern fn SftFont sft_loadmem(void* mem, usz size) @extern("sft_loadmem");
extern fn SftFont sft_loadfile(char* filename) @extern("sft_loadfile");
extern fn void sft_freefont(SftFont font) @extern("sft_freefont");

extern fn int sft_lmetrics(Sft* sft, SftLMetrics* metrics) @extern("sft_lmetrics");
extern fn int sft_lookup(Sft* sft, SftUChar codepoint, SftGlyph* glyph) @extern("sft_lookup");
extern fn int sft_gmetrics(Sft* sft, SftGlyph glyph, SftGMetrics* metrics) @extern("sft_gmetrics");
extern fn int sft_kerning(Sft* sft, SftGlyph leftGlyph, SftGlyph rightGlyph, SftKerning* kerning) @extern("sft_kerning");
extern fn int sft_render(Sft* sft, SftGlyph glyph, SftImage image) @extern("sft_render");
