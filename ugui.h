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
	ELEM_UPDATED = 1 << 0,
};

typedef struct {
	UgId     id;
	uint32_t flags;
	UgRect   rect;

	union {
		uint32_t   type_int;
		UgElemType type;
	};

	// type-specific fields
	union {
		struct {
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
int ug_tree_init(UgTree *tree, unsigned int size);
int ug_tree_pack(UgTree *tree);
int ug_tree_resize(UgTree *tree, unsigned int newsize);
int ug_tree_add(UgTree *tree, UgId elem, int parent);
int ug_tree_prune(UgTree *tree, int ref);
int ug_tree_subtree_size(UgTree *tree, int ref);
int ug_tree_children_it(UgTree *tree, int parent, int *cursor);
int ug_tree_level_order_it(UgTree *tree, int ref, int *cursor);
int ug_tree_parentof(UgTree *tree, int node);
int ug_tree_destroy(UgTree *tree);

// cache implementation
UgElemCache ug_cache_init(void);
void        ug_cache_free(UgElemCache *cache);
UgElem     *ug_cache_search(UgElemCache *cache, UgId id);
UgElem     *ug_cache_insert(UgElemCache *cache, const UgElem *g, uint32_t *index);

int ug_init(UgCtx *ctx);
int ug_destroy(UgCtx *ctx);
int ug_frame_begin(UgCtx *ctx);
int ug_frame_end(UgCtx *ctx);

#endif // _UGUI_H
