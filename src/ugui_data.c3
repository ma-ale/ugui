module ugui;

import std::core::string;

import vtree;
import cache;
import fifo;


struct Rect {
	short x, y, w, h;
}

struct Point {
	short x, y;
}

struct Color{
	char r, g, b, a;
}

// element ids are just long ints
def Id = usz;

enum ElemType {
	ETYPE_NONE,
	ETYPE_DIV,
	ETYPE_BUTTON,
	ETYPE_SLIDER,
	ETYPE_TEXT,
}

bitstruct ElemFlags : uint {
	bool updated : 0;
	bool has_focus : 1;
	bool is_new : 2;
}

bitstruct ElemEvents : uint {
	bool key_press     : 0;
	bool key_release   : 1;
	bool key_hold      : 2;
	bool mouse_hover   : 3;
	bool mouse_press   : 4;
	bool mouse_release : 5;
	bool mouse_hold    : 6;
	bool update        : 7;
}

enum DivLayout {
	LAYOUT_ROW,
	LAYOUT_COLUMN,
	LAYOUT_FLOATING,
}

// div element
struct ElemDiv {
	DivLayout layout;
	struct scroll {
		bool can_x;
		bool can_y;
		bool on_x;
		bool on_y;
		float value_x;
		float value_y;
	}
	Rect children_bounds;
	Point origin_r, origin_c;
	Color color_bg;
}

// slider element
struct ElemSlider {
	float value;
	Rect handle;
}

struct ElemText {
	char* str;
}

// element structure
struct Elem {
	Id id;
	ElemFlags flags;
	ElemEvents events;
	Rect bounds;
	ElemType type;
	union {
		ElemDiv div;
		ElemSlider slider;
		ElemText text;
	}
}


// relationships between elements are stored in a tree, it stores just the ids
def IdTree = vtree::VTree(<Id>) @private;

// elements themselves are kept in a cache
const uint MAX_ELEMENTS = 1024;
def ElemCache = cache::Cache(<Id, Elem, MAX_ELEMENTS>) @private;

def CmdQueue = fifo::Fifo(<Cmd>);

fault UgError {
	INVALID_SIZE,
	EVENT_UNSUPPORTED,
	UNEXPECTED_ELEMENT,
}

macro uint_to_rgba(uint u) {
	return Color{
		.r = (char)((u >> 24) & 0xff),
		.g = (char)((u >> 16) & 0xff),
		.b = (char)((u >> 8) & 0xff),
		.a = (char)((u >> 0) & 0xff)
	};
}

const Rect DIV_FILL = { .x = 0, .y = 0, .w = 0, .h = 0 };

macro abs(a) { return a < 0 ? -a : a; }
macro clamp(x, min, max) { return x < min ? min : (x > max ? max : x); }

const uint STACK_STEP = 10;
const uint MAX_ELEMS  = 128;
const uint MAX_CMDS   = 256;
const uint ROOT_ID    = 1;

enum Layout {
	ROW,
	COLUMN,
	FLOATING
}

// global style, similar to the css box model
struct Style { // css box model
	Rect  padding;
	Rect  border;
	Rect  margin;
	Color bgcolor; // background color
	Color fgcolor; // foreground color
	Color brcolor; // border color
	ushort radius;
}


struct Ctx {
	Layout layout;
	IdTree tree;
	ElemCache cache;
	CmdQueue cmd_queue;
	// total size in pixels of the context
	ushort width, height;
	Style style;
	Font font;

	bool has_focus;
	struct input {
		InputEvents events;
		struct mouse {
			Point pos, delta;
			// mouse_down:      bitmap of mouse buttons that are held
			// mouse_updated:   bitmap of mouse buttons that have been updated
			// mouse_released = mouse_updated & ~mouse_down
			// mouse_pressed  = mouse_updated & mouse_down
			MouseButtons down;
			MouseButtons updated;
		}
	}

	isz active_div; // tree node indicating the current active div
}

macro point_in_rect(Point p, Rect r)
{
	return (p.x >= r.x && p.x <= r.x + r.w) && (p.y >= r.y && p.y <= r.y + r.h);
}

// return true if rect a contains b
macro rect_contains(Rect a, Rect b)
{
	return (a.x <= b.x && a.y <= b.y && a.x+a.w >= b.x+b.w && a.y+a.h >= b.y+b.h);
}

macro rect_intersection(Rect a, Rect b)
{
	return Rect{
		.x = (short)max(a.x, b.x),
		.y = (short)max(a.y, b.y),
		.w = (short)min(a.x+a.w, b.x+b.w) - (short)max(a.x, b.x),
		.h = (short)min(a.y+a.h, b.y+b.h) - (short)max(a.y, b.y),
	};
}

// rect intersection not null
macro rect_collision(Rect a, Rect b)
{
	return !(a.x > b.x+b.w || a.x+a.w < b.x || a.y > b.y+b.h || a.y+a.h < b.y);
}
