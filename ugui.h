#ifndef _UGUI_H
#define _UGUI_H

/* Point Coordinate */

// coordinate type, or how it is measured
enum {
	UG_CTYPE_PX  = 0x0,
	UG_CTYPE_MM  = 0x1,
	UG_CTYPE_REL = 0x2,
};

// coordinate anchor, or where it refers
enum {
	UG_CANCHOR_TOP     = 0x0, // x coordinates
	UG_CANCHOR_LEFT    = 0x0,
	UG_CANCHOR_BOTTOM  = 0x1, // y coordinates
	UG_CANCHOR_RIGHT   = 0x1,
	UG_CANCHOR_VCENTER = 0x2, // for positions it should be centered 
	UG_CANCHOR_HCENTER = 0x2,
};

struct _ug_pt_flags {
	unsigned long int _:56;
	unsigned long int t:4;
	unsigned long int a:4;
};

typedef struct {
	// first coordinate
	union {
		union {
			int x;
			struct _ug_pt_flags fx;
		};
		union {
			int w;
			struct _ug_pt_flags fw;
		};
		union {
			int m;
			struct _ug_pt_flags fm;
		};
	};
	// second coordinate
	union {
		union {
			int y;
			struct _ug_pt_flags fy;
		};
		union {
			int h;
			struct _ug_pt_flags fh;
		};
		union {
			int a;
			struct _ug_pt_flags fa;
		};
	};	
} ug_coord_t;

// TODO: define stroke style (f.s)
typedef struct {
	int size;
	struct {
		// type of size
		unsigned char t:4;
		// stroke style
		unsigned char s:4;
	} f;
} ug_stroke_t;
//---//

/* RGBA Color type */
typedef struct {
	unsigned char a;
	unsigned char b;
	unsigned char g;
	unsigned char r;
} ug_color_t;
//---//

/* simple position structure */
struct ug_vec2 {
	int x, y;
};
//---//

/* Mouse button mask */
enum ug_mouse_btn {
	UG_MOUSEBTN_LEFT   = 1,
	UG_MOUSEBTN_MIDDLE = 2,
	UG_MOUSEBTN_RIGHT  = 4,
	UG_MOUSEBTN_4      = 8,
	UG_MOUSEBTN_5      = 16,
};
//---//

/* event structure */
typedef enum  {
	UG_EV_WINDOWMOVE,
	UG_EV_WINDOWRESIZE,
	UG_EV_WINDOWSHOW,
	UG_EV_MOUSEMOVE,
	UG_EV_MOUSEDOWN,
	UG_EV_MOUSEUP,
	UG_EV_KEYDOWN,
	UG_EV_KEYUP,
} ug_event_type_t;

typedef struct {
	ug_event_type_t type;
	union {
		int x;
		int w;
		unsigned int code;
	};
	union {
		int y;
		int h;
		unsigned int mask;
	};
} ug_event_t;
//---//

/* Primitive element type */
typedef enum {
	UG_E_RECT = 0,
	UG_E_TRIANGLE,
	UG_E_DOT,
	UG_E_LINE,
	UG_E_ARC,
	UG_E_TEXT,
	UG_E_SPRITE,
} ug_element_type_t;

typedef struct {
	ug_coord_t size;
	ug_coord_t pos;
	ug_color_t color;
} ug_rect_t;

typedef struct {
	ug_coord_t size;
	ug_coord_t pos;
	ug_color_t color;
} ug_triangle_t;

typedef struct {
	ug_stroke_t stroke;
	ug_coord_t pos;
	ug_color_t color;
} ug_dot_t;

typedef struct {
	ug_stroke_t stroke;
	ug_coord_t vert[2];
	ug_color_t color;
} ug_line_t;

typedef struct {
	ug_stroke_t stroke;
	ug_coord_t vert[3];
	ug_color_t color;
} ug_arc_t;

// draw text from view[start] to view[end]
typedef struct {
	ug_stroke_t stroke;
	ug_coord_t pos;
	ug_color_t color;
	const char *view;
	int start;
	int end;
} ug_text_t;

// all sprites have to be mapped into memory, map is an array of width x height
// bytes, the type is specified by the user
typedef struct {
	ug_coord_t pos;
	void *map;
	int width;
	int height;
} ug_sprite_t;


// data is the actual element data, it has to be cast to the right element specified
// by type and is variable size so that no memory is wasted, size is the size in
// bytes of data + id + size + type
typedef struct {
	ug_element_type_t type;
	unsigned int size;
	unsigned int id;
	unsigned char data[];
} ug_element_t;
//---//

/* Global context */
// one context per phisical window
// a phisical window can be anything, but here it basically represents the true
// surface where things are drawn into, a window has a scale, dpi and ppm 
// (pixel per mm), only the latter is truly needed, the user sets these variables
// and has to take care of updating them when needed
typedef struct {
	unsigned int window_id;
	float scale, dpi, ppm;
	// the user pushes the things that he wants to draw onto the element stack,
	// which contains all the primitives needed to draw the wanted element
	unsigned char *e_stack;
	unsigned int e_size;
	unsigned int e_idx;
	// the element which has focus
	unsigned int focus_id;
	// the element that we are hovering
	unsigned int hover_id;
	// count the frames for fun
	unsigned long int frame;
	// mouse data
	struct {
		struct ug_vec2 pos;
		struct ug_vec2 last_pos;
		struct ug_vec2 delta;
		struct ug_vec2 scroll_delta;
		// down/pressed masks get updated on mousedown, whereas down_mask
		// only on mouseup, so the masks differ by the buttons that were
		// released
		// FIXME: is this the best way to approach this?
		unsigned char down_mask;
		unsigned char press_mask;
	} mouse;
	// keyboard key pressed
	struct {
		unsigned char down_mask;
		unsigned char press_mask;
	} key;
	// input text buffer
	char input_text[32];
} ug_ctx_t;
//---//

// creates a new context, fills with default values, ctx is ready for ug_start()
ug_ctx_t *ug_new_ctx(void);
void ug_free_ctx(ug_ctx_t *ctx);
// updates the context with user information
int ug_update_ctx(ug_ctx_t *ctx,
                  unsigned int window_id,
	          float scale,
	          float dpi,
	          float ppm
	         );

// register inputs
void ug_input_mousedown(ug_ctx_t *ctx, int x, int y, unsigned char btn);
void ug_input_mouseup(ug_ctx_t *ctx, int x, int y, unsigned char btn);
void ug_input_mousemove(ug_ctx_t *ctx, int x, int y);
void ug_input_scroll(ug_ctx_t *ctx, int x, int y);
void ug_input_keydown(ug_ctx_t *ctx, int key);
void ug_input_keyup(ug_ctx_t *ctx, int key);
void ug_input_text(ug_ctx_t *ctx, const char *text);

// between begin and end the user draws
int ug_begin(ug_ctx_t *ctx);
int ug_end(ug_ctx_t *ctx);


#endif
