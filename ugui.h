#ifndef _UGUI_H
#define _UGUI_H

#include <stdint.h>

typedef struct {
	int32_t x, y, w, h;
} UgRect;

typedef struct {
	int32_t x, y;
} UgPoint;

typedef struct {
	uint8_t r, g, b, a;
} UgColor;

typedef uint64_t UgId;

typedef enum {
	ETYPE_NONE = 0,
	ETYPE_DIV,
	ETYPE_BUTTON,
} UgElemType;

enum UgElemFlags {
	ELEM_UPDATED  = 1 << 0,
	ELEM_HASFOCUS = 1 << 1,
};

enum UgElemEvent {
	EVENT_KEY_PRESS     = 1 << 0,
	EVENT_KEY_RELEASE   = 1 << 1,
	EVENT_KEY_HOLD      = 1 << 2,
	EVENT_MOUSE_HOVER   = 1 << 3,
	EVENT_MOUSE_PRESS   = 1 << 4,
	EVENT_MOUSE_RELEASE = 1 << 5,
	EVENT_MOUSE_HOLD    = 1 << 6,
};

typedef struct {
	UgId       id;
	uint32_t   flags;
	uint32_t   event;
	UgRect     rect;
	UgElemType type;

	// type-specific fields
	union {
		struct UgDiv {
			enum {
				DIV_LAYOUT_ROW = 0,
				DIV_LAYOUT_COLUMN,
				DIV_LAYOUT_FLOATING,
			} layout;

			UgPoint origin_r, origin_c;
			UgColor color_bg;
		} div; // Div
	};
} UgElem;

// TODO: add a packed flag
// TODO: add a fill index to skip some searching for free spots

typedef struct {
	int   size, elements;
	UgId *vector; // vector of element ids
	int  *refs, *ordered_refs;
} UgTree;

typedef struct {
	struct _IdTable *table;
	UgElem          *array;
	uint64_t        *present, *used;
	int              cycles;
} UgElemCache;

typedef struct _UgCtx UgCtx;

// tree implementation
int  ug_tree_init(UgTree *tree, unsigned int size);
int  ug_tree_pack(UgTree *tree);
int  ug_tree_resize(UgTree *tree, unsigned int newsize);
int  ug_tree_add(UgTree *tree, UgId elem, int parent);
int  ug_tree_prune(UgTree *tree, int ref);
int  ug_tree_subtree_size(UgTree *tree, int ref);
int  ug_tree_children_it(UgTree *tree, int parent, int *cursor);
int  ug_tree_level_order_it(UgTree *tree, int ref, int *cursor);
int  ug_tree_parentof(UgTree *tree, int node);
int  ug_tree_destroy(UgTree *tree);
UgId ug_tree_get(UgTree *tree, int node);

// cache implementation
UgElemCache ug_cache_init(void);
void        ug_cache_free(UgElemCache *cache);
UgElem     *ug_cache_search(UgElemCache *cache, UgId id);
UgElem *ug_cache_insert_new(UgElemCache *cache, const UgElem *g, uint32_t *index);

int ug_init(UgCtx *ctx);
int ug_destroy(UgCtx *ctx);
int ug_frame_begin(UgCtx *ctx);
int ug_frame_end(UgCtx *ctx);

#endif // _UGUI_H
