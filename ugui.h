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

typedef enum {
	ETYPE_NONE = 0,
	ETYPE_BUTTON,
	ETYPE_TEXT,
	ETYPE_SCROLL,
	ETYPE_SLIDER,
} UgElemType;

typedef struct {
	uint64_t id;
	UgRect rec;
	union {
		uint32_t type_int;
		UgElemType type;
	};
} UgElem;

// TODO: add a packed flag
// TODO: add a fill index to skip some searching for free spots

typedef struct {
	int size, elements;
	uint32_t *vector; // vector of element ids
	int *refs, *ordered_refs;
} UgTree;

typedef struct {
	UgTree tree;
} UgCtx;

// tree implementation
int ug_tree_init(UgTree *tree, unsigned int size); 
int ug_tree_pack(UgTree *tree);
int ug_tree_resize(UgTree *tree, unsigned int newsize);
int ug_tree_add(UgTree *tree, uint32_t elem, int parent);
int ug_tree_prune(UgTree *tree, int ref);
int ug_tree_subtree_size(UgTree *tree, int ref);
int ug_tree_children_it(UgTree *tree, int parent, int *cursor);
int ug_tree_level_order_it(UgTree *tree, int ref, int *cursor);
int ug_tree_destroy(UgTree *tree);

int ug_init(UgCtx *ctx);
int ug_destroy(UgCtx *ctx);

#endif // _UGUI_H

