#ifndef _UG_HEADER
#define _UG_HEADER

#define UG_STACK(T)    struct { T *items; int idx, size, sorted; }
#define BIT(n)         (1 << n)
#define RGBA_FORMAT(x) { .a=x&0xff, .b=(x>>8)&0xff, .g=(x>>16)&0xff, .r=(x>>24)&0xff }
#define RGB_FORMAT(x)  { .a=0xff, .b=x&0xff, .g=(x>>8)&0xff, .r=(x>>16)&0xff }
#define SIZE_PX(x)     { .size.i=x, .unit=UG_UNIT_PX }
#define SIZE_MM(x)     { .size.f=x, .unit=UG_UNIT_MM }
#define SIZE_PT(x)     { .size.f=x, .unit=UG_UNIT_PT }

// basic types
typedef unsigned int                                       ug_id_t; 
typedef struct { union {int x, w;}; union {int y, h;}; }   ug_vec2_t;
typedef struct { unsigned char a, b, g, r; }               ug_color_t;
typedef struct { int x, y, w, h; }                         ug_rect_t;
typedef struct { union {int i; float f;} size; int unit; } ug_size_t;
// div has information about the phisical dimension
typedef struct { ug_size_t x, y, w, h;}                    ug_div_t;

typedef enum { 
	UG_UNIT_PX = 0,
	UG_UNIT_MM,
	UG_UNIT_PT,
} ug_unit_t;

// container type, a container is an entity that contains layouts, a container has
// a haight a width and their maximum values, in essence a container is a rectangular
// area that can be resized and sits somewhere on the drawable region
// the z index of a container is determined by it's position on the stack
typedef struct {
	ug_id_t id;
	ug_rect_t rect;
	// absolute position rect
	ug_rect_t rca;
	ug_vec2_t max_size;
	unsigned int flags;
} ug_container_t;

// the container flags
enum {
	UG_CNT_FLOATING      = BIT(0), // is on top of everything else
	UG_CNT_RESIZE_RIGHT  = BIT(1), // can be resized from the right border
	UG_CNT_RESIZE_BOTTOM = BIT(2), // can be resized from the bottom border
	UG_CNT_RESIZE_LEFT   = BIT(3), // can be resized from the left border
	UG_CNT_RESIZE_TOP    = BIT(4), // can be resized from the top border
	UG_CNT_SCROLL_X      = BIT(5), // can have horizontal scrolling
	UG_CNT_SCROLL_Y      = BIT(6), // can have vertical scrolling
	UG_CNT_MOVABLE       = BIT(7), // can be moved around
	// container state
	CNT_STATE_NONE       = BIT(30),
	CNT_STATE_MOVING     = BIT(29),
	CNT_STATE_RESIZE_T   = BIT(28),
	CNT_STATE_RESIZE_B   = BIT(27),
	CNT_STATE_RESIZE_L   = BIT(26),
	CNT_STATE_RESIZE_R   = BIT(25),
	CNT_STATE_DELETE     = BIT(24), // The container is marked for removal
};

// style, defines default height, width, color, margins, borders, etc
// all dimensions should be taken as a reference when doing the layout since
// ultimately it's the layout that decides them. For example when deciding how to
// allocate space one can say that the default size of a region that allocates a
// slider has the style's default dimensions for a slider
typedef struct {
	struct { 
		ug_color_t color, alt_color;
		ug_size_t size, alt_size;
	} text;

	struct { 
		ug_color_t bg_color;
		struct {
			ug_size_t t, b, l, r;
			ug_color_t color;
		} border;
		// titlebar only gets applied to movable containers
		struct {
			ug_size_t  height;
			ug_color_t bg_color;
		} titlebar;
	} cnt;
	
	// a button should stand out, hence the different colors
	struct {
		ug_color_t bg_color, hover_color, active_color;
	} button;

	// a checkbox should be smaller than a button
	struct {
		ug_size_t width, height, tick_size;
		ug_color_t tick_color;
	} checkbox;

	// a slider can be thinner and generally wider than a button
	struct {
		ug_size_t width, height;
	} slider;

	// the text color, dimension and the background of a text display can be
	// different
	struct {
		ug_color_t text_color, bg_color;
		ug_size_t text_size;
	} textdisplay;

} ug_style_t;


// render commands
typedef struct {
	unsigned int type;
	union {
		struct {
			int x, y, w, h;
			ug_color_t color;
		} rect;
	};
} ug_cmd_t;

typedef enum {
	UG_CMD_NULL = 0,
	UG_CMD_RECT,
} ug_cmd_type_t;

// window side
enum {
	UG_SIDE_TOP = 0,
	UG_SIDE_BOTTOM,
	UG_SIDE_LEFT,
	UG_SIDE_RIGHT,
};

// mouse buttons
enum {
	UG_BTN_LEFT   = BIT(0),
	UG_BTN_MIDDLE = BIT(1),
	UG_BTN_RIGHT  = BIT(2),
	UG_BTN_4      = BIT(3),
	UG_BTN_5      = BIT(4),
};

// context
typedef struct {
	// some style information
	const ug_style_t *style;
	// style_px is a style cache where all measurements are already in pixels
	const ug_style_t *style_px;
	// ppi: pixels per inch
	// ppm: pixels per millimeter
	// ppd: pixels per dot
	float ppi, ppm, ppd;
	float last_ppi, last_ppm, last_ppd;
	// containers need to know how big the "main container" is so that all
	// the relative positioning work
	ug_vec2_t size;
	ug_rect_t origin;
	// which context and element we are hovering
	struct {
		ug_id_t cnt, elem;
		ug_id_t cnt_last, elem_last;
	} hover;
	// active is updated on mousedown and released on mouseup
	// the id of the "active" element, active means different things for
	// different elements, for exaple active for a button means to be pressed,
	// and for a text box it means to be focused
	struct {
		ug_id_t cnt, elem;
	} active;
	struct {
		ug_id_t cnt, elem;
	} last_active;
	// count the frames for fun
	unsigned long int frame;
	// mouse data
	struct {
		ug_vec2_t pos;
		ug_vec2_t last_pos;
		ug_vec2_t delta;
		ug_vec2_t scroll_delta;
		// mouse.update: a mask of the mouse buttons that are being updated
		unsigned char update;
		// mouse.hold: a mask of the buttons that are being held
		unsigned char hold;
	} mouse;
	// keyboard key pressed
	struct {
		unsigned char update;
		unsigned char hold;
	} key;
	// input text buffer
	char input_text[32];
	// stacks
	UG_STACK(ug_container_t) cnt_stack;
	UG_STACK(ug_cmd_t) cmd_stack;
} ug_ctx_t;


// context initialization
ug_ctx_t *ug_ctx_new(void);
void ug_ctx_free(ug_ctx_t *ctx);
// updates the context with user information
int ug_ctx_set_displayinfo(ug_ctx_t *ctx, float scale, float ppi);
int ug_ctx_set_drawableregion(ug_ctx_t *ctx, ug_vec2_t size);
int ug_ctx_set_style(ug_ctx_t *ctx, const ug_style_t *style);


// define containers, name is used as a salt for the container id, all sizes are
// the default ones, resizing is done automagically with internal state

// a floating container can be placed anywhere and can be resized, acts like a
// window inside another window
int ug_container_floating(ug_ctx_t *ctx, const char *name, ug_div_t div);
// like a floating container but cannot be resized
int ug_container_popup(ug_ctx_t *ctx, const char *name, ug_div_t div);
// a menu bar is a container of fixed height, cannot be resized and sits at the
// top of the window
int ug_container_menu_bar(ug_ctx_t *ctx, const char *name, ug_size_t height);
// a sidebar is a variable size container anchored to one side of the window
int ug_container_sidebar(ug_ctx_t *ctx, const char *name, ug_size_t size, int side);
// a body is a container that scales with the window, sits at it's center and cannot
// be resized, it also fills all the available space
int ug_container_body(ug_ctx_t *ctx, const char *name);

// Input functions
int ug_input_mousemove(ug_ctx_t *ctx, int x, int y);
int ug_input_mousedown(ug_ctx_t *ctx, unsigned int mask);
int ug_input_mouseup(ug_ctx_t *ctx, unsigned int mask);
int ug_input_scroll(ug_ctx_t *ctx, int x, int y);
// TODO: other input functions

// Frame handling
int ug_frame_begin(ug_ctx_t *ctx);
int ug_frame_end(ug_ctx_t *ctx);


#undef UG_STACK
#undef BIT

#endif
